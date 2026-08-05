//
//  AppIconView.swift
//  The Lab
//
//  Created by Michael Shingara on 8/4/26.
//

import SwiftUI
import NimbleViews

// MARK: - View extension: Model
extension AppIconView {
	struct AltIcon: Identifiable {
		var displayName: String
		var author: String
		var key: String?
		var image: UIImage
		var id: String { key ?? displayName }
		
		init(displayName: String, author: String, key: String? = nil) {
			self.displayName = displayName
			self.author = author
			self.key = key
			self.image = altImage(key)
		}
	}
	
	static func altImage(_ name: String?) -> UIImage {
		// Alternate icon PNGs land at the bundle root as <name>.png.
		// The default row (key == nil) shows the primary icon, which the
		// asset catalog compiles to AppIcon60x60@2x.png.
		let fileName = name.map { "\($0).png" } ?? "AppIcon60x60@2x.png"
		let path = Bundle.main.bundleURL.appendingPathComponent(fileName)
		return UIImage(contentsOfFile: path.path) ?? UIImage()
	}
}

// MARK: - View
struct AppIconView: View {
	@Binding var currentIcon: String?
	
	// dont translate
	var sections: [String: [AltIcon]] = [
		"The Lab": [
			AltIcon(displayName: "Default", author: "The Lab", key: nil),
			AltIcon(displayName: "thelabicon4", author: "The Lab", key: "thelabicon4"),
			AltIcon(displayName: "IMG_2780", author: "The Lab", key: "IMG_2780"),
			AltIcon(displayName: "IMG_2775", author: "The Lab", key: "IMG_2775"),
			AltIcon(displayName: "1785716933087_0", author: "The Lab", key: "1785716933087_0")
		]
	]
	
	// MARK: Body
	var body: some View {
		NBList(.localized("App Icon")) {
			ForEach(sections.keys.sorted(), id: \.self) { section in
				if let icons = sections[section] {
					NBSection(section) {
						ForEach(icons) { icon in
							_icon(icon: icon)
						}
					}
				}
			}
		}
		.onAppear {
			currentIcon = UIApplication.shared.alternateIconName
		}
	}
}

// MARK: - View extension
extension AppIconView {
	@ViewBuilder
	private func _icon(
		icon: AppIconView.AltIcon
	) -> some View {
		Button {
			UIApplication.shared.setAlternateIconName(icon.key) { _ in
				currentIcon = UIApplication.shared.alternateIconName
			}
		} label: {
			HStack(spacing: 18) {
				Image(uiImage: icon.image)
					.appIconStyle()
				
				NBTitleWithSubtitleView(
					title: icon.displayName,
					subtitle: icon.author,
					linelimit: 0
				)
				
				if currentIcon == icon.key {
					Image(systemName: "checkmark").bold()
				}
			}
		}
	}
}
