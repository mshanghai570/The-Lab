//
//  Server.swift
//  feather
//
//  Created by samara on 22.08.2024.
//  Copyright © 2024 Lakr Aream. All Rights Reserved.
//  ORIGINALLY LICENSED UNDER GPL-3.0, MODIFIED FOR USE FOR FEATHER
//

import Foundation
import Vapor
import NIOSSL
import NIOTLS
import SwiftUI
import IDeviceSwift

// MARK: - Errors

/// Errors surfaced by the in-process install server.
struct InstallServerError: LocalizedError {
	let message: String
	var errorDescription: String? { message }
}

/// What the install listener observed during the last attempt, captured on the
/// Vapor event loop and read from the UI. Used to categorise a failed install:
/// did SpringBoard's manifest request ever reach the listener? Did the payload
/// stream start?
final class InstallServerTrace: @unchecked Sendable {
	private let lock = NSLock()
	private var _manifestRequested = false
	private var _payloadRequested = false
	private var _imageRequested = false
	private var _lastRequest: String?

	func recordManifest(_ path: String) {
		lock.withLock {
			_manifestRequested = true
			_lastRequest = path
		}
	}

	func recordPayload(_ path: String) {
		lock.withLock {
			_payloadRequested = true
			_lastRequest = path
		}
	}

	func recordImage(_ path: String) {
		lock.withLock {
			_imageRequested = true
			_lastRequest = path
		}
	}

	var snapshot: (manifest: Bool, payload: Bool, image: Bool, lastRequest: String?) {
		lock.withLock { (_manifestRequested, _payloadRequested, _imageRequested, _lastRequest) }
	}

	func reset() {
		lock.withLock {
			_manifestRequested = false
			_payloadRequested = false
			_imageRequested = false
			_lastRequest = nil
		}
	}
}

// MARK: - Class
class ServerInstaller: Identifiable, ObservableObject {
	let id = UUID()
	let port = Int.random(in: 4000...8000)
	private var _needsShutdown = false
	
	var packageUrl: URL?
	/// Where the listener actually bound (read from the live socket), so the
	/// diagnosis alert can compare it against the advertised URLs.
	private(set) var boundAddress = "unknown"
	/// What the listener saw during this attempt (see `InstallServerTrace`).
	let trace = InstallServerTrace()
	/// True only when the listener actually speaks TLS. Only the External (2)
	/// server type serves TLS (the backloop cert). Fully Local (0) and Semi
	/// Local (1) always serve plain HTTP: their manifests are fetched from
	/// palera.in over HTTPS, so the listener itself never needs TLS. This must
	/// stay in sync with the listener's `tlsConfiguration` or the manifest
	/// scheme won't match the socket.
	var usesTLS: Bool {
		guard getServerMethod() == 2 else { return false }
		return (try? tls()) != nil
	}
	var app: AppInfoPresentable
	@ObservedObject var viewModel: InstallerStatusViewModel
	private var _server: Application?

	init(app: AppInfoPresentable, viewModel: InstallerStatusViewModel) throws {
		self.app = app
		self.viewModel = viewModel
		try _setup()
		try _configureRoutes()
		_server?.logger.info("Starting install server on port \(port) (method \(getServerMethod()), tls \(usesTLS))")
		try _server?.server.start()
		_needsShutdown = true
		boundAddress = (_server?.server as? HTTPServer)?.localAddress?.description ?? "unknown"
		_server?.logger.info("Install server running — bound to \(boundAddress), advertised page \(pageEndpoint.absoluteString), payload \(payloadEndpoint.absoluteString)")
	}
	
	deinit {
		_shutdownServer()
	}
	
	private func _setup() throws {
		// Propagate setup failures instead of swallowing them: a nil server
		// would leave the install flow pointing at a dead 127.0.0.1 listener
		// with no in-app error surfaced.
		self._server = try setupApp(port: port)
	}
		
	private func _configureRoutes() throws {
		_server?.get("*") { [weak self] req in
			guard let self else { return Response(status: .badGateway) }
			// Vapor exposes its own logger on the request; swift-log's Logger
			// shadows the OSLog extension in this file.
			let host = req.headers.first(name: .host) ?? "unknown"
			req.logger.info("Install server: \(req.method) \(req.url.string) host=\(host) from \(req.remoteAddress?.description ?? "unknown")")
			switch req.url.path {
			case plistEndpoint.path:
				self.trace.recordManifest(req.url.path)
				self._updateStatus(.sendingManifest)
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "text/xml",
				], body: .init(data: installManifestData))
			case displayImageSmallEndpoint.path:
				self.trace.recordImage(req.url.path)
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "image/png",
				], body: .init(data: displayImageSmallData))
			case displayImageLargeEndpoint.path:
				self.trace.recordImage(req.url.path)
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "image/png",
				], body: .init(data: displayImageLargeData))
			case payloadEndpoint.path:
				guard let packageUrl = packageUrl else {
					return Response(status: .notFound)
				}

				self.trace.recordPayload(req.url.path)
				self._updateStatus(.sendingPayload)
				
				return req.fileio.streamFile(
					at: packageUrl.path
				) { result in
					switch result {
					case .success:
						req.logger.info("Install server: payload stream finished for \(packageUrl.lastPathComponent)")
						self._updateStatus(.installing)
					case .failure(let error):
						req.logger.error("Install server: payload stream failed for \(packageUrl.lastPathComponent): \(String(describing: error))")
						self._updateStatus(.broken(error))
					}

				}
			case "/install":
				var headers = HTTPHeaders()
				headers.add(name: .contentType, value: "text/html")
				return Response(status: .ok, headers: headers, body: .init(string: self.html))
			default:
				return Response(status: .notFound)
			}
		}
	}
	
	private func _shutdownServer() {
		guard _needsShutdown else { return }
		
		_needsShutdown = false
		_server?.server.shutdown()
		_server?.shutdown()
	}
	
	private func _updateStatus(_ newStatus: InstallerStatusViewModel.InstallerStatus) {
		DispatchQueue.main.async {
			self.viewModel.status = newStatus
		}
	}
		
	func getServerMethod() -> Int {
		UserDefaults.standard.integer(forKey: "Feather.serverMethod")
	}
	
	func getIPFix() -> Bool {
		UserDefaults.standard.bool(forKey: "Feather.ipFix")
	}

	/// Confirms the local listener answers over the same URL SpringBoard will
	/// use a few seconds after the install prompt is accepted — HTTPS loopback
	/// when TLS material is installed, plain HTTP loopback otherwise. Returns
	/// `nil` on success, or a user-facing failure reason so a dead server
	/// surfaces in-app instead of as the system's opaque “cannot connect to
	/// 127.0.0.1”.
	func selfTest() async -> String? {
		guard let url = URL(string: pageEndpoint.absoluteString) else {
			return "The install server couldn't build its loopback URL."
		}
		var request = URLRequest(url: url)
		request.timeoutInterval = 5
		do {
			let (_, response) = try await URLSession.shared.data(for: request)
			if (response as? HTTPURLResponse)?.statusCode == 200 {
				return nil
			}
			return "The install server answered with an unexpected status."
		} catch {
			return "\(error.localizedDescription) (listener on 127.0.0.1:\(port))"
		}
	}

	/// Raw-loopback reachability probe (BSD sockets, independent of URLSession):
	/// does the listener answer IPv4 127.0.0.1 and/or IPv6 ::1? installd fetches
	/// the IPv4 literal 127.0.0.1, so an IPv6-only listener would produce the
	/// system's “cannot connect to 127.0.0.1” alert. Each connect is non-blocking
	/// with a 2-second timeout.
	func loopbackProbe() -> (ipv4: Bool, ipv6: Bool) {
		func canConnect(host: String, port: Int, family: Int32) -> Bool {
			var hint = addrinfo()
			hint.ai_family = family
			hint.ai_socktype = SOCK_STREAM
			var result: UnsafeMutablePointer<addrinfo>?
			guard getaddrinfo(host, String(port), &hint, &result) == 0, let addr = result else {
				return false
			}
			defer { freeaddrinfo(addr) }

			let fd = socket(addr.pointee.ai_family, addr.pointee.ai_socktype, addr.pointee.ai_protocol)
			guard fd >= 0 else { return false }
			defer { close(fd) }

			var flags = fcntl(fd, F_GETFL, 0)
			_ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

			let rc = connect(fd, addr.pointee.ai_addr, addr.pointee.ai_addrlen)
			if rc == 0 { return true }
			guard errno == EINPROGRESS else { return false }

			var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
			let ready = poll(&pfd, 1, 2000)
			guard ready > 0 else { return false }

			var soError: Int32 = 0
			var len = socklen_t(MemoryLayout<Int32>.size)
			guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len) == 0 else { return false }
			return soError == 0
		}

		return (
			canConnect(host: "127.0.0.1", port: port, family: AF_INET),
			canConnect(host: "::1", port: port, family: AF_INET6)
		)
	}
}
