//
//  LibraryView.swift
//  The Lab
//
//  Created by Michael Shingara on 8/2/26.
//

import SwiftUI
import CoreData
import NimbleViews

// MARK: - View
struct LibraryView: View {
	@StateObject var downloadManager = DownloadManager.shared
	@StateObject var updateManager = UpdateManager.shared

	@State private var _selectedInfoAppPresenting: AnyApp?
	@State private var _selectedSigningAppPresenting: AnyApp?
	@State private var _selectedInstallAppPresenting: AnyApp?
	@State private var _isImportingPresenting = false
	@State private var _isDownloadingPresenting = false
	@State private var _alertDownloadString: String = ""
	@State private var _updateCheckRotation = 0.0
	@State private var _isUpdateCheckCompleteVisible = false

	// MARK: Selection State
	@State private var _selectedAppUUIDs: Set<String> = []
	@State private var _editMode: EditMode = .inactive

	@State private var _searchText = ""
	@State private var _selectedScope: Scope = .all

	@Namespace private var _namespace

	// MARK: Fetch
	@FetchRequest(
		entity: Signed.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)],
		animation: .snappy
	) private var _signedApps: FetchedResults<Signed>

	@FetchRequest(
		entity: Imported.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)],
		animation: .snappy
	) private var _importedApps: FetchedResults<Imported>

	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>

	// MARK: Filtering
	private func filteredAndSortedApps<T>(from apps: FetchedResults<T>) -> [T] where T: NSManagedObject {
		apps.filter {
			_searchText.isEmpty ||
				(($0.value(forKey: "name") as? String)?.localizedCaseInsensitiveContains(_searchText) ?? false)
		}
	}

	private var _filteredSignedApps: [Signed] {
		filteredAndSortedApps(from: _signedApps)
	}

	private var _filteredImportedApps: [Imported] {
		filteredAndSortedApps(from: _importedApps)
	}

	private var _showSignedSection: Bool {
		!_filteredSignedApps.isEmpty && (_selectedScope == .all || _selectedScope == .signed)
	}

	private var _showImportedSection: Bool {
		!_filteredImportedApps.isEmpty && (_selectedScope == .all || _selectedScope == .imported)
	}

	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Library")) {
			ZStack {
				LabTheme.oledBlack.ignoresSafeArea()

				VStack(spacing: 0) {
					// Search field inside the content (not nav bar)
					LabSearchField(text: $_searchText, placeholder: "Search library")
						.padding(.horizontal, LabTheme.pagePadding)
						.padding(.top, 8)

					// Scope chips
					_scopeChips
						.padding(.top, 8)

					// List — swipe actions (slide-to-delete) only work in a List,
					// not in a ScrollView/LazyVStack.
					List {
						if _showSignedSection {
							Section {
								ForEach(_filteredSignedApps, id: \.uuid) { app in
									LabSpecimenCard(
										app: app,
										selectedInfoAppPresenting: $_selectedInfoAppPresenting,
										selectedSigningAppPresenting: $_selectedSigningAppPresenting,
										selectedInstallAppPresenting: $_selectedInstallAppPresenting,
										selectedAppUUIDs: $_selectedAppUUIDs
									)
									.listRowBackground(Color.clear)
									.listRowInsets(EdgeInsets(top: 5, leading: LabTheme.pagePadding, bottom: 5, trailing: LabTheme.pagePadding))
									.listRowSeparator(.hidden)
									.compatMatchedTransitionSource(id: app.uuid ?? "", ns: _namespace)
									.swipeActions(edge: .trailing, allowsFullSwipe: true) {
										Button(role: .destructive) {
											Storage.shared.deleteApp(for: app)
										} label: {
											Label("Delete", systemImage: "trash")
										}
									}
								}
							} header: {
								LabSectionHeader(title: "Signed", count: _filteredSignedApps.count, accent: LabTheme.accent)
									.listRowBackground(Color.clear)
							}
						}

						if _showImportedSection {
							Section {
								ForEach(_filteredImportedApps, id: \.uuid) { app in
									LabSpecimenCard(
										app: app,
										selectedInfoAppPresenting: $_selectedInfoAppPresenting,
										selectedSigningAppPresenting: $_selectedSigningAppPresenting,
										selectedInstallAppPresenting: $_selectedInstallAppPresenting,
										selectedAppUUIDs: $_selectedAppUUIDs
									)
									.listRowBackground(Color.clear)
									.listRowInsets(EdgeInsets(top: 5, leading: LabTheme.pagePadding, bottom: 5, trailing: LabTheme.pagePadding))
									.listRowSeparator(.hidden)
									.compatMatchedTransitionSource(id: app.uuid ?? "", ns: _namespace)
									.swipeActions(edge: .trailing, allowsFullSwipe: true) {
										Button(role: .destructive) {
											Storage.shared.deleteApp(for: app)
										} label: {
											Label("Delete", systemImage: "trash")
										}
									}
								}
							} header: {
								LabSectionHeader(title: "Imported", count: _filteredImportedApps.count, accent: LabTheme.neon)
									.listRowBackground(Color.clear)
							}
						}
					}
					.listStyle(.plain)
					.scrollContentBackground(.hidden)
					.scrollDismissesKeyboard(.interactively)
					.overlay {
						if _filteredSignedApps.isEmpty && _filteredImportedApps.isEmpty {
							_emptyState
						}
					}
				}
			}
			.scrollDismissesKeyboard(.interactively)
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					EditButton()
				}

				if _editMode.isEditing {
					NBToolbarButton(
						.localized("Delete"),
						systemImage: "trash",
						isDisabled: _selectedAppUUIDs.isEmpty
					) {
						_bulkDeleteSelectedApps()
					}
				} else {
					ToolbarItem(placement: .topBarTrailing) {
						Button {
							Task { await _checkForUpdates() }
						} label: {
							Image(systemName: _isUpdateCheckCompleteVisible ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
								.rotationEffect(.degrees(_updateCheckRotation))
								.animation(
									updateManager.isChecking
										? .linear(duration: 0.8).repeatForever(autoreverses: false)
										: .default,
									value: _updateCheckRotation
								)
						}
						.disabled(updateManager.isChecking)
						.accessibilityLabel(.localized("Check for Updates"))
					}

					NBToolbarMenu(
						systemImage: "plus",
						style: .icon,
						placement: .topBarTrailing
					) {
						_importActions()
					}
				}
			}
			.environment(\.editMode, $_editMode)
			.sheet(item: $_selectedInfoAppPresenting) { app in
				LibraryInfoView(app: app.base)
			}
			.sheet(item: $_selectedInstallAppPresenting) { app in
				InstallPreviewView(app: app.base, isSharing: app.archive)
					.presentationDetents([.height(200)])
					.presentationDragIndicator(.visible)
			}
			.fullScreenCover(item: $_selectedSigningAppPresenting) { app in
				SigningView(app: app.base)
					.compatNavigationTransition(id: app.base.uuid ?? "", ns: _namespace)
			}
			.sheet(isPresented: $_isImportingPresenting) {
				FileImporterRepresentableView(
					allowedContentTypes: [.ipa, .tipa],
					allowsMultipleSelection: true,
					onDocumentsPicked: { urls in
						guard !urls.isEmpty else { return }
						for url in urls {
							let id = "FeatherManualDownload_\(UUID().uuidString)"
							let dl = downloadManager.startArchive(from: url, id: id)
							try? downloadManager.handlePachageFile(url: url, dl: dl)
						}
					}
				)
				.ignoresSafeArea()
			}
			.alert(.localized("Import from URL"), isPresented: $_isDownloadingPresenting) {
				TextField(.localized("URL"), text: $_alertDownloadString)
					.textInputAutocapitalization(.never)
				Button(.localized("Cancel"), role: .cancel) {
					_alertDownloadString = ""
				}
				Button(.localized("OK")) {
					if let url = URL(string: _alertDownloadString) {
						_ = downloadManager.startDownload(from: url, id: "FeatherManualDownload_\(UUID().uuidString)")
					}
				}
			}
			.onReceive(NotificationCenter.default.publisher(for: Notification.Name("Feather.installApp"))) { _ in
				if let latest = _signedApps.first {
					_selectedInstallAppPresenting = AnyApp(base: latest)
				}
			}
			.onChange(of: _editMode) { mode in
				if mode == .inactive { _selectedAppUUIDs.removeAll() }
			}
			.onChange(of: updateManager.isChecking) { isChecking in
				_handleUpdateCheckStateChange(isChecking)
			}
		}
	}

	// MARK: - Subviews

	private var _scopeChips: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 8) {
				ForEach(Scope.allCases) { item in
					Button {
						withAnimation(.snappy(duration: 0.25)) { _selectedScope = item }
					} label: {
						Text(item.displayName)
							.font(.system(size: 13, weight: .semibold))
							.foregroundStyle(_selectedScope == item ? LabTheme.textPrimary : LabTheme.textTertiary)
							.padding(.horizontal, 14)
							.padding(.vertical, 7)
							.background(
								Capsule().fill(_selectedScope == item ? LabTheme.surfaceElevated : LabTheme.surfaceSecondary)
							)
							.overlay(
								Capsule().stroke(
									_selectedScope == item ? LabTheme.accent.opacity(0.5) : LabTheme.hairline,
									lineWidth: 1
								)
							)
							.labGlow(active: _selectedScope == item, color: LabTheme.accent, radius: 8)
					}
					.buttonStyle(.plain)
				}
			}
			.padding(.horizontal, LabTheme.pagePadding)
		}
	}

	private var _emptyState: some View {
		VStack(spacing: 14) {
			LabBeakerIcon(size: 88)
				.padding(.top, 10)

			Text("No Apps")
				.font(.playfair(22, weight: .semiBold))
				.foregroundStyle(LabTheme.textPrimary)

			Text("Get started by importing your first IPA file.")
				.font(.playfair(14, weight: .regular))
				.foregroundStyle(LabTheme.textTertiary)
				.multilineTextAlignment(.center)

			Menu {
				_importActions()
			} label: {
				Label("Import", systemImage: "plus")
			}
			.buttonStyle(LabPrimaryButtonStyle())
			.padding(.top, 8)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.padding(.bottom, 60)
	}

	// MARK: - Actions

	@ViewBuilder
	private func _importActions() -> some View {
		Button(.localized("Import from Files"), systemImage: "folder") {
			_isImportingPresenting = true
		}
		Button(.localized("Import from URL"), systemImage: "globe") {
			_isDownloadingPresenting = true
		}
	}

	// MARK: - Bulk Delete
	private func _bulkDeleteSelectedApps() {
		let selectedApps = _getAllApps().filter { app in
			guard let uuid = app.uuid else { return false }
			return _selectedAppUUIDs.contains(uuid)
		}

		for app in selectedApps {
			Storage.shared.deleteApp(for: app)
		}

		_selectedAppUUIDs.removeAll()
	}

	private func _getAllApps() -> [AppInfoPresentable] {
		var allApps: [AppInfoPresentable] = []

		if _selectedScope == .all || _selectedScope == .signed {
			allApps.append(contentsOf: _filteredSignedApps)
		}

		if _selectedScope == .all || _selectedScope == .imported {
			allApps.append(contentsOf: _filteredImportedApps)
		}

		return allApps
	}

	private func _checkForUpdates() async {
		let localApps = _signedApps.map { $0 as AppInfoPresentable } + _importedApps.map { $0 as AppInfoPresentable }
		await updateManager.checkForUpdates(
			sources: Array(_sources),
			localApps: localApps
		)
	}

	private func _handleUpdateCheckStateChange(_ isChecking: Bool) {
		if isChecking {
			_isUpdateCheckCompleteVisible = false
			_updateCheckRotation = 0
			withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
				_updateCheckRotation = 360
			}
		} else {
			withAnimation(.none) { _updateCheckRotation = 0 }
			_isUpdateCheckCompleteVisible = true
			Task { @MainActor in
				try? await Task.sleep(nanoseconds: 900_000_000)
				if !updateManager.isChecking { _isUpdateCheckCompleteVisible = false }
			}
		}
	}

	// MARK: - Scope
	enum Scope: String, CaseIterable, Identifiable {
		case all, signed, imported
		var id: String { rawValue }
		var displayName: String {
			switch self {
			case .all: return .localized("All")
			case .signed: return .localized("Signed")
			case .imported: return .localized("Imported")
			}
		}
	}
}