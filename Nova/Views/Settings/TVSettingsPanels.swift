import SwiftUI

#if os(tvOS)
struct TVSettingsPanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.appFont(24, weight: .semibold)).padding(.bottom, 6)
                content
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, TVReferenceStyle.edge)
            .padding(.top, 8)
            .padding(.bottom, 70)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.Colors.appBackground.ignoresSafeArea())
    }
}

private struct TVSettingLabel: View {
    let title: String
    var detail: String = ""
    var icon: String = "chevron.right"
    var destructive = false

    var body: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.appFont(27, weight: .semibold))
                    .foregroundStyle(destructive ? Theme.Colors.error : Theme.Colors.textPrimary)
                if !detail.isEmpty {
                    Text(detail).font(.appFont(21)).foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            Image(systemName: icon).font(.appFont(24, weight: .semibold))
                .foregroundStyle(destructive ? Theme.Colors.error : Theme.Colors.accent)
        }
        .padding(.horizontal, 22).padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct TVSettingAction: View {
    let title: String
    var detail = ""
    var icon = "chevron.right"
    var destructive = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            TVSettingLabel(title: title, detail: detail, icon: icon, destructive: destructive)
        }
        .buttonStyle(TVReferenceButtonStyle())
    }
}

private struct TVSettingToggle: View {
    let title: String
    var detail = ""
    @Binding var isOn: Bool
    var body: some View {
        TVSettingAction(title: title, detail: detail, icon: isOn ? "checkmark.circle.fill" : "circle") {
            isOn.toggle()
        }
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint("Press to change")
    }
}

struct TVPlayerSettingsPanel: View {
    @EnvironmentObject private var settings: SettingsStore
    var body: some View {
        TVSettingsPanel(title: "Player") {
            NavigationLink { PlayerSettingsView() } label: {
                TVSettingLabel(title: "Player", detail: settings.builtInPlayer.title, icon: "play.rectangle")
            }.buttonStyle(TVReferenceButtonStyle())
            TVSettingToggle(title: "Resume Playback", detail: "Continue from your saved position", isOn: $settings.resumePlaybackEnabled)
            NavigationLink { SettingsScreen(title: "Subtitles") { SubtitleSettingsContent() } } label: {
                TVSettingLabel(title: "Subtitles", detail: "Language, downloads, and display", icon: "captions.bubble")
            }.buttonStyle(TVReferenceButtonStyle())
            NavigationLink { SettingsScreen(title: "Streaming") { StreamingSettingsContent() } } label: {
                TVSettingLabel(title: "Stream Selection", detail: "Quality, cached sources, and source priority", icon: "slider.horizontal.3")
            }.buttonStyle(TVReferenceButtonStyle())
        }
    }
}

struct TVAutoPlaySettingsPanel: View {
    @EnvironmentObject private var settings: SettingsStore
    var body: some View {
        TVSettingsPanel(title: "Auto-Play") {
            TVSettingToggle(title: "Auto-Play Next Episode", isOn: $settings.autoPlayNext)
            TVSettingToggle(title: "Auto-Select Best Stream", detail: "Uses your quality, cached-source, and source-priority preferences", isOn: $settings.autoSelectStream)
            TVSettingToggle(title: "Show Skip Intro", isOn: $settings.skipIntroEnabled)
            TVSettingToggle(title: "Automatically Skip Intro", isOn: $settings.autoSkipIntro)
            TVSettingToggle(title: "Show Skip Outro", isOn: $settings.skipOutroEnabled)
            Text("Individual shows can override these defaults from their Binge Settings.")
                .font(.appFont(21)).foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

struct TVCacheSettingsPanel: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var status = ""
    @State private var busy = false
    var body: some View {
        TVSettingsPanel(title: "Cache") {
            TVSettingAction(title: "Clear Image Memory", detail: "Release decoded images from memory. Artwork on disk is retained.", icon: "photo") {
                busy = true
                Task { await ImageLoader.shared.purgeMemory(); status = "Image memory cleared."; busy = false }
            }.disabled(busy)
            TVSettingAction(title: "Refresh Catalog Cache", detail: "Reload catalog shelves the next time you browse them", icon: "arrow.clockwise") {
                busy = true
                Task { await env.shelfLoader.clearCache(); status = "Catalog cache cleared."; busy = false }
            }.disabled(busy)
            NavigationLink { OfflineDownloadsView() } label: {
                TVSettingLabel(title: "Offline Downloads", detail: "\(env.downloads.downloads.count) saved transfers", icon: "arrow.down.circle")
            }.buttonStyle(TVReferenceButtonStyle())
            if !status.isEmpty { Text(status).font(.appFont(21)).accessibilityAddTraits(.updatesFrequently) }
        }
    }
}

struct TVSearchSettingsPanel: View {
    @EnvironmentObject private var settings: SettingsStore
    var body: some View {
        TVSettingsPanel(title: "Search") {
            AppearanceSettingsContent()
            if !settings.guestMode {
                NavigationLink { AISearchSettingsView() } label: {
                    TVSettingLabel(title: "AI Search", detail: "Provider, search behavior, and privacy", icon: "sparkles")
                }.buttonStyle(TVReferenceButtonStyle())
            }
        }
    }
}

struct TVInterfaceSettingsPanel: View {
    var body: some View {
        TVSettingsPanel(title: "UI") {
            NavigationLink { SettingsScreen(title: "Accessibility") { AccessibilitySettingsContent() } } label: {
                TVSettingLabel(title: "Accessibility", detail: "Text and display preferences", icon: "accessibility")
            }.buttonStyle(TVReferenceButtonStyle())
            NavigationLink { SettingsScreen(title: "Home & Profiles") { ExperienceSettingsContent() } } label: {
                TVSettingLabel(title: "Home & Profiles", detail: "Personalize your browsing experience", icon: "house")
            }.buttonStyle(TVReferenceButtonStyle())
            NavigationLink { SettingsScreen(title: "Library") { LibrarySettingsContent() } } label: {
                TVSettingLabel(title: "Library", detail: "Library tools and maintenance", icon: "books.vertical")
            }.buttonStyle(TVReferenceButtonStyle())
            NavigationLink { LibraryFoldersView() } label: {
                TVSettingLabel(title: "SMB Library Folders", icon: "externaldrive")
            }.buttonStyle(TVReferenceButtonStyle())
            NavigationLink { SettingsScreen(title: "Advanced") { AdvancedSettingsContent() } } label: {
                TVSettingLabel(title: "Advanced", detail: "Guest mode and diagnostics", icon: "gearshape.2")
            }.buttonStyle(TVReferenceButtonStyle())
            NavigationLink { UnifiedQASettingsView() } label: {
                TVSettingLabel(title: "Quality Assurance", detail: "Off by default", icon: "checkmark.seal")
            }.buttonStyle(TVReferenceButtonStyle())
        }
    }
}

struct TVIntegrationSettingsPanel: View {
    enum Kind { case mdblist, trakt, glow }
    let kind: Kind
    @EnvironmentObject private var settings: SettingsStore
    @AppStorage("nova.tvFocusGlowEnabled") private var glowEnabled = true
    @AppStorage("nova.tvFocusGlowStrength") private var glowStrength = 0.35
    private var title: String {
        switch kind { case .mdblist: return "MDBList"; case .trakt: return "Trakt"; case .glow: return "Glow" }
    }
    var body: some View {
        TVSettingsPanel(title: title) {
            switch kind {
            case .mdblist:
                Text("Nova uses installed catalog addons for external lists. There is no separate MDBList account connection in this app.")
                    .font(.appFont(23)).foregroundStyle(Theme.Colors.textSecondary)
                if !settings.reviewSafeMode {
                    NavigationLink { AddonsView() } label: {
                        TVSettingLabel(title: "Manage Catalog Addons", detail: "Install or configure your list provider", icon: "puzzlepiece.extension")
                    }.buttonStyle(TVReferenceButtonStyle())
                }
            case .trakt:
                Text("Import a Trakt export ZIP using Nova on iPhone or iPad: Settings → Accounts → Nova Tracker. Nova previews the archive locally and imports only the records you confirm. Trakt is not a connected provider.")
                    .font(.appFont(23)).foregroundStyle(Theme.Colors.textSecondary)
                NavigationLink { AccountsView() } label: {
                    TVSettingLabel(title: "Accounts & Nova Tracker", detail: "View the tracking services actually available on this device", icon: "person.crop.circle")
                }.buttonStyle(TVReferenceButtonStyle())
            case .glow:
                TVSettingToggle(title: "Focus Glow", detail: "Highlight the currently focused control", isOn: $glowEnabled)
                SettingsPickerRow(icon: "sun.max", color: Theme.Colors.accent, title: "Glow Strength",
                    selection: $glowStrength, options: [0.15, 0.35, 0.6],
                    label: { $0 < 0.2 ? "Subtle" : $0 > 0.5 ? "Bright" : "Standard" })
                    .disabled(!glowEnabled)
                NavigationLink { SettingsScreen(title: "Accessibility") { AccessibilitySettingsContent() } } label: {
                    TVSettingLabel(title: "Display & Accessibility", icon: "accessibility")
                }.buttonStyle(TVReferenceButtonStyle())
            }
        }
        .onChange(of: glowEnabled) { _, value in CloudSync.shared.setBool(value, forKey: "nova.tvFocusGlowEnabled") }
        .onChange(of: glowStrength) { _, value in CloudSync.shared.setDouble(value, forKey: "nova.tvFocusGlowStrength") }
    }
}

struct TVCloudSettingsPanel: View {
    @ObservedObject var addonStore: AddonStore
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var cloud = CloudSync.shared
    @ObservedObject private var history = StreamHistoryStore.shared
    @State private var deletion: SettingsDataDomain?
    @State private var confirmDeletion = false
    @State private var confirmPull = false
    @State private var message = ""

    var body: some View {
        TVSettingsPanel(title: "iCloud") {
            ForEach(SettingsDataDomain.allCases) { domain in
                TVSettingLabel(title: domain.title, detail: detail(domain), icon: cloud.isPaused(domain) ? "pause.circle" : "icloud")
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: TVReferenceStyle.cornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: TVReferenceStyle.cornerRadius).strokeBorder(.white.opacity(0.15)))
            }
            if let issue = cloud.syncIssue {
                Text(issue).font(.appFont(20)).foregroundStyle(Theme.Colors.warning)
            } else {
                Text(cloud.lastExternalChange.map { "Last iCloud update: \($0.mediumDateTimeText)" }
                     ?? "iCloud confirms changes asynchronously. Local data remains available offline.")
                    .font(.appFont(20)).foregroundStyle(Theme.Colors.textSecondary)
            }
            if let issue = library.lastPersistenceError ?? addonStore.lastPersistenceError {
                Text("Local storage needs attention: \(issue)").font(.appFont(20)).foregroundStyle(Theme.Colors.warning)
            }
            section("Manual Sync")
            TVSettingAction(title: "Push Settings to iCloud", detail: "Send preferences, watch history, library, and addons from this device", icon: "arrow.up.to.line") {
                settings.pushPreferencesToCloud()
                library.pushSettingsDataToCloud()
                history.pushSettingsDataToCloud()
                addonStore.pushSettingsDataToCloud()
                cloud.flush()
                message = "Sync requested. iCloud delivery is pending; account passwords were not included."
            }.disabled(!cloud.accountAvailable)
            TVSettingAction(title: "Pull Settings from iCloud", detail: "Apply available cloud data to this device", icon: "arrow.down.to.line") {
                confirmPull = true
            }.disabled(!cloud.accountAvailable)
            section("Snapshots")
            NavigationLink { TVSnapshotImportPanel() } label: {
                TVSettingLabel(title: "Import Snapshot", detail: "Preview and apply a snapshot from a URL", icon: "square.and.arrow.down")
            }.buttonStyle(TVReferenceButtonStyle())
            NavigationLink { BackupView() } label: {
                TVSettingLabel(title: "Backup Options", detail: "Existing setup backups and selective restore", icon: "clock.arrow.circlepath")
            }.buttonStyle(TVReferenceButtonStyle())
            section("Dangerous")
            ForEach(SettingsDataDomain.allCases) { domain in
                TVSettingAction(title: "Delete \(domain.title == "Preferences" ? "All Preferences" : domain.title)",
                    detail: "Choose this device only, or this device and iCloud", icon: "trash", destructive: true) {
                        deletion = domain; confirmDeletion = true
                    }
            }
            if !message.isEmpty { Text(message).font(.appFont(21)).accessibilityAddTraits(.updatesFrequently) }
        }
        .confirmationDialog("Delete \(deletion?.title ?? "Data")?", isPresented: $confirmDeletion,
                            titleVisibility: .visible) {
            Button("Delete on This Device", role: .destructive) { if let deletion { erase(deletion, includingCloud: false) } }
            if cloud.accountAvailable {
                Button("Delete on This Device and iCloud", role: .destructive) { if let deletion { erase(deletion, includingCloud: true) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Device-only deletion pauses this category's sync here until you choose Push or Pull. Cloud deletion also removes it from setup backups; older app versions may not honor deletion markers. Media files and account credentials are kept.")
        }
        .confirmationDialog("Pull Settings from iCloud?", isPresented: $confirmPull, titleVisibility: .visible) {
            Button("Pull Available Settings") {
                cloud.pull()
                settings.pullPreferencesFromCloud()
                library.pullSettingsDataFromCloud()
                history.pullSettingsDataFromCloud()
                addonStore.pullSettingsDataFromCloud()
                message = "Applied available cloud values. Further changes will arrive as iCloud syncs."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cloud preferences and addons can replace this device's settings. Newer library state and watch history are merged. Deletion markers continue to protect older deleted data.")
        }
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.appFont(23, weight: .semibold)).padding(.top, 16)
    }

    private func detail(_ domain: SettingsDataDomain) -> String {
        let count: String
        let keys: [String]
        switch domain {
        case .history:
            count = "\(library.items.filter { $0.lastPlayedDate != nil || $0.lastPlayedPosition > 0 }.count) playback entries · \(history.entries.count) remembered streams"
            keys = [StreamHistoryStore.cloudKey, PrefKey.cloudLibrary]
        case .preferences:
            count = "\(settings.preferenceCount) preferences"
            keys = cloud.storedKeys.filter { SettingsDataPolicy.domain(for: $0) == .preferences }
        case .library: count = "\(library.items.count) entries"; keys = [PrefKey.cloudLibrary]
        case .addons: count = "\(addonStore.addons.count) addons"; keys = ["cloud.addons"]
        }
        if cloud.isPaused(domain) || (domain == .library && cloud.isPaused(.history)) {
            return count + " · Sync paused after deletion"
        }
        if !cloud.accountAvailable { return count + " · On this device; iCloud unavailable" }
        return count + (keys.contains { cloud.object(forKey: $0) != nil }
            ? " · iCloud mirror available" : " · Waiting for an iCloud mirror")
    }

    private func erase(_ domain: SettingsDataDomain, includingCloud: Bool) {
        cloud.beginDeletion(domain, includingCloud: includingCloud)
        switch domain {
        case .history:
            library.applySettingsDeletions(); history.applySettingsDeletion()
            if includingCloud { library.redactCloudWatchHistory() }
        case .preferences:
            _ = cloud.consumeDeletion(.preferences)
            settings.resetLocalPreferences()
        case .library: library.applySettingsDeletions()
        case .addons: addonStore.applySettingsDeletion()
        }
        if includingCloud { BackupManager.shared.redactDeletedCategoryFromCloudBackup(domain) }
        message = "\(domain.title) deletion requested. " + (includingCloud
            ? "iCloud deletion requested; other updated devices apply it when they sync."
            : "Its iCloud copy is unchanged and sync is paused on this device.")
    }
}

struct TVWebManagementPanel: View {
    var body: some View {
        TVSettingsPanel(title: "Web Management") {
            Text("Manage this Apple TV's setup by importing a Nova snapshot from a private URL you control. Preview its contents before applying changes.")
                .font(.appFont(23)).foregroundStyle(Theme.Colors.textSecondary)
            NavigationLink { TVSnapshotImportPanel() } label: {
                TVSettingLabel(title: "Import from Private URL", detail: "HTTP or HTTPS snapshot link", icon: "link")
            }.buttonStyle(TVReferenceButtonStyle())
            NavigationLink { BackupView() } label: {
                TVSettingLabel(title: "Existing Backup & Share Options", icon: "square.and.arrow.up")
            }.buttonStyle(TVReferenceButtonStyle())
            Text("Nova does not run a web management server on this Apple TV. Keep snapshot links private; a snapshot can contain addresses, configured addon URLs, or saved credentials.")
                .font(.appFont(21)).foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

struct TVSnapshotImportPanel: View {
    @State private var address = ""
    @State private var data: Data?
    @State private var preview: BackupSnapshot?
    @State private var available: BackupContents = []
    @State private var selection: BackupContents = []
    @State private var loading = false
    @State private var message = ""
    @State private var confirmImport = false
    @State private var requestTask: Task<Void, Never>?

    var body: some View {
        TVSettingsPanel(title: "Import Snapshot") {
            TextField("Private snapshot URL", text: $address)
                .font(.appFont(24)).autocorrectionDisabled()
                .onChange(of: address) { _, _ in
                    requestTask?.cancel(); loading = false; data = nil; preview = nil; selection = []
                }
            TVSettingAction(title: loading ? "Loading Preview…" : "Preview Snapshot",
                            detail: "Downloads up to 10 MB without applying changes", icon: "doc.text.magnifyingglass") {
                loadPreview()
            }.disabled(loading || SettingsDataPolicy.validSnapshotURL(address) == nil)
            if let preview {
                Text("Snapshot from \(preview.deviceName.isEmpty ? "another device" : preview.deviceName) · \(preview.createdAt.mediumDateTimeText)")
                    .font(.appFont(22, weight: .semibold))
                Text("\(preview.settings.count) preferences · \(preview.secrets.count) saved credentials. Credentials are excluded unless you select them below. Previously deleted categories may be excluded.")
                    .font(.appFont(21)).foregroundStyle(Theme.Colors.textSecondary)
                ForEach(BackupContents.catalog.filter { available.contains($0.option) }) { item in
                    TVSettingToggle(title: item.title,
                        detail: item.sensitive ? "Overwrite saved credentials only if you trust this snapshot" : item.detail,
                        isOn: Binding(get: { selection.contains(item.option) }, set: { enabled in
                            if enabled { selection.insert(item.option) } else { selection.remove(item.option) }
                        }))
                }
                TVSettingAction(title: "Import Selected Contents", detail: "Review the final confirmation before changes are applied", icon: "square.and.arrow.down") {
                    confirmImport = true
                }.disabled(selection.isEmpty)
            }
            if !message.isEmpty { Text(message).font(.appFont(21)).accessibilityAddTraits(.updatesFrequently) }
        }
        .onDisappear { requestTask?.cancel() }
        .confirmationDialog("Apply This Snapshot?", isPresented: $confirmImport, titleVisibility: .visible) {
            Button("Apply Selected Contents") {
                guard let data else { return }
                let success = BackupManager.shared.importSnapshotData(data, restoring: selection)
                message = success ? "Selected snapshot contents applied." : "Snapshot could not be imported."
                if success { self.data = nil; preview = nil; selection = [] }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Selected preferences, sources, and addons may replace existing setup data and sync to iCloud. Saved logins change only when you selected Logins & API keys. Your media files remain on disk.")
        }
    }

    private func loadPreview() {
        guard let url = SettingsDataPolicy.validSnapshotURL(address) else { return }
        requestTask?.cancel()
        loading = true; message = ""; preview = nil; data = nil
        requestTask = Task {
            let downloaded = await BackupManager.shared.downloadSnapshot(from: url)
            guard !Task.isCancelled else { return }
            loading = false
            guard let downloaded, let decoded = BackupManager.shared.snapshotPreview(downloaded),
                  let contents = BackupManager.shared.contentsOfSnapshotData(downloaded), !contents.isEmpty else {
                message = "No importable Nova snapshot was found. Check the URL, network, size, and deletion history."
                return
            }
            data = downloaded; preview = decoded; available = contents; selection = contents.subtracting(.secrets)
        }
    }
}
#endif
