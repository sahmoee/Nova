//
//  BackupView.swift
//  FrameTV
//
//  UI for creating an iCloud snapshot of the user's whole setup and restoring it
//  on another device. Backs up preferences, sources, addons, and all logins/keys.
//

import SwiftUI

struct BackupView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var backup = BackupManager.shared

    @State private var confirmRestore = false
    @State private var restoreResult: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("iCloud Backup & Restore")
                    .font(Theme.Font.screenTitle())
                    .screenTitleStyle()
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Save a snapshot of everything — your preferences, sources, addons, and all logins and API keys — to your private iCloud. Then restore it on another device signed in to the same Apple ID.")
                    .font(.appFont(19))
                    .foregroundStyle(Theme.Colors.textSecondary)

                // Status card.
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    if let info = backup.availableSnapshotInfo() {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Snapshot available").font(.appFont(19, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text("From \(info.device) · \(dateText(info.date))")
                                    .font(.appFont(16))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        } icon: {
                            Image(systemName: "icloud.fill").foregroundStyle(Theme.Colors.accent)
                        }
                    } else {
                        Label("No snapshot in iCloud yet", systemImage: "icloud.slash")
                            .font(.appFont(19))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                // Back up now.
                FocusableButton(title: "Back Up Now", systemImage: "icloud.and.arrow.up",
                                prominent: true) {
                    backup.createBackup()
                    ToastCenter.shared.show("Backed up to iCloud", systemImage: "icloud.and.arrow.up.fill")
                }
                .frame(maxWidth: Theme.isCompact ? .infinity : 360)

                // Restore.
                FocusableButton(title: "Restore from iCloud", systemImage: "icloud.and.arrow.down") {
                    confirmRestore = true
                }
                .frame(maxWidth: Theme.isCompact ? .infinity : 360)
                .disabled(!backup.hasCloudSnapshot())
                .opacity(backup.hasCloudSnapshot() ? 1 : 0.5)

                if let restoreResult {
                    Text(restoreResult)
                        .font(.appFont(17))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Text("Your snapshot stays inside your personal iCloud and is never sent anywhere else. Restoring replaces this device's settings, sources, and logins with the snapshot.")
                    .font(.appFont(15))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.top, Theme.Spacing.sm)
            }
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.bottom, Theme.Spacing.xl)
            .frame(maxWidth: Theme.contentMaxWidth(1000), alignment: .leading)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .alert("Restore from iCloud?", isPresented: $confirmRestore) {
            Button("Restore", role: .destructive) { performRestore() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces this device's preferences, sources, addons, and logins with the iCloud snapshot.")
        }
    }

    private func performRestore() {
        let ok = backup.restoreFromCloud()
        restoreResult = ok
            ? "Restored. Reopen the app to fully apply restored sources and logins."
            : "Couldn't find a snapshot to restore."
        if ok { ToastCenter.shared.show("Restored from iCloud", systemImage: "checkmark.icloud.fill") }
    }

    private func dateText(_ date: Date) -> String {
        let fmt = DateFormatter(); fmt.dateStyle = .medium; fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}
