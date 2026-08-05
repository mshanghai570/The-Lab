//
//  FilesViewModel.swift
//  The Lab
//
//  Created by Michael Shingara on 8/2/26.
//

import SwiftUI

/// Drives the Files workspace: browses the archive as folders, imports
/// specimens, and handles the archive operations (create folder, rename,
/// move, delete).
///
/// The archive is a plain directory tree under `Documents/Files`; this
/// view model is the workspace layer that navigates it. The unpacked IPA
/// workspaces under `Documents/Files/.workspace` stay hidden and untouched.
@MainActor
final class FilesViewModel: ObservableObject {
	/// Directory stack — the last entry is the directory being browsed.
	@Published private(set) var path: [URL] = [LabFileStore.workspaceDirectory]
	/// Files inside `currentDirectory`.
	@Published private(set) var files: [LabFile] = []
	/// Folders inside `currentDirectory`.
	@Published private(set) var folders: [LabFolder] = []

	var currentDirectory: URL { path.last ?? LabFileStore.workspaceDirectory }
	var isAtRoot: Bool { path.count == 1 }
	var breadcrumbs: [URL] { path }

	/// Sections ordered by importance — IPAs first, everything else after.
	var specimensByKind: [(kind: LabFile.Kind, files: [LabFile])] {
		let order: [LabFile.Kind] = [.ipa, .tipa, .archive, .plist, .dylib, .deb, .json, .image, .text, .other]
		return order.compactMap { kind in
			let matches = files.filter { $0.kind == kind }
			return matches.isEmpty ? nil : (kind, matches)
		}
	}

	var totalSpecimens: Int { files.count }

	// MARK: - Navigation

	func enter(_ folder: LabFolder) {
		path.append(folder.url)
		refresh()
	}

	func goBack() {
		guard path.count > 1 else { return }
		path.removeLast()
		refresh()
	}

	func goToRoot() {
		guard !isAtRoot else { return }
		path = [LabFileStore.workspaceDirectory]
		refresh()
	}

	/// Truncates the path stack to `index + 1` entries (breadcrumb taps).
	func goTo(index: Int) {
		guard index >= 0, index < path.count else { return }
		path = Array(path.prefix(index + 1))
		refresh()
	}

	// MARK: - Scanning

	func refresh() {
		let fm = FileManager.default
		let contents = (try? fm.contentsOfDirectory(
			at: currentDirectory,
			includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
			options: [.skipsHiddenFiles]
		)) ?? []

		var dirs: [LabFolder] = []
		var items: [LabFile] = []

		for url in contents {
			guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey]) else { continue }
			// resourceValues(.isDirectoryKey) can be flaky on iOS; the file
			// system's own answer is authoritative.
			var isDirFlag: ObjCBool = false
			let fsSaysDir = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirFlag) && isDirFlag.boolValue
			if values.isDirectory == true || fsSaysDir {
				let children = (try? fm.contentsOfDirectory(
					at: url,
					includingPropertiesForKeys: [],
					options: [.skipsHiddenFiles]
				))?.count ?? 0
				dirs.append(LabFolder(
					url: url,
					itemCount: children,
					modified: values.contentModificationDate ?? .distantPast
				))
			} else {
				items.append(LabFile(url: url))
			}
		}

		folders = dirs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
		files = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
	}

	// MARK: - Import

	/// Outcome of an import pass, used to surface feedback in the UI.
	struct ImportResult {
		var imported: [URL] = []
		/// Items that already existed in the archive, paired with the
		/// destination that was already there — still openable.
		var skipped: [(name: String, destination: URL)] = []
		var failed: [String] = []

		/// Everything that ended up (or already was) in the archive, in import
		/// order.
		var openable: [URL] {
			imported + skipped.map(\.destination)
		}

		/// First openable package, so the UI can offer to open it.
		var firstPackage: URL? {
			openable.first {
				let ext = $0.pathExtension.lowercased()
				return ext == "ipa" || ext == "tipa"
			}
		}

		var summary: String {
			var lines: [String] = []
			if !imported.isEmpty {
				lines.append("Imported \(imported.count) file\(imported.count == 1 ? "" : "s").")
			}
			if !skipped.isEmpty {
				lines.append("Already in the archive: \(skipped.map(\.name).joined(separator: ", "))")
			}
			if !failed.isEmpty {
				lines.append("Couldn't import \(failed.count):")
				lines.append(contentsOf: failed.map { "• \($0)" })
			}
			if lines.isEmpty {
				lines.append("Nothing to import.")
			}
			return lines.joined(separator: "\n")
		}
	}

	func importFiles(from urls: [URL]) -> ImportResult {
		let fm = FileManager.default
		var result = ImportResult()
		for url in urls {
			let didAccess = url.startAccessingSecurityScopedResource()
			defer {
				if didAccess { url.stopAccessingSecurityScopedResource() }
			}

			let destination = currentDirectory.appendingPathComponent(url.lastPathComponent)
			guard !fm.fileExists(atPath: destination.path) else {
				result.skipped.append((name: url.lastPathComponent, destination: destination))
				continue
			}

			do {
				try fm.copyItem(at: url, to: destination)
				result.imported.append(destination)
			} catch {
				// Providers like iCloud can reject a direct copy of a file that
				// hasn't been materialized locally yet; reading the data triggers
				// download and is more forgiving.
				do {
					let data = try Data(contentsOf: url)
					try data.write(to: destination, options: .atomic)
					result.imported.append(destination)
				} catch {
					result.failed.append("\(url.lastPathComponent) (\(error.localizedDescription))")
				}
			}
		}
		refresh()
		postChange()
		return result
	}

	// MARK: - Create / Rename / Delete

	/// Creates a folder inside the directory being browsed.
	/// Returns a user-facing error message, or `nil` on success.
	func createFolder(named rawName: String) -> String? {
		let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !name.isEmpty else { return "Enter a folder name." }
		guard !name.contains("/") else { return "Folder names can't contain \"/\"." }

		let url = currentDirectory.appendingPathComponent(name, isDirectory: true)
		guard !FileManager.default.fileExists(atPath: url.path) else {
			return "A folder named \"\(name)\" already exists here."
		}

		do {
			try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
			refresh()
			postChange()
			return nil
		} catch {
			return error.localizedDescription
		}
	}

	func rename(_ file: LabFile, to newName: String) {
		let cleaned = newName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !cleaned.isEmpty, cleaned != file.name else { return }
		let destination = file.url.deletingLastPathComponent().appendingPathComponent(cleaned)
		guard !FileManager.default.fileExists(atPath: destination.path) else { return }
		try? FileManager.default.moveItem(at: file.url, to: destination)
		refresh()
		postChange()
	}

	func rename(_ folder: LabFolder, to newName: String) {
		let cleaned = newName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !cleaned.isEmpty, cleaned != folder.name else { return }
		let destination = folder.url.deletingLastPathComponent().appendingPathComponent(cleaned)
		guard !FileManager.default.fileExists(atPath: destination.path) else { return }
		try? FileManager.default.moveItem(at: folder.url, to: destination)
		refresh()
		postChange()
	}

	func delete(_ file: LabFile) {
		try? FileManager.default.removeItem(at: file.url)
		refresh()
		postChange()
	}

	/// Removes the folder and everything inside it.
	func delete(_ folder: LabFolder) {
		try? FileManager.default.removeItem(at: folder.url)
		refresh()
		postChange()
	}

	// MARK: - Move

	func move(_ file: LabFile, to destination: URL) {
		_moveItem(at: file.url, to: destination)
	}

	func move(_ folder: LabFolder, to destination: URL) {
		_moveItem(at: folder.url, to: destination)
	}

	private func _moveItem(at url: URL, to destination: URL) {
		let fm = FileManager.default
		let parent = url.deletingLastPathComponent()

		guard destination != parent else { return }						// already there
		guard !destination.path.hasPrefix(url.path + "/") else { return }	// into itself / its own subtree

		let target = destination.appendingPathComponent(url.lastPathComponent)
		guard !fm.fileExists(atPath: target.path) else { return }
		guard (try? fm.moveItem(at: url, to: target)) != nil else { return }

		refresh()
		postChange()
	}

	/// All folders in the archive for the move picker, excluding the folder
	/// being moved (its subtree is skipped automatically by the walk).
	func folderDestinations(excluding excludedPaths: Set<String>) -> [(folder: LabFolder, depth: Int)] {
		LabFileStore.allFolders(excluding: excludedPaths)
	}

	// MARK: - Notification

	private func postChange() {
		NotificationCenter.default.post(name: .filesDidChange, object: nil)
	}
}
