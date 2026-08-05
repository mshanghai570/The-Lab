//
//  BackgroundAudioManager.swift
//  Feather
//
//  Created by Nagata Asami on 12/10/25.
//

#if !targetEnvironment(macCatalyst)

import AVFoundation

/// Keeps the app alive in the background while the in-process install server
/// streams the manifest and payload to SpringBoard.
///
/// iOS only grants background execution to apps with an active audio session.
/// The most battle-tested way to hold one open (used by Esign and friends) is
/// looping an actual silent audio file; a purely programmatic
/// `AVAudioSourceNode` can be optimized away or classified as inactive on some
/// iOS versions. We therefore play a generated silent WAV on an endless loop
/// and fall back to the source-node engine if the player can't start.
class BackgroundAudioManager {
	static let shared = BackgroundAudioManager()

	private var _player: AVAudioPlayer?
	private let _engine = AVAudioEngine()
	private var _silenceNode: AVAudioSourceNode?
	private var _isObserving = false

	private init() {}

	/// Starts the silent-audio keep-alive. If this fails the app suspends the
	/// moment it backgrounds mid-install and SpringBoard reports “cannot
	/// connect to 127.0.0.1” when it fetches the manifest.
	func start() {
		_observeInterruptions()

		if _player?.isPlaying == true || _engine.isRunning { return }

		let session = AVAudioSession.sharedInstance()

		// Activation can transiently fail (e.g. while another audio session
		// is mid-interruption); retry briefly before giving up.
		var sessionReady = false
		for attempt in 0..<3 {
			do {
				try session.setCategory(.playback, options: [.mixWithOthers])
				try session.setActive(true)
				sessionReady = true
				break
			} catch {
				print("BackgroundAudioManager: session activation failed (attempt \(attempt + 1)): \(error)")
				if attempt < 2 {
					Thread.sleep(forTimeInterval: 0.35)
				}
			}
		}

		guard sessionReady else {
			print("BackgroundAudioManager: giving up — install server may not survive backgrounding")
			return
		}

		// Primary: loop a real silent WAV. `prepareToPlay` + `play` on the main
		// thread keeps the session attributed to the app.
		if _player == nil {
			_player = try? AVAudioPlayer(contentsOf: Self._silentWAVURL())
			_player?.volume = 0
			_player?.numberOfLoops = -1
		}

		if let player = _player {
			player.prepareToPlay()
			if player.play() {
				print("BackgroundAudioManager: silent WAV keep-alive playing")
				return
			}
			print("BackgroundAudioManager: AVAudioPlayer failed to start, falling back to engine")
		}

		// Fallback: an AVAudioSourceNode rendering digital silence.
		if _silenceNode == nil {
			let silence = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
				let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
				for buffer in ablPointer {
					memset(buffer.mData, 0, Int(buffer.mDataByteSize))
				}
				return noErr
			}

			_silenceNode = silence
			_engine.attach(silence)
			_engine.connect(silence, to: _engine.mainMixerNode, format: nil)
		}

		do {
			try _engine.start()
			print("BackgroundAudioManager: engine keep-alive running")
		} catch {
			print("BackgroundAudioManager: engine failed to start: \(error)")
		}
	}

	func stop() {
		_player?.stop()
		_engine.stop()
		if let node = _silenceNode {
			_engine.detach(node)
			_silenceNode = nil
		}
		try? AVAudioSession.sharedInstance().setActive(false)
	}

	/// Whether the keep-alive is currently holding an active audio session —
	/// used by the install failure diagnosis to distinguish a suspended app
	/// (keep-alive died) from a reachable-but-refused fetch.
	func isPlaying() -> Bool {
		_player?.isPlaying == true || _engine.isRunning
	}

	// MARK: Interruptions

	/// If the audio session is interrupted (Siri, phone call, another app
	/// grabbing the session), the keep-alive dies and — unless we restart it —
	/// the app suspends mid-install. Restart when the interruption ends.
	private func _observeInterruptions() {
		guard !_isObserving else { return }
		_isObserving = true

		NotificationCenter.default.addObserver(
			forName: AVAudioSession.interruptionNotification,
			object: AVAudioSession.sharedInstance(),
			queue: .main
		) { [weak self] notification in
			guard
				let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
				let type = AVAudioSession.InterruptionType(rawValue: rawType)
			else { return }

			if type == .ended {
				print("BackgroundAudioManager: interruption ended, restarting keep-alive")
				self?.start()
			}
		}
	}

	// MARK: Silent WAV

	/// A 3-second silent 16-bit mono 44.1 kHz WAV, generated on demand so we
	/// don't have to ship an audio asset. Written to Caches so it survives for
	/// the lifetime of the app install.
	private static func _silentWAVURL() -> URL {
		let fileURL = FileManager.default.temporaryDirectory
			.appendingPathComponent("TheLab_silence.wav")

		if !FileManager.default.fileExists(atPath: fileURL.path) {
			let seconds = 3
			let sampleRate: UInt32 = 44_100
			let bitsPerSample: UInt16 = 16
			let channels: UInt16 = 1
			let dataSize = UInt32(seconds) * sampleRate * 2

			var data = Data()
			// RIFF header
			data.append(contentsOf: Array("RIFF".utf8))
			data.append(contentsOf: littleEndianBytes(UInt32(36 + dataSize)))
			data.append(contentsOf: Array("WAVE".utf8))
			// fmt chunk
			data.append(contentsOf: Array("fmt ".utf8))
			data.append(contentsOf: littleEndianBytes(UInt32(16)))
			data.append(contentsOf: littleEndianBytes(UInt16(1)))			// PCM
			data.append(contentsOf: littleEndianBytes(channels))
			data.append(contentsOf: littleEndianBytes(sampleRate))
			data.append(contentsOf: littleEndianBytes(sampleRate * 2))		// byte rate
			data.append(contentsOf: littleEndianBytes(UInt16(2)))			// block align
			data.append(contentsOf: littleEndianBytes(bitsPerSample))
			// data chunk (silence)
			data.append(contentsOf: Array("data".utf8))
			data.append(contentsOf: littleEndianBytes(dataSize))
			data.append(Data(count: Int(dataSize)))

			try? data.write(to: fileURL, options: .atomic)
		}

		return fileURL
	}

	private static func littleEndianBytes<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
		var v = value.littleEndian
		return withUnsafeBytes(of: &v) { Array($0) }
	}
}

#endif
