//
//  LabFile.swift
//  The Lab
//
//  Created by Michael Shingara on 8/2/26.
//

import SwiftUI

/// A specimen stored in The Lab's file workspace (`Documents/Files`).
///
/// IPAs are first-class here — they can be opened into a live workspace —
/// but dylibs, plists, archives and every other kind of file have a home
/// in the archive too.
struct LabFile: Identifiable, Hashable {
	enum Kind: String, CaseIterable, Identifiable {
		case ipa
		case tipa
		case archive
		case plist
		case dylib
		case deb
		case json
		case image
		case text
		case other

		var id: String { rawValue }

		var label: String {
			switch self {
			case .ipa: return "IPA Specimen"
			case .tipa: return "TIPA Specimen"
			case .archive: return "Archive"
			case .plist: return "Property List"
			case .dylib: return "Dylib"
			case .deb: return "Debian Package"
			case .json: return "JSON"
			case .image: return "Image"
			case .text: return "Text"
			case .other: return "Other"
			}
		}

		var systemImage: String {
			switch self {
			case .ipa, .tipa: return "shippingbox"
			case .archive: return "archivebox"
			case .plist: return "list.bullet.rectangle.portrait"
			case .dylib: return "puzzlepiece.extension"
			case .deb: return "shippingbox.fill"
			case .json: return "curlybraces"
			case .image: return "photo"
			case .text: return "doc.plaintext"
			case .other: return "doc"
			}
		}

		var accent: Color {
			switch self {
			case .ipa, .tipa: return LabTheme.accent
			case .archive: return Color(red: 0.72, green: 0.55, blue: 1.0)
			case .plist: return Color(red: 0.35, green: 0.75, blue: 1.0)
			case .dylib: return Color(red: 1.0, green: 0.72, blue: 0.3)
			case .deb: return LabTheme.neon
			case .json: return Color(red: 0.55, green: 1.0, blue: 0.85)
			case .image: return Color(red: 0.95, green: 0.45, blue: 0.6)
			case .text: return LabTheme.textSecondary
			case .other: return LabTheme.textTertiary
			}
		}

		static func classify(_ url: URL) -> Kind {
			switch url.pathExtension.lowercased() {
			case "ipa": return .ipa
			case "tipa": return .tipa
			case "zip", "7z", "rar", "tar", "gz", "xz", "bz2": return .archive
			case "plist", "mobileconfig", "entitlements": return .plist
			case "dylib": return .dylib
			case "deb": return .deb
			case "json": return .json
			case "png", "jpg", "jpeg", "gif", "webp", "heic", "svg": return .image
			case "txt", "log", "md", "strings", "xcconfig", "sh", "swift", "c", "h", "m", "mm", "xml", "html": return .text
			default: return .other
			}
		}
	}

	let url: URL
	let kind: Kind
	let size: Int64
	let modified: Date

	var name: String { url.lastPathComponent }
	var id: String { url.path }

	var sizeLabel: String {
		ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
	}

	var modifiedLabel: String {
		modified.formatted(date: .abbreviated, time: .shortened)
	}

	init(url: URL) {
		self.url = url
		self.kind = Kind.classify(url)
		let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
		self.size = Int64(values?.fileSize ?? 0)
		self.modified = values?.contentModificationDate ?? .distantPast
	}
}

/// A folder inside the archive.
///
/// Folders are a pure workspace layer — they live on the file system like
/// any other directory, so the whole archive stays browsable and movable.
struct LabFolder: Identifiable, Hashable {
	let url: URL
	/// Number of immediate children (files + folders) shown in the UI.
	let itemCount: Int
	let modified: Date

	var name: String { url.lastPathComponent }
	var id: String { url.path }

	var modifiedLabel: String {
		modified.formatted(date: .abbreviated, time: .shortened)
	}
}

/// File-system paths for The Lab's archive. Deliberately non-isolated so
/// any queue (e.g. the download session) can resolve them.
enum LabFileStore {
	/// Persistent workspace where downloads and imports land.
	static var workspaceDirectory: URL {
		let dir = URL.documentsDirectory.appendingPathComponent("Files", isDirectory: true)
		try? FileManager.default.createDirectoryIfNeeded(at: dir)
		return dir
	}

	/// Private root holding unpacked IPA workspaces. Never surfaced in the
	/// archive UI — hidden from listings by its dot prefix.
	static var workspacesRoot: URL {
		let dir = workspaceDirectory.appendingPathComponent(".workspace", isDirectory: true)
		try? FileManager.default.createDirectoryIfNeeded(at: dir)
		return dir
	}

	/// Walks the archive collecting every folder (excluding hidden paths),
	/// paired with its depth below the archive root. Used by the move picker.
	static func allFolders(
		excluding excludedPaths: Set<String> = []
	) -> [(folder: LabFolder, depth: Int)] {
		let fm = FileManager.default
		var result: [(LabFolder, Int)] = []

		func walk(_ dir: URL, depth: Int) {
			let contents = (try? fm.contentsOfDirectory(
				at: dir,
				includingPropertiesForKeys: [.isDirectoryKey],
				options: [.skipsHiddenFiles]
			)) ?? []
			for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
				// resourceValues(.isDirectoryKey) can be flaky on iOS; the file
				// system's own answer is authoritative.
				var isDirFlag: ObjCBool = false
				let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
					|| (FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirFlag) && isDirFlag.boolValue)
				guard isDir else { continue }
				guard !excludedPaths.contains(url.path) else { continue }

				let children = (try? fm.contentsOfDirectory(
					at: url,
					includingPropertiesForKeys: [],
					options: [.skipsHiddenFiles]
				))?.count ?? 0
				let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
				result.append((
					LabFolder(
						url: url,
						itemCount: children,
						modified: values?.contentModificationDate ?? .distantPast
					),
					depth
				))
				walk(url, depth: depth + 1)
			}
		}

		walk(workspaceDirectory, depth: 0)
		return result
	}
}

/// The modular in-place editors offered from the file context menus.
enum LabEditorKind: Hashable {
	case text
	case plist
	case hex
}

/// Sniffing helpers for choosing the right editor for a workspace file.
///
/// App bundles are full of plists that don't end in `.plist` — compiled
/// `.strings` files, `archived-expanded-entitlements.xcent`, provisioning
/// profiles — and plenty of them are stored as binary plists (`bplist00`),
/// which the text editor can't read as UTF-8. These helpers peek at the
/// magic header so the menus can route a file to an editor that can
/// actually open it.
enum LabFileFormat {
	/// "bplist00" — the magic header every binary property list starts with.
	static let bplistHeader = Data([0x62, 0x70, 0x6C, 0x69, 0x73, 0x74, 0x30, 0x30])

	/// Reads just the first eight bytes to decide whether a file is a binary
	/// property list, regardless of its extension.
	static func isBinaryPlist(_ url: URL) -> Bool {
		guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
		defer { try? handle.close() }
		guard let data = try? handle.read(upToCount: 8), data.count == 8 else { return false }
		return data == bplistHeader
	}

	/// A file is plist-editable when its extension says so, or when its
	/// contents are a binary plist (compiled .strings, extensionless plists…).
	static func isPlistFile(_ url: URL) -> Bool {
		let extensions = ["plist", "entitlements", "mobileconfig", "xml", "strings", "stringsdict", "xcent", "intentdefinition", "mobileprovision"]
		return extensions.contains(url.pathExtension.lowercased()) || isBinaryPlist(url)
	}
}

/// Reads a workspace file for one of The Lab's modular editors, capturing
/// forensics so a failure is provable instead of mysterious.
///
/// Every editor used to call `Data(contentsOf:)` directly and show a generic
/// "can't read" screen, which made it impossible to tell a missing file from a
/// permission error from a directory. This loader records whether the URL is a
/// file URL, whether it exists, is readable, is a directory, its size, its
/// full POSIX attributes, the first 16 bytes as hex (`bplist00` / `<?xml` /
/// Mach-O magic…), and — critically — the FULL `NSError` (domain, code,
/// localizedDescription and userInfo), prints it to the console, and returns
/// it for the failure UI. It defensively acquires security-scoped access
/// (some document-picker URLs require it), and falls back to `FileHandle` and
/// `contents(atPath:)` reads if the first attempt fails for a transient
/// reason.
enum LabFileLoader {
	/// Everything the forensic probe learns about one URL.
	struct Outcome {
		let url: URL
		let isFileURL: Bool
		let exists: Bool
		let isReadable: Bool
		let isDirectory: Bool
		let size: Int64
		let attributes: String
		let firstBytesHex: String
		let errorDomain: String?
		let errorCode: Int?
		let errorDescription: String?
		let errorUserInfo: String?
		let data: Data?

		/// Human-readable error summary, e.g.
		/// "NSCocoaErrorDomain 260 — The file couldn’t be opened because there is no such file."
		var errorSummary: String? {
			guard let errorDomain else { return nil }
			return "\(errorDomain) \(errorCode ?? -1) — \(errorDescription ?? "unknown error")"
		}
	}

	static func read(_ url: URL) -> Outcome {
		let scoped = url.startAccessingSecurityScopedResource()
		defer { if scoped { url.stopAccessingSecurityScopedResource() } }

		let fm = FileManager.default

		// --- Existence / directory / size / attributes -----------------------
		var isDir: ObjCBool = false
		let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir)
		let isDirectory = isDir.boolValue
		let isReadable = fm.isReadableFile(atPath: url.path)
		var size: Int64 = 0
		var attributes = "(none)"
		if exists, let attrs = try? fm.attributesOfItem(atPath: url.path) {
			size = Int64((attrs[.size] as? NSNumber)?.int64Value ?? 0)
			attributes = attrs
				.map { "\($0.key.rawValue)=\($0.value)" }
				.sorted()
				.joined(separator: " ")
		}

		// A directory can never be read as file bytes — report it clearly
		// instead of letting Data(contentsOf:) throw a confusing
		// "Is a directory" (EISDIR) error downstream.
		if isDirectory {
			let outcome = Outcome(
				url: url,
				isFileURL: url.isFileURL,
				exists: true,
				isReadable: isReadable,
				isDirectory: true,
				size: size,
				attributes: attributes,
				firstBytesHex: "(directory)",
				errorDomain: "LabDirectoryError",
				errorCode: 21, // EISDIR
				errorDescription: "This is a folder, not a file — editors can only open file contents.",
				errorUserInfo: "NSFilePath=\(url.path)",
				data: nil
			)
			print("[LabFileLoader] !!! DIRECTORY, not a file — \(url.path)")
			print("[LabFileLoader] \(summary(outcome).replacingOccurrences(of: "\n", with: " | "))")
			return outcome
		}

		// --- Read attempts ---------------------------------------------------
		var data: Data?
		var errorDomain: String?
		var errorCode: Int?
		var errorDescription: String?
		var errorUserInfo: String?
		var readSource = "Data(contentsOf:)"

		do {
			data = try Data(contentsOf: url)
		} catch {
			let ns = error as NSError
			errorDomain = ns.domain
			errorCode = ns.code
			errorDescription = ns.localizedDescription
			errorUserInfo = ns.userInfo
				.map { "\($0.key)=\($0.value)" }
				.sorted()
				.joined(separator: " ")

			// Second opinion: FileHandle shares the same underlying open but has
			// a slightly different error surface; log whichever fails.
			if let handle = try? FileHandle(forReadingFrom: url) {
				defer { try? handle.close() }
				if let probe = try? handle.readToEnd(), !probe.isEmpty {
					data = probe
					readSource = "FileHandle"
					errorDomain = nil; errorCode = nil; errorDescription = nil; errorUserInfo = nil
				}
			}

			// Third opinion: the path-based reader.
			if data == nil, let probe = fm.contents(atPath: url.path), !probe.isEmpty {
				data = probe
				readSource = "contents(atPath:)"
				errorDomain = nil; errorCode = nil; errorDescription = nil; errorUserInfo = nil
			}
		}

		let hex = data.map {
			$0.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
		} ?? (exists ? "(read failed)" : "(missing)")

		let outcome = Outcome(
			url: url,
			isFileURL: url.isFileURL,
			exists: exists,
			isReadable: isReadable,
			isDirectory: isDirectory,
			size: size,
			attributes: attributes,
			firstBytesHex: hex,
			errorDomain: errorDomain,
			errorCode: errorCode,
			errorDescription: errorDescription,
			errorUserInfo: errorUserInfo,
			data: data
		)

		print("[LabFileLoader] read via \(readSource) | \(summary(outcome).replacingOccurrences(of: "\n", with: " | "))")
		return outcome
	}

	/// Selection-site probe: logs that the user picked this exact URL and
	/// whether it's readable right now. The caller passes the returned data
	/// into the editor so the editor provably reads what was selected — never
	/// a re-read of a URL that may have gone stale between selection and the
	/// sheet appearing.
	static func probe(_ url: URL) -> Outcome {
		print("[LabFileLoader] ===== selection probe: \(url.path)")
		return read(url)
	}

	/// Outcome for bytes already read at selection time — lets an editor skip
	/// re-reading the URL entirely and open the exact data the user picked.
	static func from(preloaded data: Data, url: URL) -> Outcome {
		Outcome(
			url: url,
			isFileURL: url.isFileURL,
			exists: true,
			isReadable: true,
			isDirectory: false,
			size: Int64(data.count),
			attributes: "(preloaded at selection)",
			firstBytesHex: data.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " "),
			errorDomain: nil,
			errorCode: nil,
			errorDescription: nil,
			errorUserInfo: nil,
			data: data
		)
	}

	/// Multi-line attribute summary for the failure screens.
	static func summary(_ outcome: Outcome) -> String {
		var lines: [String] = []
		lines.append("path: \(outcome.url.path)")
		lines.append("fileURL: \(outcome.isFileURL)  exists: \(outcome.exists)  readable: \(outcome.isReadable)  dir: \(outcome.isDirectory)  size: \(outcome.size)")
		if let code = outcome.errorCode {
			lines.append("error: \(outcome.errorDomain ?? "?") \(code) — \(outcome.errorDescription ?? "?")")
			if let info = outcome.errorUserInfo, !info.isEmpty {
				lines.append("userInfo: \(info)")
			}
		} else {
			lines.append("error: nil")
		}
		lines.append("head: \(outcome.firstBytesHex)")
		lines.append("attrs: \(outcome.attributes)")
		return lines.joined(separator: "\n")
	}
}
