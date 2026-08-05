//
//  LabHexEditorView.swift
//  The Lab
//
//  Created by Michael Shingara on 8/4/26.
//

import SwiftUI

/// In-place hex editor for workspace files.
///
/// Shows offset / hex / ASCII rows. Tap any byte to change it — a small
/// prompt asks for the two-digit hexadecimal value. "Save" writes the whole
/// buffer back to the same URL, so edits to a file inside an unpacked IPA
/// workspace survive repackaging.
struct LabHexEditorView: View {
	let url: URL
	var preloadedData: Data? = nil
	@Environment(\.dismiss) private var dismiss

	@State private var bytes: [UInt8] = []
	@State private var loadFailed = false
	@State private var loadOutcome: LabFileLoader.Outcome?

	@State private var editingByteIndex: Int?
	@State private var editHex = ""
	@State private var errorMessage: String?

	private static let bytesPerRow = 16

	var body: some View {
		NavigationStack {
			ZStack {
				LabTheme.oledBlack.ignoresSafeArea()

				if loadFailed {
					_loadFailedView
				} else {
					_grid
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
				}
			}
			.alert("Edit Byte", isPresented: Binding(
				get: { editingByteIndex != nil },
				set: { if !$0 { editingByteIndex = nil } }
			)) {
				TextField("00–FF", text: $editHex)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
				Button("Cancel", role: .cancel) { editingByteIndex = nil }
				Button("OK") { _commitByteEdit() }
			} message: {
				Text("Offset 0x\(String(format: "%06X", editingByteIndex ?? 0)): enter the new byte in hexadecimal.")
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

	// MARK: - Grid

	private var _grid: some View {
		ScrollView([.vertical, .horizontal]) {
			LazyVStack(alignment: .leading, spacing: 0) {
				_headerRow

				ForEach(Array(stride(from: 0, to: bytes.count, by: Self.bytesPerRow)), id: \.self) { start in
					_row(start: start)
				}
			}
			.padding(10)
		}
	}

	private var _headerRow: some View {
		HStack(spacing: 0) {
			Text("OFFSET")
				.frame(width: 74, alignment: .leading)
			ForEach(0..<Self.bytesPerRow, id: \.self) { i in
				Text(String(format: "%02X", i))
					.frame(width: 28, alignment: .center)
			}
			Text("ASCII")
				.frame(width: 80, alignment: .leading)
				.padding(.leading, 8)
		}
		.font(.system(size: 10, weight: .bold, design: .monospaced))
		.foregroundStyle(LabTheme.textTertiary)
		.padding(.vertical, 6)
	}

	private func _row(start: Int) -> some View {
		HStack(spacing: 0) {
			Text(String(format: "%06X", start))
				.font(.system(size: 11, design: .monospaced))
				.foregroundStyle(LabTheme.textTertiary)
				.frame(width: 74, alignment: .leading)

			ForEach(0..<Self.bytesPerRow, id: \.self) { offset in
				let index = start + offset
				if index < bytes.count {
					Button {
						editingByteIndex = index
						editHex = String(format: "%02X", bytes[index])
					} label: {
						Text(String(format: "%02X", bytes[index]))
							.font(.system(size: 11, design: .monospaced))
							.foregroundStyle(editingByteIndex == index ? LabTheme.accent : LabTheme.textSecondary)
							.frame(width: 28, height: 22, alignment: .center)
							.background(editingByteIndex == index ? LabTheme.accent.opacity(0.15) : Color.clear)
							.clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
					}
					.buttonStyle(.plain)
				} else {
					Color.clear
						.frame(width: 28, height: 22)
				}
			}

			Text(_ascii(start: start))
				.font(.system(size: 11, design: .monospaced))
				.foregroundStyle(LabTheme.textSecondary)
				.frame(width: 80, alignment: .leading)
				.padding(.leading, 8)
		}
		.padding(.vertical, 1)
	}

	private var _loadFailedView: some View {
		VStack(spacing: 12) {
			Image(systemName: "doc.badge.exclamationmark")
				.font(.system(size: 30))
				.foregroundStyle(LabTheme.accent)
			Text("Couldn't read this file.")
				.font(.playfair(18, weight: .semiBold))
				.foregroundStyle(LabTheme.textPrimary)
			if let error = loadOutcome?.errorSummary {
				Text(error)
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
			Text(url.lastPathComponent)
				.font(.system(size: 12, design: .monospaced))
				.foregroundStyle(LabTheme.textTertiary)
		}
		.padding(24)
	}

	// MARK: - Helpers

	private func _ascii(start: Int) -> String {
		var result = ""
		for offset in 0..<Self.bytesPerRow {
			let index = start + offset
			guard index < bytes.count else { break }
			let byte = bytes[index]
			result.append((32...126).contains(byte) ? Character(UnicodeScalar(byte)) : "·")
		}
		return result
	}

	private func _load() {
		// Prefer the bytes captured at selection time — the editor provably
		// opens what the user picked instead of re-reading a URL that may have
		// changed or gone stale since the tap.
		if let preloadedData {
			print("[LabFileLoader] hex editor using preloaded data (\(preloadedData.count) bytes) — \(url.path)")
			bytes = [UInt8](preloadedData)
			return
		}
		let outcome = LabFileLoader.read(url)
		loadOutcome = outcome
		guard let data = outcome.data else {
			loadFailed = true
			return
		}
		bytes = [UInt8](data)
	}

	private func _commitByteEdit() {
		defer { editingByteIndex = nil }

		let cleaned = editHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
		guard cleaned.count == 2, let value = UInt8(cleaned, radix: 16) else {
			errorMessage = "Enter a two-digit hex value (00–FF)."
			return
		}
		guard let index = editingByteIndex, index < bytes.count else { return }
		bytes[index] = value
	}

	private func _save() {
		do {
			try Data(bytes).write(to: url)
			dismiss()
		} catch {
			errorMessage = error.localizedDescription
		}
	}
}
