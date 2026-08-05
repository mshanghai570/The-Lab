//
//  InstallPreview.swift
//  Feather
//
//  Created by samara on 22.04.2025.
//

import SwiftUI
import NimbleViews
import IDeviceSwift
import OSLog

// MARK: - View
struct InstallPreviewView: View {
	@Environment(\.dismiss) var dismiss
	@Environment(\.scenePhase) private var scenePhase

	@AppStorage("Feather.useShareSheetForArchiving") private var _useShareSheet: Bool = false
	@AppStorage("Feather.installationMethod") private var _installationMethod: Int = 0
	@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 0
	@State private var _isWebviewPresenting = false
	@State private var progressTask: Task<Void, Never>?
	@State private var _backgroundTask: UIBackgroundTaskIdentifier = .invalid
	/// Set once the failed-install diagnosis has been shown for this attempt.
	@State private var _didDiagnose = false
	
	var app: AppInfoPresentable
	@StateObject var viewModel: InstallerStatusViewModel
	@StateObject var installer: ServerInstaller
	
	@State var isSharing: Bool
	
	init(app: AppInfoPresentable, isSharing: Bool = false) {
		self.app = app
		self.isSharing = isSharing
		let viewModel = InstallerStatusViewModel(isIdevice: UserDefaults.standard.integer(forKey: "Feather.installationMethod") == 1)
		self._viewModel = StateObject(wrappedValue: viewModel)
		self._installer = StateObject(wrappedValue: try! ServerInstaller(app: app, viewModel: viewModel))
	}
	
	// MARK: Body
	var body: some View {
		let cornerRadius = {
			if #available(iOS 26.0, *) {
				28.0
			} else {
				10.5
			}
		}()
		
		ZStack {
			InstallProgressView(app: app, viewModel: viewModel)
			_status()
			_button()
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
		.background(Color(UIColor.secondarySystemBackground))
		.cornerRadius(cornerRadius)
		.padding()
		.sheet(isPresented: $_isWebviewPresenting) {
			SafariRepresentableView(url: installer.pageEndpoint).ignoresSafeArea()
		}
		.onReceive(viewModel.$status) { newStatus in
			if _installationMethod == 0 {
				if case .ready = newStatus {
					if _serverMethod == 0 {
						// Fully Local — hand the itms-services URL straight to
						// SpringBoard instead of bouncing through the in-app
						// /install page. The manifest is palera.in's HTTPS copy
						// (iOS 18 installd rejects a plain-HTTP manifest URL), while
						// the payload still streams from the local loopback listener.
						// Opening the URL directly is what avoids Safari's
						// “Open in iTunes?” interstitial, matching upstream Feather's
						// Fully Local behavior.
						Task {
							// Verify the loopback listener answers first, so a dead
							// server is reported in-app instead of as the system's
							// opaque “cannot connect to 127.0.0.1”.
							let failure = await installer.selfTest()
							guard failure == nil else {
								Logger.misc.error("Install server self-test failed: \(failure ?? "unknown")")
								await MainActor.run {
									let message = "The local install server didn't answer. \(failure ?? "Try again.") Dismiss and try again, or switch to Semi Local in Settings → Installation → Server & SSL."
									viewModel.status = .broken(InstallServerError(message: message))
									UIAlertController.showAlertWithOk(
										title: "Install",
										message: message
									)
								}
								return
							}
							Logger.misc.info("Install server self-test passed; opening \(installer.iTunesLinkExternal)")
							await MainActor.run {
								guard let url = URL(string: installer.iTunesLinkExternal) else {
									viewModel.status = .broken(InstallServerError(message: "The install link couldn't be built. Try again."))
									UIAlertController.showAlertWithOk(
										title: "Install",
										message: "The install link couldn't be built. Try again."
									)
									return
								}
								UIApplication.shared.open(url) { opened in
									if !opened {
										Logger.misc.error("Failed to open install URL — no handler for itms-services?")
									}
								}
							}
						}
					} else {
						// Semi Local (1) and External (2) — present the in-app
						// /install page, which redirects to the itms-services URL.
						Logger.misc.info("Install URL about to open: \(installer.html)")
						_isWebviewPresenting = true
					}
				}
				
				if case .sendingPayload = newStatus, _serverMethod == 0 || _serverMethod == 1 {
					_isWebviewPresenting = false
				}
				
				if case .installing = newStatus {
					if progressTask == nil {
						progressTask = startInstallProgressPolling(
							bundleID: app.identifier!,
							viewModel: viewModel
						)
					}
				}
				
				switch newStatus {
				case .completed, .broken(_):
					progressTask?.cancel()
					progressTask = nil
					_endBackgroundKeepAlive()
					#if !targetEnvironment(macCatalyst)
					BackgroundAudioManager.shared.stop()
					#endif
				default:
					break
				}
			}
		}
		.onAppear(perform: _install)
		
		#if !targetEnvironment(macCatalyst)
		.onAppear {
			BackgroundAudioManager.shared.start()
		}
		#endif
		
		.onDisappear {
			progressTask?.cancel()
			progressTask = nil
			_endBackgroundKeepAlive()
				
			#if !targetEnvironment(macCatalyst)
			BackgroundAudioManager.shared.stop()
			#endif
		}
		// When the user returns to the app after the system's install prompt
		// (or its “cannot connect to 127.0.0.1” alert), categorise what the
		// listener actually saw so the failure stage is visible in-app instead
		// of only in Console.app.
		.onChange(of: scenePhase) { _, phase in
			if phase == .active, _installationMethod == 0 {
				_diagnoseInstallIfStalled()
			}
		}
	}
	
	@ViewBuilder
	private func _status() -> some View {
		Label(viewModel.statusLabel, systemImage: viewModel.statusImage)
			.padding()
			.labelStyle(.titleAndIcon)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
			.animation(.smooth, value: viewModel.statusImage)
	}
	
	@ViewBuilder
	private func _button() -> some View {
		ZStack {
			if viewModel.isCompleted {
				Button {
					UIApplication.openApp(with: app.identifier ?? "")
				} label: {
					NBButton("Open", systemImage: "", style: .text)
				}
				.padding()
				.compatTransition()
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
		.animation(.easeInOut(duration: 0.3), value: viewModel.isCompleted)
	}
	
	private func _install() {
		_beginBackgroundKeepAlive()
		
		guard isSharing || app.identifier != Bundle.main.bundleIdentifier! || _installationMethod == 1 else {
			UIAlertController.showAlertWithOk(
				title: .localized("Install"),
				message: .localized("You cannot update ‘%@‘ with itself, please use an alternative tool to update it.", arguments: Bundle.main.name)
			)
			return
		}
				
		Task.detached {
			do {
				let handler = await ArchiveHandler(app: app, viewModel: viewModel)
				try await handler.move()
				
				let packageUrl = try await handler.archive()
				
				if await !isSharing {
					if await _installationMethod == 0 {
						await MainActor.run {
							installer.packageUrl = packageUrl
							viewModel.status = .ready
						}
						
						if case .installing = await viewModel.status {
							let task = await startInstallProgressPolling(
								bundleID: app.identifier!,
								viewModel: viewModel
							)

							await MainActor.run {
								progressTask = task
							}
						}
					} else if await _installationMethod == 1 {
						let handler = await InstallationProxy(viewModel: viewModel)
						try await handler.install(at: packageUrl, suspend: app.identifier == Bundle.main.bundleIdentifier!)
					}
				} else {
					let package = try await handler.moveToArchive(packageUrl, shouldOpen: !_useShareSheet)
					
					if await !_useShareSheet {
						await MainActor.run {
							dismiss()
						}
					} else {
						if let package {
							await MainActor.run {
								dismiss()
								UIActivityViewController.show(activityItems: [package])
							}
						}
					}
				}
			} catch {
				await progressTask?.cancel()
				
				await MainActor.run {
					UIAlertController.showAlertWithOk(
						title: .localized("Install"),
						message: String(describing: error),
						action: {
							HeartbeatManager.shared.start(true)
							dismiss()
						}
					)
				}
			}
		}
	}
	
	/// Requests extra background execution time for the manifest + payload
	/// transfer window. This is a fallback alongside the silent-audio keep
	/// alive: if the audio engine fails to start, the app would otherwise
	/// suspend the moment the itms-services prompt backgrounds it and the
	/// install would die with “cannot connect to 127.0.0.1”.
	private func _beginBackgroundKeepAlive() {
		#if !targetEnvironment(macCatalyst)
		guard _backgroundTask == .invalid else { return }
		_backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "TheLab.installServer") { [self] in
			let task = _backgroundTask
			_backgroundTask = .invalid
			if task != .invalid {
				UIApplication.shared.endBackgroundTask(task)
			}
		}
		#endif
	}

	private func _endBackgroundKeepAlive() {
		#if !targetEnvironment(macCatalyst)
		guard _backgroundTask != .invalid else { return }
		let task = _backgroundTask
		_backgroundTask = .invalid
		UIApplication.shared.endBackgroundTask(task)
		#endif
	}

	/// Categorises a stalled install: did SpringBoard's fetch ever reach the
	/// listener, and does the listener answer a raw IPv4/IPv6 loopback probe?
	/// Shown once per attempt, only when the install never kicked off — if the
	/// payload request has already reached the listener the pipeline is live,
	/// and returning to the app mid-stream is normal for direct-open installs.
	private func _diagnoseInstallIfStalled() {
		guard !_didDiagnose else { return }

		// Only diagnose a genuinely stalled install (still waiting for
		// SpringBoard's first fetch after the itms-services handoff). The
		// manifest is generated by palera.in over HTTPS and never touches the
		// local listener, so the first thing that reaches the server is the
		// payload request — once it has arrived, the install is in progress
		// and no alert should be shown.
		guard case .ready = viewModel.status else { return }

		_didDiagnose = true
		Task {
			let trace = installer.trace.snapshot
			let serverAlive = (await installer.selfTest()) == nil
			let audioActive = BackgroundAudioManager.shared.isPlaying()
			let probe = installer.loopbackProbe()
			let buildTag = Bundle.main.infoDictionary?["AppBuildTag"] as? String ?? "unknown build"

			let category: String
			if !serverAlive {
				category = "Server startup failure — the listener is not answering from inside the app. Check the Install server log in Console.app."
			} else if !audioActive {
				category = "Client connection failure — SpringBoard never reached the listener; the background keep-alive is not running, so the app likely suspended before the fetch. Check Console.app for \"Install server\" log lines."
			} else {
				category = "Client connection failure — SpringBoard never reached the listener even though the server and keep-alive were up. The itms-services handoff may have been dropped; try again."
			}

			let detail = "Build: \(buildTag)" +
				"\nStatus on return: \(viewModel.statusLabel)" +
				"\nInstall link: \(installer.iTunesLinkExternal)" +
				"\nPayload URL: \(installer.payloadEndpoint.absoluteString)" +
				"\nServer bound to: \(installer.boundAddress)" +
				"\nIPv4 loopback probe: \(probe.ipv4 ? "reachable" : "FAILED")" +
				"\nIPv6 loopback probe: \(probe.ipv6 ? "reachable" : "FAILED")" +
				"\nPayload fetch reached server: \(trace.payload ? "yes" : "no")" +
				"\nServer answering now: \(serverAlive ? "yes" : "no")" +
				"\nBackground keep-alive: \(audioActive ? "running" : "not running")"

			await MainActor.run {
				Logger.misc.error("Install diagnosis: \(category) \(detail)")
				UIAlertController.showAlertWithOk(
					title: "Install failed",
					message: "\(category)\n\n\(detail)"
				)
			}
		}
	}

	private func startInstallProgressPolling(
		bundleID: String,
		viewModel: InstallerStatusViewModel
	) -> Task<Void, Never> {

		Task.detached(priority: .background) {
			var hasStarted = false

			while !Task.isCancelled {
				let rawProgress = await UIApplication.installProgress(for: bundleID) ?? 0.0

				if rawProgress > 0 {
					hasStarted = true
				}

				let progress = await hasStarted
					? _normalizeInstallProgress(rawProgress)
					: 0.0

				Logger.misc.info("Install progress for \(bundleID): \(progress)")

				await MainActor.run {
					viewModel.installProgress = progress
				}

				if hasStarted && rawProgress == 0 {
					await MainActor.run {
						viewModel.installProgress = 1.0
						viewModel.status = .completed(.success(()))
					}
					break
				}

				try? await Task.sleep(nanoseconds: 1_000_000) // 1 ms
			}
		}
	}

	private func _normalizeInstallProgress(_ rawProgress: Double) -> Double {
		min(1.0, max(0.0, (rawProgress - 0.6) / 0.3))
	}
}
