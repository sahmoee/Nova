//
//  BackupView.swift
//  FrameTV
//
//  UI for creating an iCloud snapshot of the user's whole setup and restoring it
//  on another device. Backs up preferences, sources, addons, and all logins/keys.
//

import SwiftUI
#if os(iOS)
import UniformTypeIdentifiers
#endif

struct BackupView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var backup = BackupManager.shared

    @State private var restoreResult: String?
    @State private var showShareSheet = false
    @State private var showImporter = false
    @State private var exportURL: URL?

    // Contents-picker state for choosing what to include / restore.
    @State private var showExportPicker = false
    @State private var showCloudRestorePicker = false
    @State private var showFileRestorePicker = false
    @State private var pendingImportURL: URL?
    @State private var pendingImportContents: BackupContents = []

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
                    showCloudRestorePicker = true
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

                #if os(iOS)
                Divider().padding(.vertical, Theme.Spacing.md)

                Text("Share a Snapshot File")
                    .font(Theme.Font.sectionTitle())
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Export your setup as a file you can share or move to another device. You choose what goes in — preferences, sources, addons, and optionally your logins and API keys for sharing within a trusted household.")
                    .font(.appFont(17))
                    .foregroundStyle(Theme.Colors.textSecondary)

                FocusableButton(title: "Export Snapshot File", systemImage: "square.and.arrow.up") {
                    showExportPicker = true
                }
                .frame(maxWidth: Theme.isCompact ? .infinity : 360)

                FocusableButton(title: "Import Snapshot File", systemImage: "square.and.arrow.down") {
                    showImporter = true
                }
                .frame(maxWidth: Theme.isCompact ? .infinity : 360)
                #endif
            }
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.bottom, Theme.Spacing.xl)
            .frame(maxWidth: Theme.contentMaxWidth(1000), alignment: .leading)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        // iCloud restore: pick what to restore.
        .sheet(isPresented: $showCloudRestorePicker) {
            BackupContentsPicker(mode: .restore,
                                 available: backup.cloudSnapshotContents() ?? .safe) { contents in
                performRestore(contents)
            }
        }
        #if os(iOS)
        // Export: pick what to include, then share.
        .sheet(isPresented: $showExportPicker) {
            BackupContentsPicker(mode: .export, available: backup.currentDeviceContents()) { contents in
                if let url = backup.exportSnapshotFile(including: contents) {
                    exportURL = url
                    showShareSheet = true
                } else {
                    ToastCenter.shared.show("Couldn't create export", systemImage: "exclamationmark.triangle")
                }
            }
        }
        // File restore: pick what to apply from the imported file.
        .sheet(isPresented: $showFileRestorePicker) {
            BackupContentsPicker(mode: .restore, available: pendingImportContents) { contents in
                if let url = pendingImportURL {
                    let ok = backup.importSnapshotFile(url, restoring: contents)
                    ToastCenter.shared.show(ok ? "Snapshot imported" : "Import failed",
                                            systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle")
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let exportURL { ShareSheet(items: [exportURL]) }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.data, .json],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // Read what the file contains, then let the user choose.
                    if let contents = backup.contentsOfSnapshotFile(url), !contents.isEmpty {
                        pendingImportURL = url
                        pendingImportContents = contents
                        showFileRestorePicker = true
                    } else {
                        ToastCenter.shared.show("Couldn't read snapshot", systemImage: "exclamationmark.triangle")
                    }
                }
            case .failure:
                ToastCenter.shared.show("Import cancelled", systemImage: "xmark.circle")
            }
        }
        #endif
    }

    private func performRestore(_ contents: BackupContents = .all) {
        let ok = backup.restoreFromCloud(restoring: contents)
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

#if os(iOS)
/// Wraps UIActivityViewController for sharing the exported snapshot file.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
