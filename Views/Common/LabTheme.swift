//
//	LabTheme.swift
//	The Lab
//
//	Created by Michael Shingara on 8/2/26.
//

import SwiftUI

/// The Lab's design tokens.
///
/// The canvas is true OLED black; everything else sits on a ladder of
/// near-black surfaces so the black disappears into the display and the
/// panels feel like they're floating above it.
enum LabTheme {
	// MARK: - OLED canvas
	/// Pure black. The display disappears behind everything else.
	static let oledBlack = Color(red: 0.0, green: 0.0, blue: 0.0)

	// MARK: - Near-black surfaces
	/// Primary surface — most page backgrounds rest here.
	static let surfacePrimary = Color(red: 10.0 / 255.0, green: 10.0 / 255.0, blue: 12.0 / 255.0)
	/// Secondary surface — search fields, input wells, inset areas.
	static let surfaceSecondary = Color(red: 18.0 / 255.0, green: 18.0 / 255.0, blue: 20.0 / 255.0)
	/// Elevated panels — cards that hover above the canvas.
	static let surfaceElevated = Color(red: 24.0 / 255.0, green: 24.0 / 255.0, blue: 28.0 / 255.0)

	// MARK: - Signal palette
	/// The Lab's primary accent — follows the user's chosen theme color
	/// (`Feather.userTintColor`, set by the Appearance theme picker).
	/// Falls back to the classic hot pink when nothing is stored.
	static var accent: Color {
		let hex = UserDefaults.standard.string(forKey: "Feather.userTintColor") ?? "#FF0097"
		return Color(hex: hex)
	}
	/// Neon green — success, live signals, outlines.
	static let neon = Color(red: 0.0, green: 1.0, blue: 0.0)

	// MARK: - Text hierarchy
	/// Primary text — near white.
	static let textPrimary = Color.white
	/// Secondary text.
	static let textSecondary = Color.white.opacity(0.72)
	/// Tertiary text — labels, captions, hints.
	static let textTertiary = Color.white.opacity(0.45)

	// MARK: - Hairlines
	/// Default hairline stroke — lets panels read against black without noise.
	static let hairline = Color.white.opacity(0.07)
	/// Stronger hairline — hovered / focused states.
	static let hairlineStrong = Color.white.opacity(0.14)

	// MARK: - Metrics
	static let cardCornerRadius: CGFloat = 22
	static let cardPadding: CGFloat = 16
	static let pagePadding: CGFloat = 20
}
