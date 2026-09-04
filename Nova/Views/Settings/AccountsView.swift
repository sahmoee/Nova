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
import ZIPFoundation
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
    @State private var choosingTraktArchive = false
    @State private var traktPreview: TraktArchivePreview?
    @State private var importingTraktArchive = false
    #endif

    var body: some View {
        SettingsScreen(title: "Nova Tracker") {
            SettingsGroup(header: "Overview", footer: "Synced privately across your Nova devices.", rows: [AnyView(overview)])
            SettingsGroup(header: "Custom Lists", footer: "Make focused queues without changing watch status.", rows: listRows)
            SettingsGroup(header: "Recent Activity", footer: "The latest status, rating and playback changes.", rows: activityRows)
            #if os(iOS)
            SettingsGroup(header: "Import", footer: "One-way, local migration. Nova does not connect to Trakt or retain Trakt credentials.", rows: [AnyView(traktArchiveButton)])
            #endif
            SettingsGroup(header: "Portable Backup", footer: "Export a private JSON copy you control.", rows: [AnyView(backupButton)])
        }
        .task { await reload() }
        #if os(iOS)
        // Pull-to-refresh needs a drag gesture the Siri Remote doesn't have.
        .refreshable { await reload() }
        #endif
        #if os(iOS)
        .fileExporter(isPresented: $exporting,
                      document: exportDocument,
                      contentType: .json,
                      defaultFilename: "Nova-Tracker-Backup") { result in
            if case .failure = result { ToastCenter.shared.show("Backup could not be saved", systemImage: "exclamationmark.triangle") }
        }
        .fileImporter(isPresented: $choosingTraktArchive,
                      allowedContentTypes: [.zip], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await prepareTraktArchive(url) }
        }
        .sheet(item: $traktPreview) { preview in
            TraktArchivePreviewView(preview: preview,
                                    importing: importingTraktArchive,
                                    cancel: { traktPreview = nil },
                                    importAction: { Task { await importTraktArchive(preview) } })
        }
        #endif
    }

    private var overview: some View {
        Group {
            if let stats {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 12)], spacing: 12) {
                    trackerMetric("Watching", stats.watching)
                    trackerMetric("Watchlist", stats.watchlist)
                    trackerMetric("Completed", stats.completed)
                    trackerMetric("Rated", stats.rated)
                    trackerMetric("Collection", stats.collected ?? 0)
                    trackerMetric("Favorites", stats.favorites ?? 0)
                    trackerMetric("Plays", stats.plays ?? 0)
                    trackerMetric("Hours", (stats.minutesWatched ?? 0) / 60)
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
                .buttonStyle(FocusableButtonStyle(prominent: true))
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

    #if os(iOS)
    private var traktArchiveButton: some View {
        Button {
            choosingTraktArchive = true
        } label: {
            SettingsRow(icon: "archivebox.fill", color: Theme.Colors.iconRed,
                        title: "Import Trakt Data ZIP",
                        detail: "Preview and merge history, watchlist, collection and ratings",
                        showsChevron: false)
        }
        .buttonStyle(.plain)
        .disabled(importingTraktArchive)
    }

    private func prepareTraktArchive(_ url: URL) async {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let preview = try await Task.detached(priority: .userInitiated) {
                try TraktArchiveParser.parse(url: url)
            }.value
            guard !preview.items.isEmpty else {
                ToastCenter.shared.show("No supported Trakt records found", systemImage: "exclamationmark.triangle")
                return
            }
            traktPreview = preview
        } catch {
            ToastCenter.shared.show("Archive could not be read", systemImage: "exclamationmark.triangle")
        }
    }

    private func importTraktArchive(_ preview: TraktArchivePreview) async {
        guard !importingTraktArchive else { return }
        importingTraktArchive = true
        let result = await env.novaTracker.importArchive(preview.items)
        importingTraktArchive = false
        traktPreview = nil
        await reload()
        let message = result.failed == 0
            ? "Imported \(result.imported) into Nova Tracker"
            : "Imported \(result.imported); \(result.failed) could not be saved"
        ToastCenter.shared.show(message, systemImage: result.failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle")
    }
    #endif

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

private struct TraktArchivePreview: Identifiable, Sendable {
    let id = UUID()
    let items: [NovaTrackerArchiveItem]
    let filesRead: Int
    var completed: Int { items.filter { $0.status == "completed" }.count }
    var watchlist: Int { items.filter { $0.status == "plantowatch" }.count }
    var rated: Int { items.filter { $0.rating != nil }.count }
}

private struct TraktArchivePreviewView: View {
    let preview: TraktArchivePreview
    let importing: Bool
    let cancel: () -> Void
    let importAction: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Archive Summary") {
                    LabeledContent("Supported titles", value: "\(preview.items.count)")
                    LabeledContent("Completed/history", value: "\(preview.completed)")
                    LabeledContent("Watchlist/collection", value: "\(preview.watchlist)")
                    LabeledContent("Ratings", value: "\(preview.rated)")
                    LabeledContent("Data files read", value: "\(preview.filesRead)")
                }
                Section {
                    Text("Duplicates are merged by IMDb or TMDB ID. Existing Nova Tracker records are updated, not duplicated. The ZIP stays on your device and is not uploaded.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Import Trakt Archive")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel).disabled(importing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(importing ? "Importing…" : "Import", action: importAction)
                        .disabled(importing)
                }
            }
            .overlay { if importing { ProgressView().controlSize(.large) } }
        }
    }
}

private enum TraktArchiveParser {
    enum ParseError: Error { case invalidArchive }

    static func parse(url: URL) throws -> TraktArchivePreview {
        let archive = try Archive(url: url, accessMode: .read)
        var merged: [String: NovaTrackerArchiveItem] = [:]
        var filesRead = 0
        for entry in archive {
            let lower = entry.path.lowercased()
            guard lower.hasSuffix(".json") || lower.hasSuffix(".csv"),
                  entry.uncompressedSize <= 50_000_000 else { continue }
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            let rows = lower.hasSuffix(".json")
                ? parseJSON(data, path: lower)
                : parseCSV(data, path: lower)
            for row in rows { merge(row, into: &merged) }
            filesRead += 1
        }
        return TraktArchivePreview(items: merged.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending },
                                   filesRead: filesRead)
    }

    private static func parseJSON(_ data: Data, path: String) -> [NovaTrackerArchiveItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var rows: [NovaTrackerArchiveItem] = []
        walk(root, path: path, rows: &rows)
        return rows
    }

    private static func walk(_ value: Any, path: String, rows: inout [NovaTrackerArchiveItem]) {
        if let array = value as? [Any] {
            for child in array { walk(child, path: path, rows: &rows) }
            return
        }
        guard let object = value as? [String: Any] else { return }
        if let item = item(from: object, path: path) { rows.append(item) }
        for (key, child) in object where child is [Any] {
            walk(child, path: path + "/" + key.lowercased(), rows: &rows)
        }
    }

    private static func item(from wrapper: [String: Any], path: String) -> NovaTrackerArchiveItem? {
        let entity: [String: Any]
        let type: ContentType
        if let movie = wrapper["movie"] as? [String: Any] { entity = movie; type = .movie }
        else if let show = wrapper["show"] as? [String: Any] { entity = show; type = .series }
        else if let episode = wrapper["episode"] as? [String: Any] { entity = episode; type = .series }
        else {
            entity = wrapper
            let raw = string(wrapper["type"] ?? wrapper["media_type"])?.lowercased() ?? ""
            type = raw.contains("movie") ? .movie : .series
        }
        guard let title = string(entity["title"] ?? wrapper["title"]), !title.isEmpty else { return nil }
        let ids = (entity["ids"] as? [String: Any]) ?? (wrapper["ids"] as? [String: Any]) ?? [:]
        let imdb = string(ids["imdb"] ?? entity["imdb"] ?? wrapper["imdb"])
        let tmdb = integer(ids["tmdb"] ?? entity["tmdb"] ?? wrapper["tmdb"])
        guard imdb != nil || tmdb != nil else { return nil }
        let lower = path.lowercased()
        let watched = lower.contains("history") || lower.contains("watched") || wrapper["watched_at"] != nil
        let isCollection = lower.contains("collection")
        let planned = lower.contains("watchlist") || wrapper["listed_at"] != nil
        let rating = integer(wrapper["rating"] ?? entity["rating"]).map { min(max($0, 1), 10) }
        return NovaTrackerArchiveItem(title: title,
                                      year: integer(entity["year"] ?? wrapper["year"]),
                                      type: type, imdb: imdb, tmdb: tmdb,
                                      status: watched ? "completed" : (planned ? "plantowatch" : nil),
                                      rating: rating, collected: isCollection)
    }

    private static func parseCSV(_ data: Data, path: String) -> [NovaTrackerArchiveItem] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let records = csvRecords(text)
        guard let headers = records.first?.map({ $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }) else { return [] }
        return records.dropFirst().compactMap { values in
            var row: [String: String] = [:]
            for (index, header) in headers.enumerated() where index < values.count { row[header] = values[index] }
            guard let title = row["title"], !title.isEmpty else { return nil }
            let imdb = nonempty(row["imdb"] ?? row["imdb_id"])
            let tmdb = Int(row["tmdb"] ?? row["tmdb_id"] ?? "")
            guard imdb != nil || tmdb != nil else { return nil }
            let rawType = (row["type"] ?? row["media_type"] ?? "").lowercased()
            let lower = path.lowercased()
            let isCollection = lower.contains("collection")
            let status = (lower.contains("history") || lower.contains("watched")) ? "completed"
                : (lower.contains("watchlist") ? "plantowatch" : nil)
            return NovaTrackerArchiveItem(title: title, year: Int(row["year"] ?? ""),
                                          type: rawType.contains("movie") ? .movie : .series,
                                          imdb: imdb, tmdb: tmdb, status: status,
                                          rating: Int(row["rating"] ?? "").map { min(max($0, 1), 10) },
                                          collected: isCollection)
        }
    }

    private static func csvRecords(_ text: String) -> [[String]] {
        var records: [[String]] = [], record: [String] = [], field = "", quoted = false
        var index = text.startIndex
        while index < text.endIndex {
            let c = text[index]
            if c == "\"" {
                let next = text.index(after: index)
                if quoted, next < text.endIndex, text[next] == "\"" { field.append("\""); index = next }
                else { quoted.toggle() }
            } else if c == ",", !quoted { record.append(field); field = "" }
            else if (c == "\n" || c == "\r"), !quoted {
                if c == "\r" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\n" { index = next }
                }
                record.append(field); field = ""
                if record.contains(where: { !$0.isEmpty }) { records.append(record) }
                record = []
            } else { field.append(c) }
            index = text.index(after: index)
        }
        record.append(field)
        if record.contains(where: { !$0.isEmpty }) { records.append(record) }
        return records
    }

    private static func merge(_ item: NovaTrackerArchiveItem,
                              into merged: inout [String: NovaTrackerArchiveItem]) {
        let key = item.imdb.map { "imdb:\($0.lowercased())" }
            ?? item.tmdb.map { "tmdb:\($0):\(item.type == .movie ? "movie" : "show")" }
        guard let key else { return }
        if var old = merged[key] {
            if item.status == "completed" || old.status == nil { old.status = item.status }
            if let rating = item.rating { old.rating = rating }
            merged[key] = old
        } else { merged[key] = item }
    }

    private static func string(_ value: Any?) -> String? {
        if let string = value as? String { return nonempty(string) }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }
    private static func nonempty(_ value: String?) -> String? {
        let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned?.isEmpty == false ? cleaned : nil
    }
}
#endif
