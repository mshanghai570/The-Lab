//
//  IPAWorkspace.swift
//  The Lab
//
//  Created by Michael Shingara on 8/2/26.
//

import Foundation
import Zip

/// The live IPA workspace.
///
/// Opening a specimen unpacks it into a private directory under
/// `Documents/Files/.workspace`. Every future edit (Info.plist, entitlements,
/// hex, icon swaps...) will mutate that directory in place, and repackaging
/// zips it back into a fresh unsigned IPA. This is the foundation the modular
/// editors will build on — nothing re-unzips/re-zips the whole package to
/// make a single change.
enum IPAWorkspace {
	/// Unpacks an IPA into a fresh workspace directory and returns it.
	static func open(_ ipa: URL) async throws -> URL {
		let fm = FileManager.default
		let stub = ipa.deletingPathExtension().lastPathComponent
		let workspace = LabFileStore.workspacesRoot
			.appendingPathComponent("\(stub) \(Int(Date().timeIntervalSince1970))", isDirectory: true)
		try fm.createDirectoryIfNeeded(at: workspace)
		print("[LabFileLoader] workspace created at: \(workspace.path)")

		Zip.addCustomFileExtension("ipa")
		try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
			DispatchQueue.global(qos: .userInitiated).async {
				do {
					try Zip.unzipFile(ipa, destination: workspace, overwrite: true, password: nil, progress: nil)
					cont.resume()
				} catch {
					cont.resume(throwing: error)
				}
			}
		}
		let extractedCount = (try? fm.contentsOfDirectory(at: workspace, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))?.count ?? -1
		print("[LabFileLoader] extraction complete — \(extractedCount) top-level entries in \(workspace.path)")
		return workspace
	}

	/// Rezips the workspace's `Payload` back into a fresh, unsigned IPA
	/// placed next to the workspace.
	///
	/// - Parameter progress: Called with 0...1 while zipping. Invoked on a
	///   background queue — hop to the main actor before touching UI state.
	static func repackage(_ workspace: URL, progress: ((Double) -> Void)? = nil) async throws -> URL {
		let fm = FileManager.default
		let payload = workspace.appendingPathComponent("Payload", isDirectory: true)
		guard fm.fileExists(atPath: payload.path) else {
			throw WorkspaceError.payloadMissing
		}

		let zipPath = workspace.appendingPathComponent("Repackaged.zip")
		let output = workspace.appendingPathComponent("Repackaged.ipa")
		try? fm.removeItem(at: zipPath)
		try? fm.removeItem(at: output)

		try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
			DispatchQueue.global(qos: .userInitiated).async {
				do {
					try Zip.zipFiles(
						paths: [payload],
						zipFilePath: zipPath,
						password: nil,
						compression: .BestSpeed,
						progress: progress
					)
					cont.resume()
				} catch {
					cont.resume(throwing: error)
				}
			}
		}
		try fm.moveItem(at: zipPath, to: output)
		return output
	}

	enum WorkspaceError: LocalizedError {
		case payloadMissing
		case notAppBundle

		var errorDescription: String? {
			switch self {
			case .payloadMissing: return "This package does not contain a Payload folder."
			case .notAppBundle: return "This folder is not an .app bundle."
			}
		}
	}

	// MARK: - Workspace tree

	/// Packages a loose `.app` bundle (e.g. `Payload/Foo.app` from an unarchived
	/// IPA) back into a fresh unsigned IPA saved into the archive root. The
	/// bundle is staged under a temporary `Payload/` folder, zipped, and the
	/// finished IPA is moved next to the other archive specimens.
	static func packageAppBundle(_ app: URL) async throws -> URL {
		let fm = FileManager.default
		guard app.pathExtension == "app" else {
			throw WorkspaceError.notAppBundle
		}

		let staging = LabFileStore.workspacesRoot
			.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
		defer { try? fm.removeItem(at: staging) }

		let payload = staging.appendingPathComponent("Payload", isDirectory: true)
		try fm.createDirectoryIfNeeded(at: payload)
		try fm.copyItem(at: app, to: payload.appendingPathComponent(app.lastPathComponent))

		let repackaged = try await repackage(staging)
		// repackage() leaves the IPA inside the staging folder; move it into the
		// archive root before the staging folder is cleaned up.
		let base = app.deletingPathExtension().lastPathComponent
		var destination = LabFileStore.workspaceDirectory.appendingPathComponent("\(base).ipa")
		var counter = 1
		while fm.fileExists(atPath: destination.path) {
			destination = LabFileStore.workspaceDirectory
				.appendingPathComponent("\(base) \(counter).ipa")
			counter += 1
		}
		try fm.moveItem(at: repackaged, to: destination)
		return destination
	}

	/// A lightweight snapshot of the unpacked package for browsing.
	struct Entry: Identifiable {
		let url: URL
		let name: String
		let isDirectory: Bool
		let size: Int64
		var children: [Entry] = []

		var id: String { url.path }

		var displaySize: String {
			isDirectory ? "" : ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
		}
	}

	/// Builds a nested tree rooted at the workspace directory.
	static func tree(from root: URL) -> Entry {
		func walk(_ dir: URL) -> [Entry] {
			let fm = FileManager.default
			let contents = ((try? fm.contentsOfDirectory(
				at: dir,
				includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
				options: [.skipsHiddenFiles]
			)) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }

			return contents.map { url in
				let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
				// resourceValues(.isDirectoryKey) is flaky on some iOS versions and
				// can report nil for real directories — trust the file system's
				// own answer when the two disagree. Treating a folder as a file is
				// what made editors try to read Payload/ as a plist.
				var isDir = values?.isDirectory == true
				var isDirFlag: ObjCBool = false
				if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirFlag) {
					let fsSaysDir = isDirFlag.boolValue
					if isDir != fsSaysDir {
						print("[LabFileLoader] tree isDirectory mismatch \(url.path): resourceValues=\(isDir) fileManager=\(fsSaysDir) — trusting the file system")
					}
					isDir = isDir || fsSaysDir
				}
				var entry = Entry(
					url: url,
					name: url.lastPathComponent,
					isDirectory: isDir,
					size: Int64(values?.fileSize ?? 0)
				)
				if isDir { entry.children = walk(url) }
				return entry
			}
		}

		return Entry(
			url: root,
			name: root.lastPathComponent,
			isDirectory: true,
			size: 0,
			children: walk(root)
		)
	}

	/// Counts files and totals their size under the tree — used for the
	/// workspace summary without walking the file system twice.
	static func summary(from root: Entry) -> (fileCount: Int, totalSize: Int64) {
		var files = 0
		var size: Int64 = 0
		func walk(_ entry: Entry) {
			if entry.isDirectory {
				for child in entry.children { walk(child) }
			} else {
				files += 1
				size += entry.size
			}
		}
		walk(root)
		return (files, size)
	}
}
