//
//	LabGlow.swift
//	The Lab
//
//	Created by Michael Shingara on 8/2/26.
//

import SwiftUI

// MARK: - Glow modifiers

extension View {
	/// Soft OLED "bloom" — a restrained halo for active buttons, focus
	/// states, and success signals. Two layered shadows keep it tight.
	func labGlow(_ color: Color, radius: CGFloat = 16, opacity: CGFloat = 0.28) -> some View {
		shadow(color: color.opacity(opacity), radius: radius)
			.shadow(color: color.opacity(opacity * 0.5), radius: radius * 2)
	}

	/// Conditional glow — clears to nothing when inactive.
	func labGlow(active: Bool, color: Color, radius: CGFloat = 14) -> some View {
		shadow(color: active ? color.opacity(0.35) : .clear, radius: radius)
	}
}

// MARK: - Button styles

/// Primary action — hot pink fill with a soft magenta halo.
struct LabPrimaryButtonStyle: ButtonStyle {
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.system(size: 16, weight: .semibold))
			.foregroundStyle(LabTheme.textPrimary)
			.padding(.horizontal, 22)
			.padding(.vertical, 12)
			.background(Capsule().fill(LabTheme.accent))
			.overlay(Capsule().stroke(LabTheme.accent.opacity(0.6), lineWidth: 1))
			.labGlow(LabTheme.accent, radius: 14, opacity: 0.32)
			.scaleEffect(configuration.isPressed ? 0.97 : 1)
			.animation(.snappy(duration: 0.2), value: configuration.isPressed)
	}
}

/// Ghost action — a near-black capsule with a hairline border.
struct LabGhostButtonStyle: ButtonStyle {
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.system(size: 15, weight: .medium))
			.foregroundStyle(LabTheme.textPrimary)
			.padding(.horizontal, 18)
			.padding(.vertical, 10)
			.background(Capsule().fill(LabTheme.surfaceElevated))
			.overlay(Capsule().stroke(LabTheme.hairline, lineWidth: 1))
			.scaleEffect(configuration.isPressed ? 0.97 : 1)
			.animation(.snappy(duration: 0.2), value: configuration.isPressed)
	}
}

/// Success state — neon green bloom for completed operations.
struct LabSuccessButtonStyle: ButtonStyle {
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.system(size: 16, weight: .semibold))
			.foregroundStyle(LabTheme.oledBlack)
			.padding(.horizontal, 22)
			.padding(.vertical, 12)
			.background(Capsule().fill(LabTheme.neon))
			.labGlow(LabTheme.neon, radius: 16, opacity: 0.3)
			.scaleEffect(configuration.isPressed ? 0.97 : 1)
			.animation(.snappy(duration: 0.2), value: configuration.isPressed)
	}
}
