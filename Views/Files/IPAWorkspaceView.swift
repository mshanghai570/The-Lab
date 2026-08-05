//
//  IPAWorkspaceView.swift
//  The Lab
//
//  Created by Michael Shingara on 8/2/26.
//

import SwiftUI
import NimbleExtensions

/// The live workspace for an opened specimen.
///
/// Shows the unpacked package as a browsable tree, lets you preview any file
/// with Quick Look, and repackages the whole workspace into a fresh unsigned
/// IPA when you're done editing. This is where The Lab's modular editors
/// (Info.plist, entitlements, hex...) will plug in later.
struct IPAWorkspaceView: View {
	let sourceName: String
	let workspace: URL

	@Environment(\.dismiss) private var dismiss

	@State private var tree: IPAWorkspace.Entry?
	@State private var expanded: Set<String> = []
	@State private var previewURL: IdentifiableURL?
	@State private var editorTarget: EditorTarget?
	@State private var readyPackage: IdentifiableURL?
	@State private var isRepackaging = false
	@State private var repackageProgress: Double?
	@State private var errorMessage: String?
	@State private var libraryError: String?
	@State private var editorError: String?
	@State private var isDeleteConfirmPresented = false

	private var summary: (fileCount: Int, totalSize: Int64) {
		guard let tree else { return (0, 0) }
		return IPAWorkspace.summary(from: tree)
	}

	var body: some View {
		NavigationStack {
			ZStack {
				LabTheme.oledBlack.ignoresSafeArea()

				VStack(spacing: 0) {
					_header
					_stats
						.padding(.top, 14)

					if isRepackaging {
						ProgressView(value: repackageProgress ?? 0, total: 1)
							.progressViewStyle(.linear)
							.tint(LabTheme.accent)
							.padding(.horizontal, LabTheme.pagePadding)
							.padding(.top, 16)
							.transition(.opacity)
					}

					_treeList
						.padding(.top, 16)

					_actionBar
				}
			}
			.navigationTitle("Workspace")
			.navigationBarTitleDisplayMode(.inline)
			.toolbarBackground(LabTheme.surfacePrimary, for: .navigationBar)
			.toolbarBackground(.visible, for: .navigationBar)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						dismiss()
					} label: {
						Text("Close")
					}
				}
			}
			.sheet(item: $previewURL) { target in
				QuickLookPreview(url: target.url)
					.ignoresSafeArea()
			}
			.sheet(item: $editorTarget, onDismiss: _refreshTree) { target in
				switch target.kind {
				case .text:
					LabTextEditorView(url: target.url, preloadedData: target.data) { editorTarget = EditorTarget(url: target.url, kind: $0, data: target.data) }
				case .plist:
					LabPlistEditorView(url: target.url, preloadedData: target.data) { editorTarget = EditorTarget(url: target.url, kind: $0, data: target.data) }
				case .hex:
					LabHexEditorView(url: target.url, preloadedData: target.data)
				}
			}
			.sheet(item: $readyPackage) { target in
				_packageReadyView(target.url)
			}
			.alert("Couldn't Repackage", isPresented: Binding(
				get: { errorMessage != nil },
				set: { if !$0 { errorMessage = nil } }
			)) {
				Button("OK", role: .cancel) { errorMessage = nil }
			} message: {
				Text(errorMessage ?? "")
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
			.alert("Delete Workspace", isPresented: $isDeleteConfirmPresented) {
				Button("Cancel", role: .cancel) {}
				Button("Delete", role: .destructive) {
					_deleteWorkspace()
				}
			} message: {
				Text("This removes the unpacked package and any edits made inside it. The original specimen is untouched.")
			}
		}
		.onAppear {
			tree = IPAWorkspace.tree(from: workspace)
		}
	}

	// MARK: - Header

	private var _header: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 10) {
				Text(sourceName)
					.font(.playfair(24, weight: .semiBold))
					.foregroundStyle(LabTheme.textPrimary)
					.lineLimit(1)

				Text("LIVE WORKSPACE")
					.font(.system(size: 9, weight: .bold))
					.kerning(1.2)
					.foregroundStyle(LabTheme.neon)
					.padding(.horizontal, 8)
					.padding(.vertical, 4)
					.overlay(
						Capsule().stroke(LabTheme.neon.opacity(0.5), lineWidth: 1)
					)
					.labGlow(LabTheme.neon, radius: 8, opacity: 0.25)
			}

			Text(workspace.path)
				.font(.system(size: 11, design: .monospaced))
				.foregroundStyle(LabTheme.textTertiary)
				.lineLimit(1)
				.truncationMode(.middle)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.horizontal, LabTheme.pagePadding)
		.padding(.top, 8)
	}

	private var _stats: some View {
		HStack(spacing: 8) {
			_stat("\(summary.fileCount)", "FILES")
			_stat(summary.totalSize.formatted(.byteCount(style: .file)), "SIZE")
			_stat("Unsigned", "OUTPUT")
			Spacer(minLength: 0)
		}
		.padding(.horizontal, LabTheme.pagePadding)
	}

	private func _stat(_ value: String, _ label: String) -> some View {
		VStack(spacing: 2) {
			Text(value)
				.font(.system(size: 13, weight: .semibold))
				.foregroundStyle(LabTheme.textPrimary)
			Text(label)
				.font(.system(size: 9, weight: .bold))
				.kerning(1)
				.foregroundStyle(LabTheme.textTertiary)
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 8)
		.background(Capsule().fill(LabTheme.surfaceSecondary))
		.overlay(Capsule().stroke(LabTheme.hairline, lineWidth: 1))
	}

	// MARK: - Tree

	private var _treeList: some View {
		ScrollView {
			LazyVStack(alignment: .leading, spacing: 2) {
				if let tree {
					ForEach(tree.children) { entry in
						WorkspaceRow(entry: entry, depth: 0, expanded: $expanded, onPreview: {
							previewURL = IdentifiableURL(url: $0)
						}) { action, rowEntry in
							// The row passes its OWN entry — never a captured ancestor — so
							// nested files resolve to themselves, not the container
							// directory that used to swallow editor taps.
							_handleMenuAction(action, for: rowEntry)
						}
					}
				} else {
					ProgressView()
						.tint(LabTheme.accent)
						.frame(maxWidth: .infinity)
						.padding(.top, 60)
				}
			}
			.padding(.horizontal, LabTheme.pagePadding)
			.padding(.bottom, 16)
		}
	}

	private func _icon(for entry: IPAWorkspace.Entry) -> String {
		if !entry.isDirectory {
			return LabFile.Kind.classify(entry.url).systemImage
		}
		return entry.name.hasSuffix(".app") ? "app.fill" : "folder.fill"
	}

	private func _iconColor(for entry: IPAWorkspace.Entry) -> Color {
		if !entry.isDirectory {
			return LabFile.Kind.classify(entry.url).accent
		}
		return entry.name.hasSuffix(".app") ? LabTheme.accent : LabTheme.neon.opacity(0.85)
	}

	// MARK: - Row menu

	private func _handleMenuAction(_ action: WorkspaceRow.MenuAction, for entry: IPAWorkspace.Entry) {
		switch action {
		case .preview:
			previewURL = IdentifiableURL(url: entry.url)
		case .text, .plist, .hex:
			let url = entry.url
			print("[Editors] \(action) editor requested — \(url.lastPathComponent)")
			print("[Editors] Selected URL: \(url.path)")
			var isDir: ObjCBool = false
			let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
			print("[Editors] Exists: \(exists) — Is directory: \(isDir.boolValue) (tree says: \(entry.isDirectory ? "directory" : "file"))")
			// Editors must only ever receive file URLs. Reject directories at
			// launch time with a live file-system check, even if the tree
			// snapshot misclassified the row (that's what sent Payload/ to
			// the editors before).
			guard _guardFile(url, treeIsDirectory: entry.isDirectory) else {
				print("[Editors] Validation REJECTED — this is a directory, not a file")
				editorError = "\(entry.name) is a folder — tap it to open it, then pick a file inside to edit."
				return
			}
			print("[Editors] Passing validation — reading bytes")
			let outcome = LabFileLoader.probe(url)
			let kind: EditorKind
			switch action {
			case .text:
				// Binary plists (bplist00) can't be read as UTF-8 — route them
				// to the Plist Editor, which reads both binary and XML.
				kind = outcome.data?.starts(with: LabFileFormat.bplistHeader) == true ? .plist : .text
			case .plist:
				kind = .plist
			default:
				kind = .hex
			}
			print("[Editors] Presenting \(kind) editor for \(url.lastPathComponent)")
			_presentEditor(EditorTarget(url: url, kind: kind, data: outcome.data))
		case .share:
			UIActivityViewController.show(activityItems: [entry.url])
		case .packageIPA:
			Task { await _repackage() }
		}
	}

	/// Live file-system guard: editors can't open directories. Logs a
	/// mismatch between the tree's classification and reality when they
	/// disagree — that's the exact failure mode that sent Payload/ to the
	/// editors before.
	private func _guardFile(_ url: URL, treeIsDirectory: Bool) -> Bool {
		var isDir: ObjCBool = false
		let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
		let liveIsDir = exists && isDir.boolValue
		if liveIsDir != treeIsDirectory {
			print("[LabFileLoader] row model mismatch: tree=\(treeIsDirectory ? "directory" : "file") live=\(liveIsDir ? "directory" : "file") — \(url.path)")
		}
		if liveIsDir {
			print("[LabFileLoader] cannot edit directory: \(url.path)")
			return false
		}
		return true
	}

	/// Presents the editor sheet on a later tick. Tapping a context-menu item
	/// dismisses the menu in the same runloop; presenting a sheet that instant
	/// is silently swallowed by SwiftUI (the same class of bug FilesView's
	/// document picker guards against). Nudging the presentation past the
	/// dismissal makes it reliable.
	private func _presentEditor(_ target: EditorTarget) {
		Task { @MainActor in
			try? await Task.sleep(nanoseconds: 500_000_000)
			if editorTarget == nil {
				editorTarget = target
			}
		}
	}

	private func _refreshTree() {
		tree = IPAWorkspace.tree(from: workspace)
	}

	// MARK: - Actions

	private var _actionBar: some View {
		HStack(spacing: 12) {
			Button {
				isDeleteConfirmPresented = true
			} label: {
				Label("Delete", systemImage: "trash")
			}
			.buttonStyle(LabGhostButtonStyle())
			.disabled(isRepackaging)

			Button {
				Task { await _repackage() }
			} label: {
				Group {
					if isRepackaging {
						ProgressView()
							.tint(LabTheme.oledBlack)
					} else {
						Label("Repackage IPA", systemImage: "shippingbox.and.arrow.backward")
					}
				}
			}
			.buttonStyle(LabPrimaryButtonStyle())
			.disabled(isRepackaging)
		}
		.padding(.horizontal, LabTheme.pagePadding)
		.padding(.top, 10)
		.padding(.bottom, 6)
		.background(
			LinearGradient(
				colors: [LabTheme.oledBlack.opacity(0), LabTheme.oledBlack.opacity(0.9)],
				startPoint: .top,
				endPoint: .bottom
			)
			.ignoresSafeArea(edges: .bottom)
		)
	}

	private func _repackage() async {
		guard !isRepackaging else { return }
		isRepackaging = true
		repackageProgress = 0
		defer { isRepackaging = false }

		do {
			let output = try await IPAWorkspace.repackage(workspace) { [self] progress in
				Task { @MainActor in
					self.repackageProgress = progress
				}
			}
			// Refresh the tree so the fresh package shows up in the listing.
			tree = IPAWorkspace.tree(from: workspace)
			readyPackage = IdentifiableURL(url: output)
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	private func _deleteWorkspace() {
		try? FileManager.default.removeItem(at: workspace)
		dismiss()
	}

	// MARK: - Package ready

	private func _packageReadyView(_ url: URL) -> some View {
		ZStack {
			LabTheme.oledBlack.ignoresSafeArea()

			VStack(spacing: 16) {
				ZStack {
					Circle()
						.fill(LabTheme.neon.opacity(0.12))
						.frame(width: 72, height: 72)
					Image(systemName: "checkmark")
						.font(.system(size: 26, weight: .bold))
						.foregroundStyle(LabTheme.neon)
				}
				.labGlow(LabTheme.neon, radius: 18, opacity: 0.3)

				Text("Package Ready")
					.font(.playfair(24, weight: .semiBold))
					.foregroundStyle(LabTheme.textPrimary)

				Text(url.lastPathComponent)
					.font(.system(size: 12, design: .monospaced))
					.foregroundStyle(LabTheme.textTertiary)
					.lineLimit(1)
					.truncationMode(.middle)

				Text("A fresh unsigned IPA. Sign it on-device with your certificate.")
					.font(.playfair(14, weight: .regular))
					.foregroundStyle(LabTheme.textSecondary)
					.multilineTextAlignment(.center)

				HStack(spacing: 12) {
					Button {
						_saveToArchive(url)
						readyPackage = nil
					} label: {
						Label("Save to Archive", systemImage: "tray.and.arrow.down")
					}
					.buttonStyle(LabGhostButtonStyle())

					Button {
						_addToLibrary(url)
					} label: {
						Label("Add to Library", systemImage: "books.vertical")
					}
					.buttonStyle(LabGhostButtonStyle())
				}

				HStack(spacing: 12) {
					Button("Done") {
						readyPackage = nil
					}
					.buttonStyle(LabGhostButtonStyle())

					Button {
						readyPackage = nil
						UIActivityViewController.show(activityItems: [url])
					} label: {
						Label("Share IPA", systemImage: "square.and.arrow.up")
					}
					.buttonStyle(LabPrimaryButtonStyle())
				}
				.padding(.top, 10)
			}
			.padding(32)
		}
	}
	/// Copies the freshly repackaged IPA into the archive root so it can be
	/// organized from the Files tab, then tells observers to re-scan.
	private func _saveToArchive(_ url: URL) {
		let fm = FileManager.default
		var destination = LabFileStore.workspaceDirectory.appendingPathComponent(url.lastPathComponent)

		var counter = 1
		while fm.fileExists(atPath: destination.path) {
			let stub = url.deletingPathExtension().lastPathComponent
			destination = LabFileStore.workspaceDirectory
				.appendingPathComponent("\(stub) \(counter).\(url.pathExtension)")
			counter += 1
		}

		try? fm.copyItem(at: url, to: destination)
		NotificationCenter.default.post(name: .filesDidChange, object: nil)
	}

	/// Imports the freshly repackaged IPA into the Library tab so it can be
	/// signed and installed like any other specimen.
	private func _addToLibrary(_ url: URL) {
		FR.handlePackageFile(url) { error in
			if let error {
				libraryError = error.localizedDescription
			} else {
				readyPackage = nil
			}
		}
	}
}

/// A single row in the workspace tree. Recursion flows through this named
/// type rather than a `some View` function, which keeps the opaque return
/// type well-founded.
private struct WorkspaceRow: View {
	enum MenuAction: Hashable {
		case preview
		case text
		case plist
		case hex
		case share
		case packageIPA
	}

	let entry: IPAWorkspace.Entry
	let depth: Int
	@Binding var expanded: Set<String>
	let onPreview: (URL) -> Void
	/// Takes the row's own entry so a nested row can never resolve to an
	/// ancestor (the bug that sent the `Payload` directory to the editors).
	let onMenu: (MenuAction, IPAWorkspace.Entry) -> Void

	/// Live file-system check — the tree snapshot can be built with a stale
	/// classification, so the row asks the file system directly before
	/// deciding icon, tap behavior, and which menu items to offer.
	private var isDirectory: Bool {
		var isDirFlag: ObjCBool = false
		return FileManager.default.fileExists(atPath: entry.url.path, isDirectory: &isDirFlag) && isDirFlag.boolValue
	}

	var body: some View {
		let isExpanded = expanded.contains(entry.id)
		let kind = LabFile.Kind.classify(entry.url)

		VStack(alignment: .leading, spacing: 2) {
			HStack(spacing: 10) {
				Image(systemName: isDirectory ? (isExpanded ? "chevron.down" : "chevron.right") : "circle.fill")
					.font(.system(size: isDirectory ? 11 : 5, weight: .semibold))
					.foregroundStyle(isDirectory ? LabTheme.textTertiary : kind.accent.opacity(0.8))
					.frame(width: 12)

				Image(systemName: _icon(for: entry))
					.font(.system(size: 13, weight: .medium))
					.foregroundStyle(_iconColor(for: entry))
					.frame(width: 22)

				Text(entry.name)
					.font(.system(size: 14, weight: entry.isDirectory ? .semibold : .regular))
					.foregroundStyle(entry.isDirectory ? LabTheme.textPrimary : LabTheme.textSecondary)
					.lineLimit(1)
					.truncationMode(.middle)

				Spacer(minLength: 8)

				if !isDirectory {
					Text(entry.displaySize)
						.font(.system(size: 11))
						.foregroundStyle(LabTheme.textTertiary)
				}
			}
			.padding(.vertical, 8)
			.padding(.horizontal, 10)
			.background(
				RoundedRectangle(cornerRadius: 12, style: .continuous)
					.fill(isExpanded ? LabTheme.surfaceSecondary.opacity(0.55) : .clear)
			)
			.contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
			.contextMenu { _contextMenu }
			.onTapGesture {
				if isDirectory {
					withAnimation(.snappy(duration: 0.22)) {
						if isExpanded {
							expanded.remove(entry.id)
						} else {
							expanded.insert(entry.id)
						}
					}
				} else {
					onPreview(entry.url)
				}
			}

			if isDirectory && isExpanded {
				ForEach(entry.children) { child in
					WorkspaceRow(entry: child, depth: depth + 1, expanded: $expanded, onPreview: onPreview, onMenu: onMenu)
						.padding(.leading, 14)
				}
			}
		}
	}

	@ViewBuilder
	private var _contextMenu: some View {
		if isDirectory {
			// Esign-style: an .app folder offers to package the workspace back
			// into a fresh IPA.
			if entry.name.hasSuffix(".app") {
				Button {
					onMenu(.packageIPA, entry)
				} label: {
					Label("Package IPA", systemImage: "shippingbox.and.arrow.backward")
				}
			}
		} else {
			Button {
				onMenu(.preview, entry)
			} label: {
				Label("Quick Look", systemImage: "eye")
			}

			Button {
				onMenu(.text, entry)
			} label: {
				Label("Text Editor", systemImage: "doc.plaintext")
			}

			if _isPlist(entry.url) {
				Button {
					onMenu(.plist, entry)
				} label: {
					Label("Plist Editor", systemImage: "list.bullet.rectangle.portrait")
				}
			}

			Button {
				onMenu(.hex, entry)
			} label: {
				Label("Hex Editor", systemImage: "number")
			}

			Divider()

			Button {
				onMenu(.share, entry)
			} label: {
				Label("Share", systemImage: "square.and.arrow.up")
			}
		}
	}

	private func _isPlist(_ url: URL) -> Bool {
		LabFileFormat.isPlistFile(url)
	}

	private func _icon(for entry: IPAWorkspace.Entry) -> String {
		if !entry.isDirectory {
			return LabFile.Kind.classify(entry.url).systemImage
		}
		return entry.name.hasSuffix(".app") ? "app.fill" : "folder.fill"
	}

	private func _iconColor(for entry: IPAWorkspace.Entry) -> Color {
		if !entry.isDirectory {
			return LabFile.Kind.classify(entry.url).accent
		}
		return entry.name.hasSuffix(".app") ? LabTheme.accent : LabTheme.neon.opacity(0.85)
	}
}

/// Small Identifiable wrapper so `URL` values can drive `.sheet(item:)`.
private struct IdentifiableURL: Identifiable {
	let id = UUID()
	let url: URL
}

/// Which modular editor should open for a workspace file.
typealias EditorKind = LabEditorKind

/// Identifiable wrapper for the editor sheet.
private struct EditorTarget: Identifiable {
	let id = UUID()
	let url: URL
	let kind: EditorKind
	/// Bytes read at selection time — the editor uses these instead of
	/// re-reading the URL, so it provably opens what the user picked.
	let data: Data?
}
