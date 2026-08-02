//
//	LabCard.swift
//	The Lab
//
//	Created by Michael Shingara on 8/2/26.
//

import SwiftUI

/// Shared panel geometry for The Lab's floating cards.
enum LabCardStyle {
	static func background(cornerRadius: CGFloat = LabTheme.cardCornerRadius) -> some View {
		RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
			.fill(
				LinearGradient(
					colors: [LabTheme.surfaceElevated, LabTheme.surfaceSecondary],
					startPoint: .top,
					endPoint: .bottom
				)
			)
	}

	static func stroke(cornerRadius: CGFloat = LabTheme.cardCornerRadius, lineWidth: CGFloat = 1) -> some View {
		RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
			.stroke(LabTheme.hairline, lineWidth: lineWidth)
	}
}

/// A floating panel — near-black fill, hairline border, and a soft drop
/// shadow so it hovers above the OLED canvas.
struct LabCard<Content: View>: View {
	private let content: Content

	init(@ViewBuilder content: () -> Content) {
		self.content = content()
	}

	var body: some View {
		content
			.background(LabCardStyle.background())
			.overlay(LabCardStyle.stroke())
			.shadow(color: .black.opacity(0.55), radius: 26, x: 0, y: 12)
	}
}

extension View {
	/// Wraps the view in The Lab's floating panel treatment.
	func labCard() -> some View {
		background(LabCardStyle.background())
			.overlay(LabCardStyle.stroke())
			.shadow(color: .black.opacity(0.55), radius: 26, x: 0, y: 12)
	}

	/// A thinner, lower card used for compact rows inside panels.
	func labCardCompact() -> some View {
		background(LabCardStyle.background())
			.overlay(LabCardStyle.stroke())
			.shadow(color: .black.opacity(0.4), radius: 14, x: 0, y: 6)
	}

	/// Adds a soft neon bloom around the panel — reserved for active states.
	func labCardGlow(_ color: Color, intensity: CGFloat = 0.22) -> some View {
		shadow(color: color.opacity(intensity), radius: 22, x: 0, y: 0)
	}
}

/// A whisper-thin hairline divider for stacking rows inside a card.
struct LabDivider: View {
	var body: some View {
		Rectangle()
			.fill(LabTheme.hairline)
			.frame(height: 1)
	}
}
