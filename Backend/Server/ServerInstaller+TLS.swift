//
//  Server+TLS.swift
//  feather
//
//  Created by samara on 22.08.2024.
//  Copyright © 2024 Lakr Aream. All Rights Reserved.
//  ORIGINALLY LICENSED UNDER GPL-3.0, MODIFIED FOR USE FOR FEATHER
//

import Foundation
import NIOSSL
import NIOTLS
import Vapor
import SystemConfiguration.CaptiveNetwork

// MARK: - Class extension: TLS/Setup
extension ServerInstaller {
	// MARK: Setup
	static let env: Environment = {
		var env = try! Environment.detect()
		try! LoggingSystem.bootstrap(from: &env)
		return env
	}()
	
	func setupApp(port: Int) throws -> Application {
		let app = Application(Self.env)
		// The installer streams a multi-megabyte payload to SpringBoard while
		// also serving the manifest and icon requests; a single thread can make
		// that transfer stall. A small pool keeps it snappy without hogging CPU.
		app.threadPool = .init(numberOfThreads: 4)
		
		// Only External (2) serves TLS (the backloop cert). Fully Local (0) and
		// Semi Local (1) always serve plain HTTP: their manifests are fetched
		// from palera.in over HTTPS, so the listener itself never needs TLS.
		// Keeping the listener in sync with `usesTLS` is what makes the
		// manifest scheme and the socket speak the same protocol.
		if getServerMethod() == 2, let tls = try tls() {
			app.http.server.configuration.tlsConfiguration = tls
		}
		
		app.http.server.configuration.hostname = sni()
		app.http.server.configuration.tcpNoDelay = true

		// The listener binds every interface (0.0.0.0) for every server type.
		// The URLs the manifest advertises are loopback-only (127.0.0.1), so
		// only on-device connections should arrive — but binding 0.0.0.0 is
		// required for installd to reach the listener on iOS: the
		// proven-working Semi Local + “Only use localhost address” path binds
		// 0.0.0.0, while binding exactly 127.0.0.1 produced the system's
		// “cannot connect to 127.0.0.1” alert.
		app.http.server.configuration.address = .hostname("0.0.0.0", port: port)
		app.http.server.configuration.port = port
		app.routes.defaultMaxBodySize = "128mb"
		app.routes.caseInsensitive = false
		
		return app
	}
	
	// MARK: Files/IP
	func sni() -> String {
		let localhost = "127.0.0.1"

		switch getServerMethod() {
		case 0:
			// Fully Local serves the manifest and payload over loopback only.
			// The listener is always plain HTTP on 127.0.0.1 and the /install
			// page hands SpringBoard the palera.in HTTPS manifest (the payload
			// still streams from this loopback listener) — the same flow as
			// Semi Local with “Only use localhost address”, which installs
			// cleanly on iOS 18.
			return localhost
		case 1:
			return !self.getIPFix()
				? (Self.getLocalAddress() ?? localhost)
				: localhost
		default:
			return readConcreteCommonName() ?? localhost
		}
	}
	
	/// The stored common name is a wildcard (`*.backloop.dev`), which cannot
	/// be used as a URL host. Rewrite it to a concrete subdomain that resolves
	/// to loopback so the same wildcard certificate validates the connection.
	func readConcreteCommonName() -> String? {
		guard let name = readCommonName(), !name.isEmpty else { return nil }
		if name.hasPrefix("*.") {
			return "test." + name.dropFirst(2)
		}
		return name
	}
	
	func tls() throws -> TLSConfiguration? {
		guard
			let crt = Self.getUrl("server", ext: "crt"),
			let pem = Self.getUrl("server", ext: "pem")
		else {
			return nil
		}
		
		return try TLSConfiguration.makeServerConfiguration(
			certificateChain: NIOSSLCertificate.fromPEMFile(crt.path).map {
				NIOSSLCertificateSource.certificate($0)
			},
			privateKey: .privateKey(
				try NIOSSLPrivateKey(file: pem.path, format: .pem)
			)
		)
	}
	
	func readCommonName() -> String? {
		guard let url = Self.getUrl("commonName", ext: "txt") else {
			return nil
		}
		
		return try? String(contentsOf: url, encoding: .utf8)
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

extension ServerInstaller {
	static func getUrl(_ name: String, ext: String) -> URL? {
		let fileManager = FileManager.default
		
		let documentsURL = URL.documentsDirectory.appendingPathComponent("\(name).\(ext)")
		let bundlesURL = Bundle.main.url(forResource: name, withExtension: ext)
		
		if fileManager.fileExists(atPath: documentsURL.path) {
			return documentsURL
		}
		
		if let bundlesURL, fileManager.fileExists(atPath: bundlesURL.path) {
			return bundlesURL
		}
		
		return nil
	}
	
	static func getLocalAddress() -> String? {
		var address: String?
		var ifaddr: UnsafeMutablePointer<ifaddrs>?
		
		if getifaddrs(&ifaddr) == 0 {
			var ptr = ifaddr
			while ptr != nil {
				let interface = ptr!.pointee
				let addrFamily = interface.ifa_addr.pointee.sa_family
				
				if addrFamily == UInt8(AF_INET) {
					
					let name = String(cString: interface.ifa_name)
					if name == "en0" || name == "pdp_ip0" {
						
						var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
						if getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
						               &hostname, socklen_t(hostname.count),
						               nil, socklen_t(0), NI_NUMERICHOST) == 0 {
							address = String(cString: hostname)
						}
						
					}
				}
				ptr = ptr!.pointee.ifa_next
			}
			freeifaddrs(ifaddr)
		}
		
		return address
	}
}
