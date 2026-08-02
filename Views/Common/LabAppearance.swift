//
//	LabAppearance.swift
//	The Lab
//
//	Created by Michael Shingara on 8/2/26.
//

import SwiftUI
import UIKit

/// Configures the app-wide UIKit appearances so every screen — including the
/// Form/List based ones The Lab inherits — renders on a true OLED canvas
/// instead of the system's gray.
enum LabAppearance {
	static func configure() {
		// Root window canvas.
		if let window = UIApplication.shared.connectedScenes
			.compactMap({ $0 as? UIWindowScene })
			.flatMap({ $0.windows })
			.first {
			window.backgroundColor = .black
		}

		// Navigation bars — opaque black, white titles.
		let nav = UINavigationBarAppearance()
		nav.configureWithOpaqueBackground()
		nav.backgroundColor = .black
		nav.titleTextAttributes = [.foregroundColor: UIColor.white]
		nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
		UINavigationBar.appearance().standardAppearance = nav
		UINavigationBar.appearance().scrollEdgeAppearance = nav
		UINavigationBar.appearance().compactAppearance = nav

		// Tab bars — opaque black.
		let tab = UITabBarAppearance()
		tab.configureWithOpaqueBackground()
		tab.backgroundColor = .black
		UITabBar.appearance().standardAppearance = tab
		UITabBar.appearance().scrollEdgeAppearance = tab

		// Lists / forms — black canvas, whisper-thin separators.
		UITableView.appearance().backgroundColor = .black
		UITableView.appearance().separatorColor = UIColor.white.withAlphaComponent(0.06)

		// Search bars — black, dark keyboard style.
		let search = UISearchBar.appearance()
		search.barStyle = .black
		search.backgroundColor = .black
	}
}
