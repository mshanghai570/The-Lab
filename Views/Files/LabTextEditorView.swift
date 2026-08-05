//
//  LabTextEditorView.swift
//  The Lab
//
//  Created by Michael Shingara on 8/4/26.
//

import SwiftUI

/// In-place text editor for workspace files.
///
/// Loads a file as UTF-8 text, lets you edit it in a monospaced editor, and
/// writes the result back to the same URL — so edits to a file inside an
/// unpacked IPA workspace survive repackaging. Non-destructive: nothing is
/// written until Save is tapped.
///
/// Binary content (binary plists, Mach-O slices, compressed data…) can't be
/// decoded as UTF-8; instead of dead-ending, the editor explains what the
/// file actually is and offers to hand off to the Plist or Hex editor via
/// `onSwitchEditor`.
struct LabTextEditorView: View {
	let url: URL
	var preloadedData: Data? = nil
	var onSwitchEditor: ((LabEditorKind) -> Void)? = nil
	@Environment(\.dismiss) private var dismiss

	@State private var text = ""
	@State private var hasChanges = false
	@State private var loadFailure: LoadFailure?
	@State private var errorMessage: String?

	private enum LoadFailure {
		case binaryPlist
		case binary
		case unreadable(LabFileLoader.Outcome)
	}

	var body: some View {
		NavigationStack {
			ZStack {
				LabTheme.oledBlack.ignoresSafeArea()

				if let loadFailure {
					_loadFailedView(loadFailure)
				} else {
					TextEditor(text: $text)
						.font(.system(size: 12, design: .monospaced))
						.foregroundStyle(LabTheme.textSecondary)
						.scrollContentBackground(.hidden)
						.autocorrectionDisabled()
						.textInputAutocapitalization(.never)
						.padding(12)
						.onChange(of: text) {
							hasChanges = true
						}
				}
			}
			.navigationTitle(url.lastPathComponent)
			.navigationBarTitleDisplayMode(.inline)
			.toolbarBackground(LabTheme.surfacePrimary, for: .navigationBar)
			.toolbarBackground(.visible, for: .navigationBar)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Save") { _save() }
						.disabled(!hasChanges)
				}
			}
			.alert("Couldn't Save", isPresented: Binding(
				get: { errorMessage != nil },
				set: { if !$0 { errorMessage = nil } }
			)) {
				Button("OK", role: .cancel) { errorMessage = nil }
			} message: {
				Text(errorMessage ?? "")
			}
			.onAppear(perform: _load)
		}
	}

	private func _loadFailedView(_ failure: LoadFailure) -> some View {
		VStack(spacing: 14) {
			Image(systemName: "doc.badge.exclamationmark")
				.font(.system(size: 30))
				.foregroundStyle(LabTheme.accent)

			switch failure {
			case .binaryPlist:
				Text("This is a binary plist, not UTF-8 text.")
					.font(.playfair(18, weight: .semiBold))
					.foregroundStyle(LabTheme.textPrimary)
				Text("Use the Plist Editor to view and edit its contents.")
					.font(.system(size: 13))
					.foregroundStyle(LabTheme.textTertiary)
				Button {
					onSwitchEditor?(.plist)
				} label: {
					Label("Open in Plist Editor", systemImage: "list.bullet.rectangle.portrait")
				}
				.buttonStyle(LabPrimaryButtonStyle())
			case .binary:
				Text("This file isn't UTF-8 text.")
					.font(.playfair(18, weight: .semiBold))
					.foregroundStyle(LabTheme.textPrimary)
				Text("It looks like binary data. Use the Hex Editor to inspect it.")
					.font(.system(size: 13))
					.foregroundStyle(LabTheme.textTertiary)
				Button {
					onSwitchEditor?(.hex)
				} label: {
					Label("Open in Hex Editor", systemImage: "number")
				}
				.buttonStyle(LabPrimaryButtonStyle())
			case .unreadable(let outcome):
				Text("This file can't be read.")
					.font(.playfair(18, weight: .semiBold))
					.foregroundStyle(LabTheme.textPrimary)
				Text(outcome.errorSummary ?? "Unknown read error.")
					.font(.system(size: 13))
					.foregroundStyle(LabTheme.textTertiary)
					.multilineTextAlignment(.center)
				Text(LabFileLoader.summary(outcome))
					.font(.system(size: 11, design: .monospaced))
					.foregroundStyle(LabTheme.textTertiary)
					.multilineTextAlignment(.leading)
					.textSelection(.enabled)
			}

			Text(url.lastPathComponent)
				.font(.system(size: 12, design: .monospaced))
				.foregroundStyle(LabTheme.textTertiary)
		}
		.padding(24)
		.multilineTextAlignment(.center)
	}

	private func _load() {
		// Prefer the bytes captured at selection time — the editor provably
		// opens what the user picked instead of re-reading a URL that may have
		// changed or gone stale since the tap.
		if let preloadedData {
			print("[LabFileLoader] text editor using preloaded data (\(preloadedData.count) bytes) — \(url.path)")
			_consume(preloadedData)
			return
		}
		let outcome = LabFileLoader.read(url)
		guard let data = outcome.data else {
			loadFailure = .unreadable(outcome)
			return
		}
		_consume(data)
	}

	private func _consume(_ data: Data) {
		if let string = String(data: data, encoding: .utf8) {
			text = string
			hasChanges = false
			return
		}
		loadFailure = data.starts(with: LabFileFormat.bplistHeader) ? .binaryPlist : .binary
	}

	private func _save() {
		do {
			try text.write(to: url, atomically: true, encoding: .utf8)
			dismiss()
		} catch {
			errorMessage = error.localizedDescription
		}
	}
}
