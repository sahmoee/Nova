//
//  BackupView.swift
//  Astra
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

    // Restore-source state (Files / URL / QR / Drive).
    @State private var showURLEntry = false
    @State private var urlText = ""
    @State private var showQRScanner = false
    @State private var pendingImportData: Data?
    @State private var showDataRestorePicker = false
    @State private var isDownloading = false

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
                .refinedCardBackground()

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

                Text("Restore from")
                    .font(Theme.Font.sectionTitle())
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.top, Theme.Spacing.sm)

                FocusableButton(title: "Files", systemImage: "folder") {
                    showImporter = true
                }
                .frame(maxWidth: Theme.isCompact ? .infinity : 360)

                FocusableButton(title: isDownloading ? "Downloading…" : "From a Link (URL)",
                                systemImage: "link") {
                    urlText = ""
                    showURLEntry = true
                }
                .frame(maxWidth: Theme.isCompact ? .infinity : 360)
                .disabled(isDownloading)

                FocusableButton(title: "Scan QR Code", systemImage: "qrcode.viewfinder") {
                    showQRScanner = true
                }
                .frame(maxWidth: Theme.isCompact ? .infinity : 360)

                FocusableButton(title: "Google Drive / iCloud Drive", systemImage: "externaldrive.badge.icloud") {
                    // Drive and iCloud Drive appear as locations inside the Files
                    // picker when their apps are installed.
                    showImporter = true
                }
                .frame(maxWidth: Theme.isCompact ? .infinity : 360)

                Text("Google Drive, Dropbox, and iCloud Drive show up as locations in the Files picker when their apps are installed. A QR code holds a link to a snapshot, not the snapshot itself.")
                    .font(.appFont(14))
                    .foregroundStyle(Theme.Colors.textTertiary)
                #endif
            }
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.bottom, Theme.Spacing.xl)
            .frame(maxWidth: Theme.contentMaxWidth(1000), alignment: .leading)
        }
        .background(Theme.Colors.appBackground.ignoresSafeArea())
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
        // Data restore (from URL download or QR): pick what to apply.
        .sheet(isPresented: $showDataRestorePicker) {
            BackupContentsPicker(mode: .restore, available: pendingImportContents) { contents in
                if let data = pendingImportData {
                    let ok = backup.importSnapshotData(data, restoring: contents)
                    ToastCenter.shared.show(ok ? "Snapshot imported" : "Import failed",
                                            systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle")
                }
            }
        }
        // QR scanner: decodes a URL, then downloads + imports it.
        .sheet(isPresented: $showQRScanner) {
            QRScannerView { code in
                if let url = URL(string: code.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    Task { await downloadAndPrepare(url) }
                } else {
                    ToastCenter.shared.show("That QR code isn't a link", systemImage: "qrcode")
                }
            }
        }
        // URL entry for restoring from a link.
        .alert("Restore from a Link", isPresented: $showURLEntry) {
            TextField("https://example.com/backup.frametv", text: $urlText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Download") {
                if let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    Task { await downloadAndPrepare(url) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste a direct link to a Astra snapshot file.")
        }
        #endif
    }

    #if os(iOS)
    /// Downloads a snapshot from a URL, inspects its contents, and opens the restore
    /// picker so the user chooses what to apply.
    private func downloadAndPrepare(_ url: URL) async {
        isDownloading = true
        defer { isDownloading = false }
        guard let data = await backup.downloadSnapshot(from: url),
              let contents = backup.contentsOfSnapshotData(data), !contents.isEmpty else {
            ToastCenter.shared.show("Couldn't load a snapshot from that link",
                                    systemImage: "exclamationmark.triangle")
            return
        }
        pendingImportData = data
        pendingImportContents = contents
        showDataRestorePicker = true
    }
    #endif

    private func performRestore(_ contents: BackupContents = .all) {
        let ok = backup.restoreFromCloud(restoring: contents)
        restoreResult = ok
            ? "Restored. Reopen the app to fully apply restored sources and logins."
            : "Couldn't find a snapshot to restore."
        if ok { ToastCenter.shared.show("Restored from iCloud", systemImage: "checkmark.icloud.fill") }
    }

    private func dateText(_ date: Date) -> String {
        date.mediumDateTimeText
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
