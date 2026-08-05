//
//  LabSpecimenCard.swift
//  The Lab
//
//  Created by Michael Shingara on 8/2/26.
//

import SwiftUI
import NimbleExtensions
import NimbleViews

/// The Lab's specimen card — a floating obsidian panel on the OLED canvas.
///
/// Replaces Feather's LibraryCellView. Preserves all existing bindings and
/// action logic (info, sign, install, update, delete, export, re-sign, open).
/// Visual language: true black background, near-black elevated card, Playfair
/// SemiBold title, neon accent icon glow, FRExpirationPillView for status.
struct LabSpecimenCard: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.editMode) private var editMode
	@ObservedObject private var updateManager = UpdateManager.shared
	@State private var _signedUpdateConfirmation: AppUpdate?
	@State private var _isSignedUpdateConfirmationPresented = false

	var certInfo: Date.ExpirationInfo? {
		Storage.shared.getCertificate(from: app)?.expiration?.expirationInfo()
	}

	var certRevoked: Bool {
		Storage.shared.getCertificate(from: app)?.revoked == true
	}

	let app: AppInfoPresentable
	@Binding var selectedInfoAppPresenting: AnyApp?
	@Binding var selectedSigningAppPresenting: AnyApp?
	@Binding var selectedInstallAppPresenting: AnyApp?
	@Binding var selectedAppUUIDs: Set<String>

	// MARK: - Selection

	private var _isSelected: Bool {
		guard let uuid = app.uuid else { return false }
		return selectedAppUUIDs.contains(uuid)
	}

	private func _toggleSelection() {
		guard let uuid = app.uuid else { return }
		if selectedAppUUIDs.contains(uuid) {
			selectedAppUUIDs.remove(uuid)
		} else {
			selectedAppUUIDs.insert(uuid)
		}
	}

	// MARK: - Body

	var body: some View {
		let isRegular = horizontalSizeClass != .compact
		let isEditing = editMode?.wrappedValue == .active

		HStack(spacing: 14) {
			if isEditing {
				Button { _toggleSelection() } label: {
					Image(systemName: _isSelected ? "checkmark.circle.fill" : "circle")
						.font(.title2)
						.foregroundStyle(_isSelected ? LabTheme.accent : LabTheme.textTertiary)
				}
				.buttonStyle(.borderless)
			}

			_appIcon

			VStack(alignment: .leading, spacing: 4) {
				Text(app.name ?? "Unknown")
					.font(.playfair(16, weight: .semiBold))
					.foregroundStyle(LabTheme.textPrimary)
					.lineLimit(1)

				Text(_desc)
					.font(.system(size: 12))
					.foregroundStyle(LabTheme.textTertiary)
					.lineLimit(1)
			}

			if !isEditing {
				_buttonActions
			}

			Spacer(minLength: 8)

			if isEditing {
				Image(systemName: "line.3.horizontal")
					.font(.system(size: 16, weight: .medium))
					.foregroundStyle(LabTheme.textTertiary)
			}
		}
		.padding(.vertical, 10)
		.padding(.horizontal, 14)
		.background(
			RoundedRectangle(cornerRadius: LabTheme.cardCornerRadius, style: .continuous)
				.fill(
					LinearGradient(
						colors: _isSelected && isEditing
							? [LabTheme.accent.opacity(0.08), LabTheme.accent.opacity(0.03)]
							: [LabTheme.surfaceElevated, LabTheme.surfaceSecondary],
						startPoint: .top, endPoint: .bottom
					)
				)
		)
		.overlay(
			RoundedRectangle(cornerRadius: LabTheme.cardCornerRadius, style: .continuous)
				.stroke(
					_isSelected && isEditing
						? LabTheme.accent.opacity(0.4)
						: LabTheme.hairline,
					lineWidth: _isSelected && isEditing ? 1.5 : 1
				)
		)
		.shadow(color: .black.opacity(0.5), radius: isRegular ? 18 : 10, x: 0, y: isRegular ? 8 : 4)
		.labGlow(active: _isSelected && isEditing, color: LabTheme.accent, radius: 14)
		.contentShape(RoundedRectangle(cornerRadius: LabTheme.cardCornerRadius, style: .continuous))
		.onTapGesture {
			if isEditing { _toggleSelection() }
		}
		.swipeActions {
			if !isEditing { _swipeActions }
		}
		.contextMenu {
			if !isEditing {
				_contextActions
				Divider()
				_contextActionsExtra
				Divider()
				_swipeActions
			}
		}
		.confirmationDialog(
			"Update Available",
			isPresented: $_isSignedUpdateConfirmationPresented,
			titleVisibility: .visible
		) {
			Button("Install Current Version", systemImage: "square.and.arrow.down") {
				selectedInstallAppPresenting = AnyApp(base: app)
			}
			if let update = _signedUpdateConfirmation {
				Button("Download Update", systemImage: "arrow.down.circle") {
					_startUpdateDownload(update)
				}
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			if let update = _signedUpdateConfirmation {
				Text("\(update.appName) \(update.remoteVersion)")
			}
		}
	}

	// MARK: - Subviews

	private var _appIcon: some View {
		FRAppIconView(app: app, size: 57)
			.overlay(alignment: .topTrailing) {
				if updateManager.update(for: app) != nil {
					Image(systemName: "arrow.down.circle.fill")
						.font(.system(size: 18, weight: .semibold))
						.symbolRenderingMode(.palette)
						.foregroundStyle(.white, LabTheme.accent)
						.background(Circle().fill(LabTheme.surfacePrimary).frame(width: 20, height: 20))
						.offset(x: 5, y: -5)
						.accessibilityLabel("Update Available")
				}
			}
	}

	private var _desc: String {
		if let version = app.version, let id = app.identifier {
			return "\(version) • \(id)"
		}
		return "Unknown"
	}

	@ViewBuilder
	private var _swipeActions: some View {
		Button("Delete", systemImage: "trash", role: .destructive) {
			Storage.shared.deleteApp(for: app)
		}
	}

	@ViewBuilder
	private var _contextActions: some View {
		Button("Get Info", systemImage: "info.circle") {
			selectedInfoAppPresenting = AnyApp(base: app)
		}
	}

	@ViewBuilder
	private var _contextActionsExtra: some View {
		if let update = updateManager.update(for: app) {
			Button("Update", systemImage: "arrow.down.circle") {
				if app.isSigned {
					_signedUpdateConfirmation = update
					_isSignedUpdateConfirmationPresented = true
				} else {
					_startUpdateDownload(update)
				}
			}
		}

		if app.isSigned {
			if let id = app.identifier {
				Button("Open", systemImage: "app.badge.checkmark") {
					UIApplication.openApp(with: id)
				}
			}
			Button("Install", systemImage: "square.and.arrow.down") {
				selectedInstallAppPresenting = AnyApp(base: app)
			}
			Button("Re-sign", systemImage: "signature") {
				selectedSigningAppPresenting = AnyApp(base: app)
			}
			Button("Export", systemImage: "square.and.arrow.up") {
				selectedInstallAppPresenting = AnyApp(base: app, archive: true)
			}
		} else {
			Button("Install", systemImage: "square.and.arrow.down") {
				selectedInstallAppPresenting = AnyApp(base: app)
			}
			Button("Sign", systemImage: "signature") {
				selectedSigningAppPresenting = AnyApp(base: app)
			}
		}
	}

	@ViewBuilder
	private var _buttonActions: some View {
		Group {
			if let update = updateManager.update(for: app) {
				if app.isSigned {
					Button { _signedUpdateConfirmation = update; _isSignedUpdateConfirmationPresented = true } label: {
						FRExpirationPillView(title: "Install", revoked: certRevoked, expiration: certInfo)
					}
				} else {
					Button { _startUpdateDownload(update) } label: {
						FRExpirationPillView(title: "Update", revoked: false, expiration: nil)
					}
				}
			} else if app.isSigned {
				Button { selectedInstallAppPresenting = AnyApp(base: app) } label: {
					FRExpirationPillView(title: "Install", revoked: certRevoked, expiration: certInfo)
				}
			} else {
				Button { selectedSigningAppPresenting = AnyApp(base: app) } label: {
					FRExpirationPillView(title: "Sign", revoked: false, expiration: nil)
				}
			}
		}
		.buttonStyle(.borderless)
	}

	private func _startUpdateDownload(_ update: AppUpdate) {
		_ = DownloadManager.shared.startDownload(
			from: update.downloadURL,
			id: "FeatherManualDownload_Update_\(update.localUUID)",
			sourceProvenance: update.sourceProvenance
		)
	}
}