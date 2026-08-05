//
//  LabPlistEditorView.swift
//  The Lab
//
//  Created by Michael Shingara on 8/4/26.
//

import SwiftUI

/// In-place property list editor for workspace files.
///
/// Loads a plist (XML or binary), presents it as editable XML text, validates
/// the edited document with `PropertyListSerialization` before writing, and
/// saves back to the same URL — so edits to an Info.plist inside an unpacked
/// IPA workspace survive repackaging. Binary plists are normalized to XML on
/// load, which is the format iOS tooling expects from edited packages anyway.
struct LabPlistEditorView: View {
	let url: URL
	var preloadedData: Data? = nil
	var onSwitchEditor: ((LabEditorKind) -> Void)? = nil
	@Environment(\.dismiss) private var dismiss

	@State private var text = ""
	@State private var hasChanges = false
	@State private var loadFailed = false
	@State private var loadOutcome: LabFileLoader.Outcome?
	@State private var errorMessage: String?
	@State private var validationMessage: String?

	var body: some View {
		NavigationStack {
			ZStack {
				LabTheme.oledBlack.ignoresSafeArea()

				if loadFailed {
					_loadFailedView
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
			.alert("Invalid Plist", isPresented: Binding(
				get: { validationMessage != nil },
				set: { if !$0 { validationMessage = nil } }
			)) {
				Button("Keep Editing", role: .cancel) { validationMessage = nil }
			} message: {
				Text(validationMessage ?? "")
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

	private var _loadFailedView: some View {
		VStack(spacing: 14) {
			Image(systemName: "doc.badge.exclamationmark")
				.font(.system(size: 30))
				.foregroundStyle(LabTheme.accent)

			if loadOutcome?.errorDomain != nil {
				// The file couldn't be opened at all — a read failure, not a
				// format failure. Show the underlying error so it's diagnosable.
				Text("This file can't be read.")
					.font(.playfair(18, weight: .semiBold))
					.foregroundStyle(LabTheme.textPrimary)
				Text(loadOutcome?.errorSummary ?? "Unknown read error.")
					.font(.system(size: 13))
					.foregroundStyle(LabTheme.textTertiary)
					.multilineTextAlignment(.center)
			} else {
				Text("This file isn't a readable plist.")
					.font(.playfair(18, weight: .semiBold))
					.foregroundStyle(LabTheme.textPrimary)
				Text("It may be corrupted, or not a property list at all. Inspect the raw bytes with the Hex Editor.")
					.font(.system(size: 13))
					.foregroundStyle(LabTheme.textTertiary)
					.multilineTextAlignment(.center)
			}

			if let outcome = loadOutcome {
				Text(LabFileLoader.summary(outcome))
					.font(.system(size: 11, design: .monospaced))
					.foregroundStyle(LabTheme.textTertiary)
					.multilineTextAlignment(.leading)
					.textSelection(.enabled)
			}

			Button {
				onSwitchEditor?(.hex)
			} label: {
				Label("Open in Hex Editor", systemImage: "number")
			}
			.buttonStyle(LabPrimaryButtonStyle())
			Text(url.lastPathComponent)
				.font(.system(size: 12, design: .monospaced))
				.foregroundStyle(LabTheme.textTertiary)
		}
		.padding(24)
		.multilineTextAlignment(.center)
	}

	// MARK: - Helpers

	private func _load() {
		// Prefer the bytes captured at selection time — the editor provably
		// opens what the user picked instead of re-reading a URL that may have
		// changed or gone stale since the tap.
		let outcome: LabFileLoader.Outcome
		if let preloadedData {
			print("[LabFileLoader] plist editor using preloaded data (\(preloadedData.count) bytes) — \(url.path)")
			outcome = LabFileLoader.from(preloaded: preloadedData, url: url)
		} else {
			outcome = LabFileLoader.read(url)
		}
		loadOutcome = outcome
		guard let data = outcome.data else {
			loadFailed = true
			return
		}
		do {
			// PropertyListSerialization reads both XML and binary plists; the
			// round-trip through XML gives us an editable document either way.
			let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
			let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
			guard let string = String(data: xml, encoding: .utf8) else {
				loadFailed = true
				return
			}
			text = string
			hasChanges = false
		} catch {
			loadFailed = true
		}
	}

	private func _save() {
		let data = Data(text.utf8)
		do {
			// Throws if the edited text is not a well-formed property list.
			_ = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
			try data.write(to: url, options: .atomic)
			dismiss()
		} catch {
			let nsError = error as NSError
			if nsError.domain == NSCocoaErrorDomain {
				validationMessage = "The document isn't valid XML plist syntax:\n\(error.localizedDescription)"
			} else {
				errorMessage = error.localizedDescription
			}
		}
	}
}
