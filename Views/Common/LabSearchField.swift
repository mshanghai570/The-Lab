//
//	LabSearchField.swift
//	The Lab
//
//	Created by Michael Shingara on 8/2/26.
//

import SwiftUI

/// Custom search field — an elevated near-black panel with a pink focus
/// glow. Replaces the system `.searchable` bar so search lives inside the
/// page's visual rhythm instead of the navigation chrome.
struct LabSearchField: View {
	@Binding var text: String
	var placeholder: String = "Search"

	@FocusState private var isFocused: Bool

	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: "magnifyingglass")
				.font(.system(size: 15, weight: .medium))
				.foregroundStyle(isFocused ? LabTheme.accent : LabTheme.textTertiary)

			TextField(placeholder, text: $text)
				.focused($isFocused)
				.font(.system(size: 16))
				.foregroundStyle(LabTheme.textPrimary)
				.autocorrectionDisabled()
				.textInputAutocapitalization(.never)
				.submitLabel(.search)

			if !text.isEmpty {
				Button {
					text = ""
				} label: {
					Image(systemName: "xmark.circle.fill")
						.font(.system(size: 15))
						.foregroundStyle(LabTheme.textTertiary)
				}
				.buttonStyle(.plain)
			}
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 12)
		.background(
			RoundedRectangle(cornerRadius: 16, style: .continuous)
				.fill(LabTheme.surfaceSecondary)
		)
		.overlay(
			RoundedRectangle(cornerRadius: 16, style: .continuous)
				.stroke(
					isFocused ? LabTheme.accent.opacity(0.55) : LabTheme.hairline,
					lineWidth: 1
				)
		)
		.labGlow(active: isFocused, color: LabTheme.accent, radius: 12)
		.animation(.smooth(duration: 0.25), value: isFocused)
	}
}
