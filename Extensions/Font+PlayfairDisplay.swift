//
//  Font+PlayfairDisplay.swift
//  The Lab
//
//  Created by Michael Shingara on 8/2/26.
//

import SwiftUI

/// The Lab's branding typeface.
/// The Playfair Display family ships inside `Resources/Fonts/` and is
/// registered via `UIAppFonts` in Info.plist.
enum Playfair {
	enum Weight: String, CaseIterable {
		case black = "PlayfairDisplay-Black"
		case blackItalic = "PlayfairDisplay-BlackItalic"
		case bold = "PlayfairDisplay-Bold"
		case boldItalic = "PlayfairDisplay-BoldItalic"
		case extraBold = "PlayfairDisplay-ExtraBold"
		case extraBoldItalic = "PlayfairDisplay-ExtraBoldItalic"
		case italic = "PlayfairDisplay-Italic"
		case medium = "PlayfairDisplay-Medium"
		case mediumItalic = "PlayfairDisplay-MediumItalic"
		case regular = "PlayfairDisplay-Regular"
		case semiBold = "PlayfairDisplay-SemiBold"
		case semiBoldItalic = "PlayfairDisplay-SemiBoldItalic"
		case variable = "PlayfairDisplay-VariableFont_wght"
	}
}

extension Font {
	/// Playfair Display — The Lab's branding font.
	static func playfair(_ size: CGFloat, weight: Playfair.Weight = .regular) -> Font {
		.custom(weight.rawValue, size: size)
	}
}
