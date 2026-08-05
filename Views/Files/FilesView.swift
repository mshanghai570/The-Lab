//
//  FilesView.swift
//  The Lab
//
//  Created by Michael Shingara on 8/2/26.
//

import SwiftUI
import UniformTypeIdentifiers
import Zip
import NimbleExtensions
import NimbleViews

/// The Lab's file workspace — the archive where specimens live.
///
/// The archive is organized as folders. IPAs pulled from repos or imported
/// from the device land here, alongside dylibs, plists and any other file
/// worth keeping. Tapping an IPA opens it into a live workspace; everything
/// else previews with Quick Look.
struct FilesView: View {
	@StateObject private var viewModel = FilesViewModel()

	@State private var searchText = ""
	@State private var scope: Scope = .all
	@State private var isImporterPresented = false
	@State private var previewTarget: PreviewTarget?
	@State private var workspaceTarget: WorkspaceTarget?
	@State private var isUnpacking = false
	@State private var unpackError: String?
	@State private var isArchiving = false
	@State private var archiveError: String?

	// Rename / create folder / delete folder / move
	@State private var renameTarget: RenameTarget?
	@State private var renameText = ""
	@State private var isNewFolderPresented = false
	@State private var newFolderName = ""
	@State private var folderError: String?
	@State private var pendingDeleteFolder: LabFolder?
	@State private var moveItem: MoveItem?
	@State private var moveDestinations: [(folder: LabFolder, depth: Int)] = []
	@State private var importResult: FilesViewModel.ImportResult?
	/// Editor opened from a long-press on a specimen card (text/plist/hex).
	@State private var editorTarget: FileEditorTarget?
	/// IPA packaged from an `.app` folder, waiting for the “Package Ready” alert.
	@State private var packagedResult: PackageResult?
	@State private var libraryError: String?
	/// Folder rejection feedback for the editor buttons (defense-in-depth —
	/// editors must never receive a directory URL).
	@State private var editorError: String?

	/// Paths that have already flown in — drives the stagger appear animation.
	@State private var appearedIDs: Set<String> = []

	var body: some View {
		ZStack {
			LabTheme.oledBlack.ignoresSafeArea()

			if viewModel.files.isEmpty && viewModel.folders.isEmpty && !isUnpacking {
				_emptyState
			} else {
				_content
			}

			if isUnpacking {
				_unpackingOverlay
			}

			if isArchiving {
				_archivingOverlay
			}
		}
		.onAppear { viewModel.refresh() }
		.onReceive(NotificationCenter.default.publisher(for: .filesDidChange)) { _ in
			viewModel.refresh()
		}
		.toolbar {
			if !viewModel.isAtRoot {
				ToolbarItem(placement: .topBarLeading) {
					Button {
						withAnimation(.snappy(duration: 0.25)) { viewModel.goBack() }
					} label: {
						Image(systemName: "chevron.backward")
					}
					.accessibilityLabel("Back")
				}
			}

			ToolbarItem(placement: .topBarTrailing) {
				Menu {
					Button {
						isImporterPresented = true
					} label: {
						Label("Import Specimens", systemImage: "plus")
					}
					Button {
						newFolderName = ""
						isNewFolderPresented = true
					} label: {
						Label("New Folder", systemImage: "folder.badge.plus")
					}
				} label: {
					Image(systemName: "plus")
				}
				.accessibilityLabel("Archive Actions")
			}
		}
		.sheet(isPresented: $isImporterPresented) {
			// The app-wide UIKit picker (asCopy: true) — the same one Certificates,
			// Signing and Tweaks use. It hands over a plain local copy, which
			// avoids the security-scoped URL + iCloud materialization failures
			// of SwiftUI's .fileImporter, and it presents as a plain sheet so it
			// can't fight the alert chain below.
			FileImporterRepresentableView(
				allowedContentTypes: [.item],
				allowsMultipleSelection: true,
				onDocumentsPicked: { urls in
					guard !urls.isEmpty else { return }
					let outcome = viewModel.importFiles(from: urls)
					importResult = outcome
					// Esign-style: picking a specimen should land you inside it.
					// Auto-open only when exactly one thing landed (or already
					// existed) so multi-select keeps the summary alert instead.
					if outcome.failed.isEmpty, outcome.openable.count == 1, let first = outcome.openable.first {
						importResult = nil
						_openImported(first)
					}
				}
			)
			.ignoresSafeArea()
		}
		.alert("Import", isPresented: Binding(
			get: { importResult != nil },
			set: { if !$0 { importResult = nil } }
		)) {
			Button("OK", role: .cancel) { importResult = nil }
			if let package = importResult?.firstPackage {
				Button("Open Workspace") {
					let url = package
					importResult = nil
					_openImported(url)
				}
			}
		} message: {
			Text(importResult?.summary ?? "")
		}
		.sheet(item: $previewTarget) { target in
			QuickLookPreview(url: target.url)
				.ignoresSafeArea()
		}
		.sheet(item: $editorTarget) { target in
			switch target.kind {
			case .text:
				LabTextEditorView(url: target.url, preloadedData: target.data) { editorTarget = FileEditorTarget(url: target.url, kind: $0, data: target.data) }
			case .plist:
				LabPlistEditorView(url: target.url, preloadedData: target.data) { editorTarget = FileEditorTarget(url: target.url, kind: $0, data: target.data) }
			case .hex:
				LabHexEditorView(url: target.url, preloadedData: target.data)
			}
		}
		.sheet(item: $workspaceTarget) { target in
			IPAWorkspaceView(sourceName: target.name, workspace: target.url)
		}
		.sheet(item: $moveItem) { item in
			LabMoveSheet(
				itemName: item.name,
				destinations: moveDestinations
			) { destination in
				switch item {
				case .file(let file): viewModel.move(file, to: destination)
				case .folder(let folder): viewModel.move(folder, to: destination)
				}
			}
		}
		.alert("New Folder", isPresented: $isNewFolderPresented) {
			TextField("Folder name", text: $newFolderName)
				.textInputAutocapitalization(.never)
			Button("Cancel", role: .cancel) { newFolderName = "" }
			Button("Create") {
				if let error = viewModel.createFolder(named: newFolderName) {
					folderError = error
				}
				newFolderName = ""
			}
		} message: {
			Text("Create a folder inside \(_currentLocationLabel).")
		}
		.alert("Folder Not Created", isPresented: Binding(
			get: { folderError != nil },
			set: { if !$0 { folderError = nil } }
		)) {
			Button("OK", role: .cancel) { folderError = nil }
		} message: {
			Text(folderError ?? "")
		}
		.alert("Rename", isPresented: Binding(
			get: { renameTarget != nil },
			set: { if !$0 { renameTarget = nil } }
		)) {
			TextField("Name", text: $renameText)
			Button("Cancel", role: .cancel) { renameTarget = nil }
			Button("Rename") {
				if let target = renameTarget {
					switch target {
					case .file(let file): viewModel.rename(file, to: renameText)
					case .folder(let folder): viewModel.rename(folder, to: renameText)
					}
				}
				renameTarget = nil
			}
		} message: {
			Text("Enter a new name for this \(renameTarget?.kindLabel ?? "item").")
		}
		.alert("Delete Folder", isPresented: Binding(
			get: { pendingDeleteFolder != nil },
			set: { if !$0 { pendingDeleteFolder = nil } }
		)) {
			Button("Cancel", role: .cancel) { pendingDeleteFolder = nil }
			Button("Delete", role: .destructive) {
				if let folder = pendingDeleteFolder {
					viewModel.delete(folder)
				}
				pendingDeleteFolder = nil
			}
		} message: {
			if let folder = pendingDeleteFolder {
				Text("Deleting \"\(folder.name)\" removes it and everything inside, including any specimens. This can't be undone.")
			}
		}
		.alert("Couldn't Open Workspace", isPresented: Binding(
			get: { unpackError != nil },
			set: { if !$0 { unpackError = nil } }
		)) {
			Button("OK", role: .cancel) { unpackError = nil }
		} message: {
			Text(unpackError ?? "")
		}
		.alert("Couldn't Archive", isPresented: Binding(
			get: { archiveError != nil },
			set: { if !$0 { archiveError = nil } }
		)) {
			Button("OK", role: .cancel) { archiveError = nil }
		} message: {
			Text(archiveError ?? "")
		}
		.alert("Package Ready", isPresented: Binding(
			get: { packagedResult != nil },
			set: { if !$0 { packagedResult = nil } }
		)) {
			Button("Done", role: .cancel) { packagedResult = nil }
			if let url = packagedResult?.url {
				Button("Add to Library") {
					FR.handlePackageFile(url) { error in
						if let error {
							libraryError = error.localizedDescription
						} else {
							packagedResult = nil
						}
					}
				}
			}
		} message: {
			if let name = packagedResult?.name {
				Text("\(name) is ready. Add it to the Library to sign and install it.")
			}
		}
		.alert("Couldn't Add to Library", isPresented: Binding(
			get: { libraryError != nil },
			set: { if !$0 { libraryError = nil } }
		)) {
			Button("OK", role: .cancel) { libraryError = nil }
		} message: {
			Text(libraryError ?? "")
		}
		.alert("Can't Open Folder", isPresented: Binding(
			get: { editorError != nil },
			set: { if !$0 { editorError = nil } }
		)) {
			Button("OK", role: .cancel) { editorError = nil }
		} message: {
			Text(editorError ?? "")
		}
	}

	// MARK: - Content

	private var _content: some View {
		VStack(spacing: 0) {
			_header

			if !viewModel.isAtRoot {
				_breadcrumb
					.padding(.top, 6)
			}

			LabSearchField(text: $searchText, placeholder: "Search the archive")
				.padding(.horizontal, LabTheme.pagePadding)
				.padding(.top, 14)

			_scopeChips
				.padding(.top, 12)

			ScrollView {
				LazyVStack(alignment: .leading, spacing: 26) {
					if !viewModel.folders.isEmpty {
						_foldersSection
					}

					ForEach(_visibleSections, id: \.kind.rawValue) { section in
						_section(section.kind, files: section.files)
					}
				}
				.padding(.horizontal, LabTheme.pagePadding)
				.padding(.top, 20)
				.padding(.bottom, 40)
			}
		}
	}

	private var _header: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(viewModel.isAtRoot ? "Files" : viewModel.currentDirectory.lastPathComponent)
				.font(.playfair(34, weight: .bold))
				.foregroundStyle(LabTheme.textPrimary)
				.kerning(0.4)
				.lineLimit(1)

			Text("The Lab archive")
				.font(.playfair(16, weight: .italic))
				.foregroundStyle(LabTheme.textTertiary)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.horizontal, LabTheme.pagePadding)
		.padding(.top, 8)
	}

	private var _breadcrumb: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 5) {
				Button {
					withAnimation(.snappy(duration: 0.25)) { viewModel.goToRoot() }
				} label: {
					Text("Archive")
						.font(.system(size: 12, weight: .semibold))
						.foregroundStyle(LabTheme.neon.opacity(0.9))
				}
				.buttonStyle(.plain)

				let crumbs = viewModel.breadcrumbs
				ForEach(crumbs.indices.dropFirst(), id: \.self) { index in
					Image(systemName: "chevron.right")
						.font(.system(size: 9, weight: .semibold))
						.foregroundStyle(LabTheme.textTertiary)

					if index == crumbs.count - 1 {
						Text(crumbs[index].lastPathComponent)
							.font(.system(size: 12, weight: .semibold))
							.foregroundStyle(LabTheme.textPrimary)
							.lineLimit(1)
					} else {
						Button {
							withAnimation(.snappy(duration: 0.25)) { viewModel.goTo(index: index) }
						} label: {
							Text(crumbs[index].lastPathComponent)
								.font(.system(size: 12, weight: .semibold))
								.foregroundStyle(LabTheme.textSecondary)
								.lineLimit(1)
						}
						.buttonStyle(.plain)
					}
				}
			}
			.padding(.horizontal, LabTheme.pagePadding)
		}
	}

	private var _scopeChips: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 8) {
				ForEach(Scope.allCases) { item in
					Button {
						withAnimation(.snappy(duration: 0.25)) { scope = item }
					} label: {
						Text(item.label)
							.font(.system(size: 13, weight: .semibold))
							.foregroundStyle(scope == item ? LabTheme.textPrimary : LabTheme.textTertiary)
							.padding(.horizontal, 14)
							.padding(.vertical, 7)
							.background(
								Capsule().fill(scope == item ? LabTheme.surfaceElevated : LabTheme.surfaceSecondary)
							)
							.overlay(
								Capsule().stroke(
									scope == item ? LabTheme.accent.opacity(0.5) : LabTheme.hairline,
									lineWidth: 1
								)
							)
							.labGlow(active: scope == item, color: LabTheme.accent, radius: 8)
					}
					.buttonStyle(.plain)
				}
			}
			.padding(.horizontal, LabTheme.pagePadding)
		}
	}

	// MARK: - Folders

	private var _foldersSection: some View {
		VStack(alignment: .leading, spacing: 12) {
			LabSectionHeader(title: "Folders", count: viewModel.folders.count, accent: LabTheme.neon)

			LazyVGrid(
				columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
				spacing: 12
			) {
				ForEach(viewModel.folders) { folder in
					_folderCard(folder)
				}
			}
		}
	}

	private func _folderCard(_ folder: LabFolder) -> some View {
		Button {
			withAnimation(.snappy(duration: 0.25)) { viewModel.enter(folder) }
		} label: {
			VStack(alignment: .leading, spacing: 10) {
				HStack {
					ZStack {
						RoundedRectangle(cornerRadius: 12, style: .continuous)
							.fill(LabTheme.neon.opacity(0.1))
							.frame(width: 40, height: 40)

						Image(systemName: "folder.fill")
							.font(.system(size: 17, weight: .medium))
							.foregroundStyle(LabTheme.neon.opacity(0.9))
					}
					.labGlow(LabTheme.neon, radius: 8, opacity: 0.16)

					Spacer(minLength: 4)

					Menu {
						_folderActions(folder)
					} label: {
						Image(systemName: "ellipsis")
							.font(.system(size: 14, weight: .semibold))
							.foregroundStyle(LabTheme.textSecondary)
							.frame(width: 30, height: 30)
							.contentShape(Rectangle())
					}
				}

				Text(folder.name)
					.font(.playfair(15, weight: .semiBold))
					.foregroundStyle(LabTheme.textPrimary)
					.lineLimit(1)

				Text("\(folder.itemCount) item\(folder.itemCount == 1 ? "" : "s") • \(folder.modifiedLabel)")
					.font(.system(size: 11))
					.foregroundStyle(LabTheme.textTertiary)
					.lineLimit(1)
			}
			.padding(12)
			.labCardCompact()
			.contentShape(RoundedRectangle(cornerRadius: LabTheme.cardCornerRadius, style: .continuous))
		}
		.buttonStyle(.plain)
		.contextMenu {
			if folder.name.hasSuffix(".app") {
				// Esign-style: long-pressing an .app bundle offers to package it
				// back into a fresh unsigned IPA.
				Button {
					_packageAppFolder(folder)
				} label: {
					Label("Package IPA", systemImage: "shippingbox.and.arrow.backward")
				}
			}

			Button {
				renameText = folder.name
				renameTarget = .folder(folder)
			} label: {
				Label("Rename", systemImage: "pencil")
			}

			Button {
				moveDestinations = viewModel.folderDestinations(excluding: [folder.url.path])
				moveItem = .folder(folder)
			} label: {
				Label("Move to…", systemImage: "folder")
			}

			Button {
				_compress(folder.url)
			} label: {
				Label("Compress", systemImage: "shippingbox")
			}

			Divider()

			Button(role: .destructive) {
				pendingDeleteFolder = folder
			} label: {
				Label("Delete", systemImage: "trash")
			}
		}
		.opacity(appearedIDs.contains(folder.id) ? 1 : 0)
		.offset(y: appearedIDs.contains(folder.id) ? 0 : 8)
		.onAppear {
			let delay = _folderAppearDelay(folder)
			withAnimation(.snappy(duration: 0.35).delay(delay)) {
				appearedIDs.insert(folder.id)
			}
		}
	}

	@ViewBuilder
	private func _folderActions(_ folder: LabFolder) -> some View {
		Button {
			renameText = folder.name
			renameTarget = .folder(folder)
		} label: {
			Label("Rename", systemImage: "pencil")
		}

		Button {
			moveDestinations = viewModel.folderDestinations(excluding: [folder.url.path])
			moveItem = .folder(folder)
		} label: {
			Label("Move to…", systemImage: "folder")
		}

		Button {
			_compress(folder.url)
		} label: {
			Label("Compress", systemImage: "shippingbox")
		}

		Button(role: .destructive) {
			pendingDeleteFolder = folder
		} label: {
			Label("Delete", systemImage: "trash")
		}
	}

	// MARK: - Specimens

	private func _section(_ kind: LabFile.Kind, files: [LabFile]) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			LabSectionHeader(title: kind.label, count: files.count, accent: kind.accent)

			ForEach(files) { file in
				_card(for: file)
			}
		}
	}

	private func _card(for file: LabFile) -> some View {
		Button {
			_open(file)
		} label: {
			HStack(spacing: 14) {
				ZStack {
					RoundedRectangle(cornerRadius: 14, style: .continuous)
						.fill(file.kind.accent.opacity(0.12))
						.frame(width: 46, height: 46)

					Image(systemName: file.kind.systemImage)
						.font(.system(size: 19, weight: .medium))
						.foregroundStyle(file.kind.accent)
				}
				.labGlow(file.kind.accent, radius: 8, opacity: 0.18)

				VStack(alignment: .leading, spacing: 3) {
					Text(file.name)
						.font(.playfair(16, weight: .semiBold))
						.foregroundStyle(LabTheme.textPrimary)
						.lineLimit(1)

					HStack(spacing: 6) {
						Text(file.sizeLabel)
						Text("•")
						Text(file.modifiedLabel)
					}
					.font(.system(size: 12))
					.foregroundStyle(LabTheme.textTertiary)
				}

				Spacer(minLength: 8)

				if file.kind == .ipa || file.kind == .tipa {
					Text("SPECIMEN")
						.font(.system(size: 9, weight: .bold))
						.kerning(0.8)
						.foregroundStyle(LabTheme.accent)
						.padding(.horizontal, 8)
						.padding(.vertical, 4)
						.overlay(
							Capsule().stroke(LabTheme.accent.opacity(0.55), lineWidth: 1)
						)
				}

				Menu {
					_actions(for: file)
				} label: {
					Image(systemName: "ellipsis")
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(LabTheme.textSecondary)
						.frame(width: 32, height: 32)
						.contentShape(Rectangle())
				}
			}
			.padding(12)
			.labCardCompact()
			.contentShape(RoundedRectangle(cornerRadius: LabTheme.cardCornerRadius, style: .continuous))
		}
		.buttonStyle(.plain)
		.contextMenu {
			Button {
				_open(file)
			} label: {
				Label(file.kind == .ipa || file.kind == .tipa ? "Open Workspace" : "View File", systemImage: "eye")
			}

			Button {
				guard !_isDirectory(file.url) else {
					print("[Editors] Text editor requested — REJECTED: \(file.url.path) is a directory")
					editorError = "\(file.name) is a folder — open it, then pick a file inside to edit."
					return
				}
				print("[Editors] Text editor requested — \(file.url.path)")
				print("[Editors] Passing validation — reading bytes")
				// Probe the exact URL at selection time and hand the bytes to the
				// editor, so it provably reads what the user picked. Binary plists
				// (bplist00) can't be read as UTF-8 — route them to the Plist
				// Editor, which reads both binary and XML.
				let outcome = LabFileLoader.probe(file.url)
				print("[Editors] Presenting text editor for \(file.url.lastPathComponent)")
				_presentEditor(FileEditorTarget(
					url: file.url,
					kind: outcome.data?.starts(with: LabFileFormat.bplistHeader) == true ? .plist : .text,
					data: outcome.data
				))
			} label: {
				Label("Text Editor", systemImage: "doc.plaintext")
			}

			if _isPlist(file.url) {
				Button {
					guard !_isDirectory(file.url) else {
						print("[Editors] Plist editor requested — REJECTED: \(file.url.path) is a directory")
						editorError = "\(file.name) is a folder — open it, then pick a file inside to edit."
						return
					}
					print("[Editors] Plist editor requested — \(file.url.path)")
					print("[Editors] Passing validation — reading bytes")
					let outcome = LabFileLoader.probe(file.url)
					print("[Editors] Presenting plist editor for \(file.url.lastPathComponent)")
					_presentEditor(FileEditorTarget(url: file.url, kind: .plist, data: outcome.data))
				} label: {
					Label("Plist Editor", systemImage: "list.bullet.rectangle.portrait")
				}
			}

			Button {
				guard !_isDirectory(file.url) else {
					print("[Editors] Hex editor requested — REJECTED: \(file.url.path) is a directory")
					editorError = "\(file.name) is a folder — open it, then pick a file inside to edit."
					return
				}
				print("[Editors] Hex editor requested — \(file.url.path)")
				print("[Editors] Passing validation — reading bytes")
				let outcome = LabFileLoader.probe(file.url)
				print("[Editors] Presenting hex editor for \(file.url.lastPathComponent)")
				_presentEditor(FileEditorTarget(url: file.url, kind: .hex, data: outcome.data))
			} label: {
				Label("Hex Editor", systemImage: "number")
			}

			Divider()

			Button {
				UIActivityViewController.show(activityItems: [file.url])
			} label: {
				Label("Share", systemImage: "square.and.arrow.up")
			}

			if file.kind == .archive || file.kind == .ipa || file.kind == .tipa {
				Button {
					_unarchive(file.url)
				} label: {
					Label("Unarchive", systemImage: "archivebox")
				}
			}

			Divider()

			Button(role: .destructive) {
				viewModel.delete(file)
			} label: {
				Label("Delete", systemImage: "trash")
			}
		}
		.opacity(appearedIDs.contains(file.id) ? 1 : 0)
		.offset(y: appearedIDs.contains(file.id) ? 0 : 8)
		.onAppear {
			let delay = _appearDelay(for: file)
			withAnimation(.snappy(duration: 0.35).delay(delay)) {
				appearedIDs.insert(file.id)
			}
		}
	}

	@ViewBuilder
	private func _actions(for file: LabFile) -> some View {
		Button {
			_open(file)
		} label: {
			Label(file.kind == .ipa || file.kind == .tipa ? "Open Workspace" : "Preview", systemImage: "eye")
		}

		Button {
			UIActivityViewController.show(activityItems: [file.url])
		} label: {
			Label("Share", systemImage: "square.and.arrow.up")
		}

		Button {
			moveDestinations = viewModel.folderDestinations(excluding: [])
			moveItem = .file(file)
		} label: {
			Label("Move to…", systemImage: "folder")
		}

		Button {
			renameText = file.name
			renameTarget = .file(file)
		} label: {
			Label("Rename", systemImage: "pencil")
		}

		if file.kind == .archive || file.kind == .ipa || file.kind == .tipa {
			Button {
				_unarchive(file.url)
			} label: {
				Label("Unarchive", systemImage: "archivebox")
			}
		}

		Button {
			_compress(file.url)
		} label: {
			Label("Compress", systemImage: "shippingbox")
		}

		Button(role: .destructive) {
			viewModel.delete(file)
		} label: {
			Label("Delete", systemImage: "trash")
		}
	}

	// MARK: - Opening specimens

	private func _open(_ file: LabFile) {
		_open(url: file.url)
	}

	private func _openImported(_ url: URL) {
		// Folders land in the archive as folders — nothing to preview or open.
		let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
		guard !isDirectory else { return }
		_open(url: url)
	}

	private func _open(url: URL) {
		let kind = LabFile.Kind.classify(url)
		if kind == .ipa || kind == .tipa {
			isUnpacking = true
			Task {
				do {
					let workspace = try await IPAWorkspace.open(url)
					isUnpacking = false
					workspaceTarget = WorkspaceTarget(name: url.lastPathComponent, url: workspace)
				} catch {
					isUnpacking = false
					unpackError = error.localizedDescription
				}
			}
		} else {
			// The document picker may still be dismissing; presenting a sheet in
			// the same runloop as that dismissal can be silently swallowed by
			// SwiftUI. Nudge the preview onto a later tick.
			Task {
				try? await Task.sleep(nanoseconds: 600_000_000)
				previewTarget = PreviewTarget(url: url)
			}
		}
	}

	// MARK: - Zip / Unzip

	/// Compresses a file or folder into a `.zip` sitting next to it.
	private func _compress(_ url: URL) {
		guard !isArchiving else { return }
		isArchiving = true
		let fm = FileManager.default

		let base = url.deletingPathExtension().lastPathComponent
		var destination = url.deletingLastPathComponent().appendingPathComponent("\(base).zip")
		var counter = 1
		while fm.fileExists(atPath: destination.path) {
			destination = url.deletingLastPathComponent().appendingPathComponent("\(base) \(counter).zip")
			counter += 1
		}

		Task {
			do {
				try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
					DispatchQueue.global(qos: .userInitiated).async {
						do {
							try Zip.zipFiles(
								paths: [url],
								zipFilePath: destination,
								password: nil,
								compression: .BestCompression,
								progress: nil
							)
							cont.resume()
						} catch {
							cont.resume(throwing: error)
						}
					}
				}
				viewModel.refresh()
			} catch {
				archiveError = error.localizedDescription
			}
			isArchiving = false
		}
	}

	/// Unpacks an archive (`.zip`, `.ipa`, `.tipa`, …) into a sibling folder
	/// so its Payload and everything inside can be browsed from the archive.
	private func _unarchive(_ url: URL) {
		guard !isArchiving else { return }
		isArchiving = true
		let fm = FileManager.default

		Zip.addCustomFileExtension("ipa")
		Zip.addCustomFileExtension("tipa")

		let base = url.deletingPathExtension().lastPathComponent
		var destination = url.deletingLastPathComponent().appendingPathComponent(base, isDirectory: true)
		var counter = 1
		while fm.fileExists(atPath: destination.path) {
			destination = url.deletingLastPathComponent().appendingPathComponent("\(base) \(counter)", isDirectory: true)
			counter += 1
		}

		Task {
			do {
				try fm.createDirectory(at: destination, withIntermediateDirectories: true)
				try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
					DispatchQueue.global(qos: .userInitiated).async {
						do {
							try Zip.unzipFile(url, destination: destination, overwrite: true, password: nil, progress: nil)
							cont.resume()
						} catch {
							cont.resume(throwing: error)
						}
					}
				}
				viewModel.refresh()
			} catch {
				archiveError = error.localizedDescription
			}
			isArchiving = false
		}
	}

	// MARK: - Packaging .app bundles

	/// Esign-style: long-pressing an `.app` folder in the archive packages it
	/// back into a fresh unsigned IPA saved into the archive root.
	private func _packageAppFolder(_ folder: LabFolder) {
		guard !isArchiving else { return }
		isArchiving = true
		Task {
			do {
				let destination = try await IPAWorkspace.packageAppBundle(folder.url)
				packagedResult = PackageResult(url: destination, name: destination.lastPathComponent)
				NotificationCenter.default.post(name: .filesDidChange, object: nil)
			} catch {
				archiveError = error.localizedDescription
			}
			isArchiving = false
		}
	}

	private func _isPlist(_ url: URL) -> Bool {
		LabFileFormat.isPlistFile(url)
	}

	private func _isDirectory(_ url: URL) -> Bool {
		var isDir: ObjCBool = false
		return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
	}

	/// Presents the editor sheet on a later tick. Tapping a context-menu item
	/// dismisses the menu in the same runloop; presenting a sheet that instant
	/// is silently swallowed by SwiftUI (the same class of bug the document
	/// picker below guards against). Nudging the presentation past the
	/// dismissal makes it reliable.
	private func _presentEditor(_ target: FileEditorTarget) {
		Task { @MainActor in
			try? await Task.sleep(nanoseconds: 500_000_000)
			if editorTarget == nil {
				editorTarget = target
			}
		}
	}

	private var _archivingOverlay: some View {
		ZStack {
			LabTheme.oledBlack.opacity(0.75).ignoresSafeArea()

			VStack(spacing: 14) {
				ProgressView()
					.tint(LabTheme.accent)
					.scaleEffect(1.15)

				Text("Working…")
					.font(.playfair(17, weight: .semiBold))
					.foregroundStyle(LabTheme.textPrimary)

				Text("Compressing or unarchiving")
					.font(.system(size: 12))
					.foregroundStyle(LabTheme.textTertiary)
			}
			.padding(28)
			.labCard()
		}
		.transition(.opacity)
	}

	private var _unpackingOverlay: some View {
		ZStack {
			LabTheme.oledBlack.opacity(0.75).ignoresSafeArea()

			VStack(spacing: 14) {
				ProgressView()
					.tint(LabTheme.accent)
					.scaleEffect(1.15)

				Text("Opening workspace…")
					.font(.playfair(17, weight: .semiBold))
					.foregroundStyle(LabTheme.textPrimary)

				Text("Unpacking the specimen")
					.font(.system(size: 12))
					.foregroundStyle(LabTheme.textTertiary)
			}
			.padding(28)
			.labCard()
		}
		.transition(.opacity)
	}

	private var _emptyState: some View {
		VStack(spacing: 14) {
			LabBeakerIcon(size: 88)
				.padding(.top, 10)

			Text(viewModel.isAtRoot ? "No specimens yet" : "This folder is empty")
				.font(.playfair(22, weight: .semiBold))
				.foregroundStyle(LabTheme.textPrimary)

			Text(viewModel.isAtRoot
				? "Import IPAs, dylibs or plists to begin the archive."
				: "Import files here or create a folder to keep the archive organized.")
				.font(.playfair(14, weight: .regular))
				.foregroundStyle(LabTheme.textTertiary)
				.multilineTextAlignment(.center)

			HStack(spacing: 12) {
				Button {
					isImporterPresented = true
				} label: {
					Label("Import", systemImage: "plus")
				}
				.buttonStyle(LabPrimaryButtonStyle())

				Button {
					newFolderName = ""
					isNewFolderPresented = true
				} label: {
					Label("New Folder", systemImage: "folder.badge.plus")
				}
				.buttonStyle(LabGhostButtonStyle())
			}
			.padding(.top, 8)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.padding(.horizontal, 30)
		.padding(.bottom, 60)
	}

	// MARK: - Helpers

	private var _visibleSections: [(kind: LabFile.Kind, files: [LabFile])] {
		let filtered = viewModel.specimensByKind.map { section -> (kind: LabFile.Kind, files: [LabFile]) in
			let searched = section.files.filter { file in
				searchText.isEmpty || file.name.localizedCaseInsensitiveContains(searchText)
			}
			return (section.kind, searched)
		}
		return filtered
			.filter { !$0.files.isEmpty }
			.filter { scope.matches($0.kind) }
	}

	private var _currentLocationLabel: String {
		viewModel.isAtRoot ? "the archive" : viewModel.currentDirectory.lastPathComponent
	}

	private func _appearDelay(for file: LabFile) -> Double {
		guard let index = viewModel.files.firstIndex(of: file) else { return 0 }
		return Double(index % 6) * 0.04
	}

	private func _folderAppearDelay(_ folder: LabFolder) -> Double {
		guard let index = viewModel.folders.firstIndex(of: folder) else { return 0 }
		return Double(index % 4) * 0.04
	}

	// MARK: - Types

	enum Scope: String, CaseIterable, Identifiable {
		case all, ipa, plist, dylib, other

		var id: String { rawValue }

		var label: String {
			switch self {
			case .all: return "All"
			case .ipa: return "IPAs"
			case .plist: return "Plists"
			case .dylib: return "Dylibs"
			case .other: return "Other"
			}
		}

		func matches(_ kind: LabFile.Kind) -> Bool {
			switch self {
			case .all: return true
			case .ipa: return kind == .ipa || kind == .tipa
			case .plist: return kind == .plist
			case .dylib: return kind == .dylib
			case .other: return ![.ipa, .tipa, .plist, .dylib].contains(kind)
			}
		}
	}

	struct PreviewTarget: Identifiable {
		let id = UUID()
		let url: URL
	}

	struct WorkspaceTarget: Identifiable {
		let id = UUID()
		let name: String
		let url: URL
	}
}

// MARK: - Editor / package result types

/// Which modular editor should open for a specimen card.
typealias FileEditorKind = LabEditorKind

/// Identifiable wrapper for the editor sheet presented from a long-press.
struct FileEditorTarget: Identifiable {
	let id = UUID()
	let url: URL
	let kind: FileEditorKind
	/// Bytes read at selection time — the editor uses these instead of
	/// re-reading the URL, so it provably opens what the user picked.
	let data: Data?
}

/// The IPA produced by packaging an `.app` folder, waiting for the
/// “Package Ready” alert.
private struct PackageResult {
	let url: URL
	let name: String
}

// MARK: - Rename / Move helpers

/// A file or folder waiting to be renamed.
enum RenameTarget: Identifiable {
	case file(LabFile)
	case folder(LabFolder)

	var id: String {
		switch self {
		case .file(let file): return file.id
		case .folder(let folder): return folder.id
		}
	}

	var kindLabel: String {
		switch self {
		case .file: return "specimen"
		case .folder: return "folder"
		}
	}
}

/// A file or folder waiting to be moved.
enum MoveItem: Identifiable {
	case file(LabFile)
	case folder(LabFolder)

	var id: String {
		switch self {
		case .file(let file): return file.id
		case .folder(let folder): return folder.id
		}
	}

	var name: String {
		switch self {
		case .file(let file): return file.name
		case .folder(let folder): return folder.name
		}
	}

	/// Paths the move picker must not offer. For folders this hides the
	/// folder itself — the archive walk skips its subtree automatically.
	var excludedPaths: Set<String> {
		switch self {
		case .file: return []
		case .folder(let folder): return [folder.url.path]
		}
	}
}

/// Folder picker presented when moving a specimen or folder.
private struct LabMoveSheet: View {
	let itemName: String
	let destinations: [(folder: LabFolder, depth: Int)]
	let onSelect: (URL) -> Void

	@Environment(\.dismiss) private var dismiss

	var body: some View {
		ZStack {
			LabTheme.oledBlack.ignoresSafeArea()

			VStack(spacing: 0) {
				HStack(spacing: 10) {
					Text("Move")
						.font(.playfair(22, weight: .bold))
						.foregroundStyle(LabTheme.textPrimary)

					Text(itemName)
						.font(.playfair(17, weight: .semiBold))
						.foregroundStyle(LabTheme.textTertiary)
						.lineLimit(1)

					Spacer()

					Button("Cancel") {
						dismiss()
					}
					.font(.system(size: 15, weight: .semibold))
					.foregroundStyle(LabTheme.accent)
				}
				.padding(.horizontal, LabTheme.pagePadding)
				.padding(.top, 18)
				.padding(.bottom, 10)

				ScrollView {
					LazyVStack(spacing: 6) {
						Button {
							onSelect(LabFileStore.workspaceDirectory)
							dismiss()
						} label: {
							_row(name: "Archive Root", depth: 0, count: nil)
						}
						.buttonStyle(.plain)

						ForEach(Array(destinations.enumerated()), id: \.element.folder.id) { _, dest in
							Button {
								onSelect(dest.folder.url)
								dismiss()
							} label: {
								_row(name: dest.folder.name, depth: dest.depth + 1, count: dest.folder.itemCount)
							}
							.buttonStyle(.plain)
						}
					}
					.padding(.horizontal, LabTheme.pagePadding)
					.padding(.bottom, 24)
				}
			}
		}
		.presentationDetents([.medium, .large])
		.presentationDragIndicator(.visible)
	}

	private func _row(name: String, depth: Int, count: Int?) -> some View {
		HStack(spacing: 10) {
			Image(systemName: "folder.fill")
				.font(.system(size: 14, weight: .medium))
				.foregroundStyle(LabTheme.neon.opacity(0.85))
				.frame(width: 20)
				.padding(.leading, CGFloat(depth) * 14)

			Text(name)
				.font(.system(size: 15, weight: .medium))
				.foregroundStyle(LabTheme.textPrimary)
				.lineLimit(1)

			Spacer()

			if let count {
				Text("\(count)")
					.font(.system(size: 11, weight: .semibold))
					.foregroundStyle(LabTheme.textTertiary)
			}
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 11)
		.background(
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.fill(LabTheme.surfaceSecondary)
		)
	}
}

extension Notification.Name {
	static let filesDidChange = Notification.Name("TheLab.filesDidChange")
}
