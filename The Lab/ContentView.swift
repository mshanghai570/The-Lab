//
//  ContentView.swift
//  The Lab
//
//  Created by Michael Shingara on 8/1/26.
//

import SwiftUI

/// Root container for the app.
/// Kept for compatibility with the project template; the actual
/// app UI lives in `The_LabApp` via `VariedTabbarView()`.
struct ContentView: View {
	@StateObject private var downloadManager = DownloadManager.shared
	let storage = Storage.shared
	
	var body: some View {
		VStack(spacing: 0) {
			DownloadHeaderView(downloadManager: downloadManager)
			VariedTabbarView()
				.environment(\.managedObjectContext, storage.context)
		}
	}
}

#Preview {
	ContentView()
}
