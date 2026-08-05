//
//	Font+PlayfairDisplay.swift
//	The Lab
//
//	Created by Michael Shingara on 8/2/26.
//

import SwiftUI

/// The Lab's branding typeface.
///
/// The Playfair Display family ships four static weights inside
/// `Resources/Fonts/` and is registered via `UIAppFonts` in Info.plist.
/// Use the semantic weights — they map to the four bundled faces so the
/// package stays lean:
///
///	  - Bold	 → hero headers ("THE LAB", page titles)
///	  - SemiBold → card titles, specimen names
///	  - Regular	 → secondary / body text
///	  - Italic	 → special accents, specimen annotations
enum Playfair {
	enum Weight: String, CaseIterable {
		case bold = "PlayfairDisplay-Bold"
		case semiBold = "PlayfairDisplay-SemiBold"
		case regular = "PlayfairDisplay-Regular"
		case italic = "PlayfairDisplay-Italic"
	}
}

extension Font {
	/// Playfair Display — The Lab's branding font.
	static func playfair(_ size: CGFloat, weight: Playfair.Weight = .regular) -> Font {
		.custom(weight.rawValue, size: size)
	}
}
