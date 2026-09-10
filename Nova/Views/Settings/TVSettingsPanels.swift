import SwiftUI

#if os(tvOS)
struct TVSettingsPanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.appFont(42, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 10)
                content
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, TVReferenceStyle.edge)
            .padding(.top, TVReferenceStyle.top)
            .padding(.bottom, 96)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .focusSection()
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
                Text(title).font(.appFont(24, weight: .semibold))
                    .foregroundStyle(destructive ? Theme.Colors.error : Theme.Colors.textPrimary)
                if !detail.isEmpty {
                    Text(detail).font(.appFont(18)).foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            Image(systemName: icon).font(.appFont(24, weight: .semibold))
                .foregroundStyle(destructive ? Theme.Colors.error : Theme.Colors.textPrimary)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
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
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.appFont(24, weight: .semibold))
                if !detail.isEmpty {
                    Text(detail)
                        .font(.appFont(18))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 22)
        .background(.white.opacity(0.075),
                    in: RoundedRectangle(cornerRadius: TVReferenceStyle.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TVReferenceStyle.cornerRadius, style: .continuous)
            .strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint("Press to toggle")
    }
}

struct TVPlayerSettingsPanel: View {
    @EnvironmentObject private var settings: SettingsStore
    var body: some View {
        TVSettingsPanel(title: "Playback") {
            NavigationLink { PlayerSettingsView() } label: {
                TVSettingLabel(title: "Player", detail: settings.builtInPlayer.title, icon: "play.rectangle")
            }.buttonStyle(TVReferenceButtonStyle())
            TVSettingToggle(title: "Resume Playback", detail: "Continue from your saved position", isOn: $settings.resumePlaybackEnabled)
            NavigationLink { TVAutoPlaySettingsPanel() } label: {
                TVSettingLabel(title: "Auto-Play", detail: "Next episode, intros, and automatic source selection", icon: "play.forward")
            }.buttonStyle(TVReferenceButtonStyle())
            NavigationLink { SettingsScreen(title: "Subtitles") { SubtitleSettingsContent() } } label: {
                TVSettingLabel(title: "Subtitles", detail: "Language, downloads, and display", icon: "captions.bubble")
            }.buttonStyle(TVReferenceButtonStyle())
            NavigationLink { SettingsScreen(title: "Streaming") { StreamingSettingsContent() } } label: {
                TVSettingLabel(title: "Stream Selection", detail: "Quality, cached sources, and source priority", icon: "slider.horizontal.3")
            }.buttonStyle(TVReferenceButtonStyle())
        }
    }
}

/// tvOS exposes source operations as a short list of real destinations. Provider
/// setup and server maintenance no longer compete for space on Home.
struct TVSourcesSettingsPanel: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var smbShares = SMBSharesModel()

    var body: some View {
        TVSettingsPanel(title: "Sources") {
            if settings.guestMode {
                Text("Source management is unavailable in Guest Mode.")
                    .font(.appFont(22))
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                NavigationLink { MediaServersView() } label: {
                    TVSettingLabel(
                        title: "Media Servers",
                        detail: mediaServerDetail,
                        icon: "play.tv"
                    )
                }
                .buttonStyle(TVReferenceButtonStyle())

                NavigationLink { SMBListView() } label: {
                    TVSettingLabel(
                        title: "Network Shares",
                        detail: "\(smbShares.shares.count) SMB share\(smbShares.shares.count == 1 ? "" : "s")",
                        icon: "externaldrive"
                    )
                }
                .buttonStyle(TVReferenceButtonStyle())

                NavigationLink { LiveTVSourcesView() } label: {
                    TVSettingLabel(
                        title: "Live TV",
                        detail: "\(env.liveTVSources.sources.count) source\(env.liveTVSources.sources.count == 1 ? "" : "s")",
                        icon: "dot.radiowaves.left.and.right"
                    )
                }
                .buttonStyle(TVReferenceButtonStyle())

                if !settings.reviewSafeMode {
                    NavigationLink { RealDebridView() } label: {
                        TVSettingLabel(title: "Real-Debrid", detail: "Stream cache and account", icon: "bolt.horizontal")
                    }
                    .buttonStyle(TVReferenceButtonStyle())

                    NavigationLink { AddonsView() } label: {
                        TVSettingLabel(
                            title: "Add-ons",
                            detail: "\(env.addonStore.addons.count) installed",
                            icon: "puzzlepiece.extension"
                        )
                    }
                    .buttonStyle(TVReferenceButtonStyle())
                }

                NavigationLink { AccountsView() } label: {
                    TVSettingLabel(title: "Accounts", detail: "Tracking services available on Apple TV", icon: "person.crop.circle")
                }
                .buttonStyle(TVReferenceButtonStyle())
            }
        }
    }

    private var mediaServerDetail: String {
        let count = env.mediaServers.connections.count
        return count == 0 ? "Connect Jellyfin, Plex, or Emby" : "\(count) connected server\(count == 1 ? "" : "s")"
    }
}

struct TVLibrarySettingsPanel: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        TVSettingsPanel(title: "Library") {
            NavigationLink { SettingsScreen(title: "Library") { LibrarySettingsContent() } } label: {
                TVSettingLabel(title: "Library Behavior", detail: "History, indexing, and maintenance", icon: "rectangle.stack")
            }
            .buttonStyle(TVReferenceButtonStyle())

            NavigationLink { OfflineDownloadsView() } label: {
                TVSettingLabel(
                    title: "Offline Downloads",
                    detail: "\(env.downloads.downloads.count) saved transfer\(env.downloads.downloads.count == 1 ? "" : "s")",
                    icon: "arrow.down.circle"
                )
            }
            .buttonStyle(TVReferenceButtonStyle())

            NavigationLink { LibraryFoldersView() } label: {
                TVSettingLabel(
                    title: "Network Library Folders",
                    detail: "\(env.libraryFolders.folders.count) configured",
                    icon: "folder"
                )
            }
            .buttonStyle(TVReferenceButtonStyle())

            NavigationLink { TVSearchSettingsPanel() } label: {
                TVSettingLabel(title: "Search & Browse", detail: "Layout and search behavior", icon: "magnifyingglass")
            }
            .buttonStyle(TVReferenceButtonStyle())

            NavigationLink { TitleCleanupRulesView() } label: {
                TVSettingLabel(title: "Title Cleanup", detail: "Rules applied while indexing media", icon: "textformat")
            }
            .buttonStyle(TVReferenceButtonStyle())

            NavigationLink { TVCacheSettingsPanel() } label: {
                TVSettingLabel(title: "Storage", detail: "Artwork memory, catalog cache, and downloads", icon: "internaldrive")
            }
            .buttonStyle(TVReferenceButtonStyle())
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
        TVSettingsPanel(title: "Experience") {
            AppearanceSettingsContent()
            NavigationLink { SettingsScreen(title: "Accessibility") { AccessibilitySettingsContent() } } label: {
                TVSettingLabel(title: "Accessibility", detail: "Motion and display preferences", icon: "accessibility")
            }.buttonStyle(TVReferenceButtonStyle())
            NavigationLink { SettingsScreen(title: "Home & Profiles") { ExperienceSettingsContent() } } label: {
                TVSettingLabel(title: "Home & Profiles", detail: "Shelves, profiles, and artwork motion", icon: "house")
            }.buttonStyle(TVReferenceButtonStyle())
        }
    }
}

struct TVDataSettingsPanel: View {
    @ObservedObject var addonStore: AddonStore
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        TVSettingsPanel(title: "Data & Privacy") {
            if !settings.guestMode {
                NavigationLink { TVCloudSettingsPanel(addonStore: addonStore) } label: {
                    TVSettingLabel(title: "iCloud", detail: "Preferences, watch history, library, and add-ons", icon: "icloud")
                }
                .buttonStyle(TVReferenceButtonStyle())

                NavigationLink { TVWebManagementPanel() } label: {
                    TVSettingLabel(title: "Snapshot Import", detail: "Preview a private setup snapshot before applying it", icon: "square.and.arrow.down")
                }
                .buttonStyle(TVReferenceButtonStyle())
            }

            NavigationLink { SettingsScreen(title: "Advanced") { AdvancedSettingsContent() } } label: {
                TVSettingLabel(title: "Advanced", detail: "Guest Mode and maintenance", icon: "gearshape.2")
            }
            .buttonStyle(TVReferenceButtonStyle())

            NavigationLink { UnifiedQASettingsView() } label: {
                TVSettingLabel(title: "Quality Assurance", detail: "Diagnostics are off by default", icon: "checkmark.seal")
            }
            .buttonStyle(TVReferenceButtonStyle())

            NavigationLink { SettingsScreen(title: "Privacy & Legal") { PrivacyLegalSettingsContent() } } label: {
                TVSettingLabel(title: "Privacy & Legal", detail: "Data use, licenses, and notices", icon: "hand.raised")
            }
            .buttonStyle(TVReferenceButtonStyle())
        }
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
        TVSettingsPanel(title: "Snapshot Import") {
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
