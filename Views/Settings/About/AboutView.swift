//
//  AboutView.swift
//  The Lab
//
//  Created by Michael Shingara on 8/2/26.
//

import SwiftUI
import NimbleViews

// MARK: - Extension: Model
extension AboutView {
	struct CreditsModel: Codable, Hashable {
		let name: String?
		let desc: String?
		let github: String
	}
}

// MARK: - View
struct AboutView: View {
	@State private var _credits: [CreditsModel] = [
		.init(name: "C", desc: "Developer", github: "claration"),
		.init(name: "Asami", desc: "Developer", github: "Nyasami"),
		.init(name: "Lakhan Lothiyi", desc: "AltStore Repositories", github: "llsc12"),
	]
	
	// MARK: Body
	var body: some View {
		NBList(.localized("About")) {
			Section {
				VStack(spacing: 6) {
					FRAppIconView(size: 72)
					
					Text(Bundle.main.exec)
						.font(.largeTitle)
						.bold()
						.foregroundStyle(Color.accentColor)
					
					Text("An experimental IPA workspace.")
						.font(.footnote)
						.foregroundStyle(.secondary)
					
					HStack(spacing: 4) {
						Text(.localized("Version"))
						Text(Bundle.main.version)
					}
					.font(.footnote)
					.foregroundStyle(.secondary)
					
					if let tag = Bundle.main.infoDictionary?["AppBuildTag"] as? String {
						Text(tag)
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
				}
			}
			.frame(maxWidth: .infinity)
			.listRowBackground(EmptyView())
			
			NBSection(.localized("Developer")) {
				Button {
					UIApplication.open("https://github.com/mshanghai570")
				} label: {
					HStack {
						FRIconCellView(
							title: "Michael",
							subtitle: "@mshanghai570",
							iconUrl: URL(string: "https://github.com/mshanghai570.png"),
							size: 45,
							isCircle: true
						)
							
						Image(systemName: "arrow.up.right")
							.foregroundColor(.secondary.opacity(0.65))
					}
				}
			}
				
			NBSection(.localized("Lab Assistants")) {
				Label("Big Pickle", systemImage: "sparkles")
				Label("Kit", systemImage: "sparkles")
			}
			
			NBSection(.localized("Built upon the foundations created by:")) {
				ForEach(_credits, id: \.github) { credit in
					_credit(name: credit.name, desc: credit.desc, github: credit.github)
				}
				.transition(.slide)
			}
		}
	}
}

// MARK: - Extension: view
extension AboutView {
	@ViewBuilder
	private func _credit(
		name: String?,
		desc: String?,
		github: String
	) -> some View {
		Button {
			UIApplication.open("https://github.com/\(github)")
		} label: {
			HStack {
				FRIconCellView(
					title: name ?? github,
					subtitle: desc ?? "",
					iconUrl: URL(string: "https://github.com/\(github).png")!,
					size: 45,
					isCircle: true
				)
				
				Image(systemName: "arrow.up.right")
					.foregroundColor(.secondary.opacity(0.65))
			}
		}
	}
}
