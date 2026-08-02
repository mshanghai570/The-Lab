//
//	LabSectionHeader.swift
//	The Lab
//
//	Created by Michael Shingara on 8/2/26.
//

import SwiftUI

/// A large Playfair section header with a small neon tick and an optional
/// count pill. Replaces the system's plain section titles.
struct LabSectionHeader: View {
	let title: String
	var count: Int? = nil
	var accent: Color = LabTheme.neon

	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: 10) {
			Capsule()
				.fill(accent)
				.frame(width: 4, height: 20)
				.labGlow(accent, radius: 8, opacity: 0.45)

			Text(title)
				.font(.playfair(26, weight: .semiBold))
				.foregroundStyle(LabTheme.textPrimary)
				.kerning(0.3)

			Spacer()

			if let count {
				Text("\(count)")
					.font(.system(size: 13, weight: .semibold))
					.foregroundStyle(LabTheme.textSecondary)
					.padding(.horizontal, 10)
					.padding(.vertical, 4)
					.background(Capsule().fill(LabTheme.surfaceElevated))
					.overlay(Capsule().stroke(LabTheme.hairline, lineWidth: 1))
			}
		}
	}
}
