//
//	SourcesView.swift
//	The Lab
//
//	Created by samara on 10.04.2025.
//

import CoreData
import AltSourceKit
import SwiftUI
import NimbleViews

// MARK: - View
struct SourcesView: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@StateObject var viewModel = SourcesViewModel.shared
	@State private var _isAddingPresenting = false
	@State private var _addingSourceLoading = false
	@State private var _searchText = ""

	private var _filteredSources: [AltSource] {
		_sources.filter { _searchText.isEmpty || ($0.name?.localizedCaseInsensitiveContains(_searchText) ?? false) }
	}

	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>

	// MARK: Body
	var body: some View {
		NBNavigationView("", displayMode: .inline) {
			ScrollView {
				VStack(alignment: .leading, spacing: 18) {
					LabBrandView()
						.padding(.top, 8)

					LabSearchField(text: $_searchText)

					if _filteredSources.isEmpty {
						_emptyState
					} else {
						_allRepositoriesCard

						LabSectionHeader(
							title: .localized("Repositories"),
							count: _filteredSources.count
						)
						.padding(.top, 2)

						_repositoriesCard
					}
				}
				.padding(.horizontal, LabTheme.pagePadding)
				.padding(.bottom, 40)
			}
			.background(LabTheme.oledBlack.ignoresSafeArea())
			.scrollDismissesKeyboard(.immediately)
			.toolbar {
				NBToolbarButton(
					systemImage: "plus",
					style: .icon,
					placement: .topBarTrailing,
					isDisabled: _addingSourceLoading
				) {
					_isAddingPresenting = true
				}
			}
			.refreshable {
				await viewModel.fetchSources(_sources, refresh: true)
			}
			.sheet(isPresented: $_isAddingPresenting) {
				SourcesAddView()
			}
		}
		.task(id: Array(_sources)) {
			await viewModel.fetchSources(_sources)
		}
	}
}

// MARK: - Components
extension SourcesView {
	private var _allRepositoriesCard: some View {
		NavigationLink {
			SourceAppsView(object: Array(_sources), viewModel: viewModel)
		} label: {
			HStack(spacing: 16) {
				Image("Repositories").appIconStyle()

				VStack(alignment: .leading, spacing: 3) {
					Text(.localized("All Repositories"))
						.font(.system(size: 17, weight: .semibold))
						.foregroundStyle(LabTheme.textPrimary)
					Text(.localized("See all apps from your sources"))
						.font(.system(size: 14))
						.foregroundStyle(LabTheme.textTertiary)
				}

				Spacer()

				Image(systemName: "chevron.right")
					.font(.system(size: 13, weight: .semibold))
					.foregroundStyle(LabTheme.textTertiary)
			}
			.padding(LabTheme.cardPadding)
			.labCard()
			.contentShape(
				RoundedRectangle(cornerRadius: LabTheme.cardCornerRadius, style: .continuous)
			)
		}
		.buttonStyle(.plain)
	}

	private var _repositoriesCard: some View {
		LabCard {
			VStack(spacing: 0) {
				ForEach(Array(_filteredSources.enumerated()), id: \.element.identifier) { index, source in
					NavigationLink {
						SourceAppsView(object: [source], viewModel: viewModel)
					} label: {
						SourcesCellView(source: source)
					}
					.buttonStyle(.plain)
					.padding(.horizontal, 12)
					.padding(.vertical, 12)

					if index < _filteredSources.count - 1 {
						LabDivider()
							.padding(.leading, 58)
					}
				}
			}
		}
	}

	private var _emptyState: some View {
		LabCard {
			VStack(spacing: 14) {
				LabBeakerIcon(size: 88)
					.padding(.top, 12)

				Text(.localized("No Repositories"))
					.font(.playfair(22, weight: .semiBold))
					.foregroundStyle(LabTheme.textPrimary)

				Text(.localized("Get started by adding your first repository."))
					.font(.system(size: 14))
					.foregroundStyle(LabTheme.textTertiary)
					.multilineTextAlignment(.center)

				Button {
					_isAddingPresenting = true
				} label: {
					Text(.localized("Add Source"))
				}
				.buttonStyle(LabPrimaryButtonStyle())
				.padding(.top, 6)
				.padding(.bottom, 12)
			}
			.frame(maxWidth: .infinity)
			.padding(20)
		}
	}
}
