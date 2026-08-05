//
//	QuickLookPreview.swift
//	The Lab
//
//	Created by Michael Shingara on 8/2/26.
//

import SwiftUI
import QuickLook

/// Presents a file with the system Quick Look preview — free viewing for
/// plists, text, images, archives and everything else while The Lab's own
/// modular editors are being built.
struct QuickLookPreview: UIViewControllerRepresentable {
	let url: URL

	func makeCoordinator() -> Coordinator {
		Coordinator(url: url)
	}

	func makeUIViewController(context: Context) -> QLPreviewController {
		let controller = QLPreviewController()
		controller.dataSource = context.coordinator
		return controller
	}

	func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

	final class Coordinator: NSObject, QLPreviewControllerDataSource {
		let url: URL

		init(url: URL) {
			self.url = url
		}

		func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

		func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
			url as NSURL
		}
	}
}
