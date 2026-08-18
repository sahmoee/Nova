//
//  AccountsView.swift
//  Nova
//
//  Native settings-style hub for external service accounts and API keys. Account
//  sign-ins are routed through each service's own authorization screen; manual keys
//  live in a separate group so setup does not feel like a credentials form first.
//

import SwiftUI
#if os(iOS)
import UniformTypeIdentifiers
#endif

struct AccountsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.openURL) private var openURL

    @State private var tmdbKey = ""
    @State private var openSubtitlesKey = ""
    @State private var omdbKey = ""
    @State private var savedFlash = false
    @State private var importingNova = false

    private let config = AppConfig.shared

    var body: some View {
        SettingsScreen(title: "Accounts") {
            SettingsGroup(
                header: "Services",
                footer: "Sign in through the service's own authorization page. Nova stores account tokens in the device Keychain.",
                rows: serviceRows
            )

            SettingsGroup(
                header: "API Keys",
                footer: "Keys are stored securely in the device Keychain. Leave a field blank to keep its current value.",
                rows: apiKeyRows
            )
        }
        .dismissKeyboardOnTap()
    }

    private var serviceRows: [AnyView] {
        [
            AnyView(
                NavigationLink { TraktConnectView() } label: {
                    SettingsRow(
                        icon: "checkmark.seal.fill",
                        color: Theme.Colors.iconRed,
                        title: "Trakt",
                        detail: traktDetail,
                        status: traktStatusColor
                    )
                }
                .buttonStyle(.plain)
            ),
            AnyView(
                NavigationLink { SimklConnectView() } label: {
                    SettingsRow(
                        icon: "checkmark.seal",
                        color: Theme.Colors.iconRed,
                        title: "SIMKL",
                        detail: "Optional tracker",
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            ),
            AnyView(
                NavigationLink { TMDBAccountConnectView() } label: {
                    SettingsRow(
                        icon: "person.crop.circle",
                        color: Theme.Colors.iconRed,
                        title: "TMDB Account",
                        detail: "Watchlist tracker",
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            ),
            AnyView(
                NavigationLink { NovaTrackerDashboardView() } label: {
                    SettingsRow(
                        icon: "sparkles.tv.fill",
                        color: Theme.Colors.iconRed,
                        title: "Nova Tracker",
                        detail: "Stats, activity, lists and backup",
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            ),
            AnyView(
                Button {
                    guard !importingNova else { return }
                    importingNova = true
                    let others = env.trackers.providers.filter { $0.trackerID != .nova }
                    Task {
                        let n = await env.novaTracker.importEverything(from: others)
                        await MainActor.run {
                            importingNova = false
                            ToastCenter.shared.show("Imported \(n) into Nova Tracker", systemImage: "square.and.arrow.down")
                        }
                    }
                } label: {
                    SettingsRow(
                        icon: importingNova ? "hourglass" : "square.and.arrow.down",
                        color: Theme.Colors.iconRed,
                        title: importingNova ? "Importing…" : "Import to Nova Tracker",
                        detail: "Import watchlist, watched history and ratings into Nova",
                        showsChevron: false
                    )
                }
                .buttonStyle(.plain)
                .disabled(importingNova)
            ),
            AnyView(
                NavigationLink { RealDebridView() } label: {
                    SettingsRow(
                        icon: "arrow.down.circle.fill",
                        color: Theme.Colors.iconRed,
                        title: "Real-Debrid",
                        detail: realDebridDetail,
                        status: realDebridStatusColor
                    )
                }
                .buttonStyle(.plain)
            )
        ]
    }

    private var apiKeyRows: [AnyView] {
        var rows: [AnyView] = [
            AnyView(
                credentialRow(
                    icon: "photo.on.rectangle",
                    color: Theme.Colors.iconGraphite,
                    title: "TMDB",
                    subtitle: "Posters, search, descriptions, seasons, and episodes.",
                    text: $tmdbKey,
                    isPresent: config.isPresent(.tmdbAPIKey),
                    externalURL: "https://www.themoviedb.org/settings/api"
                )
            ),
            AnyView(
                credentialRow(
                    icon: "captions.bubble.fill",
                    color: Theme.Colors.iconSilver,
                    title: "OpenSubtitles",
                    subtitle: "Optional subtitle search provider.",
                    text: $openSubtitlesKey,
                    isPresent: config.isPresent(.openSubtitlesAPIKey),
                    externalURL: "https://www.opensubtitles.com/consumers"
                )
            ),
            AnyView(
                credentialRow(
                    icon: "star.bubble.fill",
                    color: Theme.Colors.iconSilver,
                    title: "OMDb",
                    subtitle: "Optional IMDb, Rotten Tomatoes, and Metacritic ratings.",
                    text: $omdbKey,
                    isPresent: config.isPresent(.omdbAPIKey),
                    externalURL: "https://www.omdbapi.com/apikey.aspx"
                )
            )
        ]

        rows.append(AnyView(saveRow))
        return rows
    }

    private var traktDetail: String {
        if AppConfig.shared.value(for: .traktAccessToken)?.isEmpty == false { return "Connected · Log out" }
        if config.traktClientID?.isEmpty == false && config.traktClientSecret?.isEmpty == false { return "Log in" }
        return "Set up login"
    }

    private var traktStatusColor: Color {
        traktDetail.hasPrefix("Connected") ? Theme.Colors.success : Theme.Colors.textTertiary
    }

    private var realDebridDetail: String {
        KeychainStore.shared.realDebridToken == nil ? "Log in" : "Connected · Log out"
    }

    private var realDebridStatusColor: Color {
        KeychainStore.shared.realDebridToken == nil ? Theme.Colors.textTertiary : Theme.Colors.success
    }

    private func credentialRow(icon: String,
                               color: Color,
                               title: String,
                               subtitle: String,
                               text: Binding<String>,
                               isPresent: Bool,
                               externalURL: String) -> some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            HStack(alignment: .top, spacing: SettingsMetrics.rowSpacing) {
                SettingsIconTile(systemImage: icon, color: color)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.appFont(SettingsMetrics.title, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        if isPresent {
                            Label("Set", systemImage: "checkmark.circle.fill")
                                .font(.appFont(SettingsMetrics.header, weight: .semibold))
                                .foregroundStyle(Theme.Colors.success)
                        }
                    }
                    Text(subtitle)
                        .font(.appFont(SettingsMetrics.header))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button {
                    if let url = URL(string: externalURL) { openURL(url) }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.appFont(SettingsMetrics.chevron, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.accent)
                .accessibilityLabel("Open \(title) key page")
            }

            SecureField(isPresent ? "Stored" : "Paste key", text: text)
                .textFieldStyle(.plain)
                .font(.appFont(SettingsMetrics.detail))
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, SettingsMetrics.rowSpacing)
                .padding(.vertical, SettingsMetrics.rowVPad)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: SettingsMetrics.tileRadius, style: .continuous))
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .textSelection(.enabled)
                #endif
        }
        .padding(.horizontal, SettingsMetrics.rowSpacing + 2)
        .padding(.vertical, SettingsMetrics.rowVPad)
    }

    private var saveRow: some View {
        Button {
            save()
        } label: {
            SettingsRow(
                icon: savedFlash ? "checkmark.circle.fill" : "key.fill",
                color: savedFlash ? .green : .gray,
                title: savedFlash ? "Saved" : "Save API Keys",
                detail: hasInput ? nil : "No changes",
                showsChevron: false,
                tint: hasInput ? nil : Theme.Colors.textTertiary
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasInput)
        .opacity(hasInput ? 1 : 0.65)
    }

    private var hasInput: Bool {
        ![tmdbKey, openSubtitlesKey, omdbKey]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func save() {
        let tmdb = tmdbKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let openSubtitles = openSubtitlesKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let omdb = omdbKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if !tmdb.isEmpty { config.set(tmdb, for: .tmdbAPIKey) }
        if !openSubtitles.isEmpty { config.set(openSubtitles, for: .openSubtitlesAPIKey) }
        if !omdb.isEmpty { config.set(omdb, for: .omdbAPIKey) }

        tmdbKey = ""
        openSubtitlesKey = ""
        omdbKey = ""
        ToastCenter.shared.show("API keys saved", systemImage: "key.fill")
        savedFlash = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { savedFlash = false }
        }
    }
}

private struct NovaTrackerDashboardView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var stats: NovaTrackerStats?
    @State private var activity: [NovaTrackerActivity] = []
    @State private var lists: [NovaTrackerList] = []
    @State private var newListName = ""
    @State private var loading = true
    #if os(iOS)
    @State private var exportDocument: NovaTrackerBackupDocument?
    @State private var exporting = false
    #endif

    var body: some View {
        SettingsScreen(title: "Nova Tracker") {
            SettingsGroup(header: "Overview", footer: "Synced privately across your Nova devices.", rows: [AnyView(overview)])
            SettingsGroup(header: "Custom Lists", footer: "Make focused queues without changing watch status.", rows: listRows)
            SettingsGroup(header: "Recent Activity", footer: "The latest status, rating and playback changes.", rows: activityRows)
            SettingsGroup(header: "Portable Backup", footer: "Export a private JSON copy you control.", rows: [AnyView(backupButton)])
        }
        .task { await reload() }
        .refreshable { await reload() }
        #if os(iOS)
        .fileExporter(isPresented: $exporting,
                      document: exportDocument,
                      contentType: .json,
                      defaultFilename: "Nova-Tracker-Backup") { result in
            if case .failure = result { ToastCenter.shared.show("Backup could not be saved", systemImage: "exclamationmark.triangle") }
        }
        #endif
    }

    private var overview: some View {
        Group {
            if let stats {
                HStack(spacing: 12) {
                    trackerMetric("Watching", stats.watching)
                    trackerMetric("Watchlist", stats.watchlist)
                    trackerMetric("Completed", stats.completed)
                    trackerMetric("Rated", stats.rated)
                }
                .padding(.vertical, 8)
            } else {
                HStack { ProgressView(); Text(loading ? "Connecting…" : "Tracker unavailable") }
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.horizontal, SettingsMetrics.rowSpacing)
    }

    private func trackerMetric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)").font(.appFont(24, weight: .bold)).foregroundStyle(Theme.Colors.accent)
            Text(title).font(.appFont(SettingsMetrics.header)).foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var listRows: [AnyView] {
        var rows = lists.map { list in
            AnyView(SettingsRow(icon: "list.bullet", color: Theme.Colors.iconSilver,
                                title: list.name, detail: "\(list.itemCount) titles", showsChevron: false))
        }
        rows.append(AnyView(HStack {
            TextField("New list name", text: $newListName)
                .textFieldStyle(.plain)
            Button("Create") { Task { await createList() } }
                .buttonStyle(.borderedProminent)
                .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.padding(.horizontal, SettingsMetrics.rowSpacing).padding(.vertical, 8)))
        return rows
    }

    private var activityRows: [AnyView] {
        if activity.isEmpty {
            return [AnyView(SettingsRow(icon: "clock", color: Theme.Colors.iconSilver,
                                       title: "No activity yet", detail: "Play, rate or track a title to begin", showsChevron: false))]
        }
        return activity.prefix(20).map { item in
            AnyView(SettingsRow(icon: activityIcon(item.kind), color: Theme.Colors.iconSilver,
                                title: item.title ?? "Tracked title",
                                detail: item.kind.replacingOccurrences(of: "_", with: " ").capitalized,
                                showsChevron: false))
        }
    }

    private var backupButton: some View {
        Button {
            Task {
                guard let data = await env.novaTracker.portableBackup() else {
                    ToastCenter.shared.show("Backup unavailable", systemImage: "exclamationmark.triangle")
                    return
                }
                #if os(iOS)
                exportDocument = NovaTrackerBackupDocument(data: data)
                exporting = true
                #else
                ToastCenter.shared.show("Backup ready on iPhone or iPad", systemImage: "checkmark.circle")
                #endif
            }
        } label: {
            SettingsRow(icon: "square.and.arrow.up", color: Theme.Colors.iconRed,
                        title: "Export Tracker Backup", detail: "Statuses, ratings, playback and lists", showsChevron: false)
        }
        .buttonStyle(.plain)
    }

    private func reload() async {
        loading = true
        async let loadedStats = env.novaTracker.trackerStats()
        async let loadedActivity = env.novaTracker.recentActivity()
        async let loadedLists = env.novaTracker.customLists()
        let result = await (loadedStats, loadedActivity, loadedLists)
        stats = result.0; activity = result.1; lists = result.2; loading = false
    }

    private func createList() async {
        let name = newListName
        guard await env.novaTracker.createCustomList(named: name) else {
            ToastCenter.shared.show("List could not be created", systemImage: "exclamationmark.triangle")
            return
        }
        newListName = ""
        lists = await env.novaTracker.customLists()
    }

    private func activityIcon(_ kind: String) -> String {
        if kind == "rating" { return "star.fill" }
        if kind.hasPrefix("scrobble") { return "play.circle.fill" }
        return "checkmark.circle.fill"
    }
}

#if os(iOS)
private struct NovaTrackerBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
#endif
