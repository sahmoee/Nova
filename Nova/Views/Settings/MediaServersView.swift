import SwiftUI

// Sonarr remains authoritative for acquisition. Nova keeps only the server address and
// a short-lived dashboard snapshot; the API key stays in Keychain.
@MainActor
final class SonarrStore: ObservableObject {
    struct Configuration: Codable, Equatable {
        var address: String = "http://"
    }
    struct Series: Decodable, Identifiable {
        let id: Int
        let title: String
        let monitored: Bool
        let statistics: Statistics?
        struct Statistics: Decodable { let episodeCount: Int?; let episodeFileCount: Int? }
    }
    struct Episode: Decodable, Identifiable {
        let id: Int
        let seriesId: Int
        let seasonNumber: Int
        let episodeNumber: Int
        let title: String
        let airDateUtc: Date?
        let hasFile: Bool
        let monitored: Bool
    }
    struct QueuePage: Decodable {
        let totalRecords: Int
        let records: [QueueItem]
    }
    struct QueueItem: Decodable, Identifiable {
        let id: Int
        let title: String?
        let status: String?
        let trackedDownloadStatus: String?
        let errorMessage: String?
    }
    struct Status: Decodable { let appName: String?; let version: String? }

    @Published private(set) var configuration = Configuration()
    @Published private(set) var series: [Series] = []
    @Published private(set) var episodes: [Episode] = []
    @Published private(set) var queue: [QueueItem] = []
    @Published private(set) var version: String?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastRefresh: Date?

    private static let keyAccount = "sonarr.apiKey"
    private static let configKey = "nova.sonarr.configuration.v1"
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.configKey),
           let saved = try? JSONDecoder().decode(Configuration.self, from: data) {
            configuration = saved
        }
    }

    var isConfigured: Bool { baseURL != nil && KeychainStore.shared.get(Self.keyAccount)?.isEmpty == false }
    var monitoredSeriesCount: Int { series.filter(\.monitored).count }
    var missingEpisodeCount: Int {
        series.filter(\.monitored).reduce(0) { value, item in
            value + max(0, (item.statistics?.episodeCount ?? 0) - (item.statistics?.episodeFileCount ?? 0))
        }
    }
    var warningCount: Int {
        queue.filter { ($0.trackedDownloadStatus ?? "").lowercased() == "warning" || $0.errorMessage?.isEmpty == false }.count
    }
    var baseURL: URL? {
        guard var components = URLComponents(string: configuration.address.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.host != nil else { return nil }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return components.url
    }

    func save(address: String, apiKey: String) throws {
        guard URLComponents(string: address)?.host != nil else { throw URLError(.badURL) }
        configuration = Configuration(address: address.trimmingCharacters(in: .whitespacesAndNewlines))
        if let data = try? JSONEncoder().encode(configuration) { UserDefaults.standard.set(data, forKey: Self.configKey) }
        if !apiKey.isEmpty { try KeychainStore.shared.set(apiKey, for: Self.keyAccount) }
    }

    func disconnect() {
        try? KeychainStore.shared.delete(Self.keyAccount)
        UserDefaults.standard.removeObject(forKey: Self.configKey)
        configuration = Configuration(); series = []; episodes = []; queue = []; version = nil; lastRefresh = nil
    }

    func refresh() async {
        guard !isLoading else { return }
        guard let baseURL, let key = KeychainStore.shared.get(Self.keyAccount), !key.isEmpty else {
            errorMessage = "Enter your Sonarr address and API key first."; return
        }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            async let status: Status = request("system/status", baseURL: baseURL, key: key)
            async let loadedSeries: [Series] = request("series", baseURL: baseURL, key: key)
            async let loadedEpisodes: [Episode] = request(calendarPath(), baseURL: baseURL, key: key)
            async let loadedQueue: QueuePage = request("queue?page=1&pageSize=50&includeUnknownSeriesItems=true", baseURL: baseURL, key: key)
            let result = try await (status, loadedSeries, loadedEpisodes, loadedQueue)
            version = result.0.version
            series = result.1.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            episodes = result.2.filter(\.monitored).sorted { ($0.airDateUtc ?? .distantFuture) < ($1.airDateUtc ?? .distantFuture) }
            queue = result.3.records
            lastRefresh = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func calendarPath() -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]
        let start = formatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        let end = formatter.string(from: Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date())
        return "calendar?start=\(start)&end=\(end)&includeSeries=false&includeEpisodeFile=false"
    }

    private func request<T: Decodable>(_ path: String, baseURL: URL, key: String) async throws -> T {
        let pieces = path.split(separator: "?", maxSplits: 1).map(String.init)
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/v3").appendingPathComponent(pieces[0]),
            resolvingAgainstBaseURL: false
        )
        if pieces.count == 2 { components?.percentEncodedQuery = pieces[1] }
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(T.self, from: data)
    }
}

struct SonarrView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var editing = false

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    ScreenHeader(title: "Sonarr", subtitle: "See upcoming and missing episodes without leaving Nova.")
                    if env.sonarr.isConfigured { dashboard } else { setupPrompt }
                }
                .padding(.horizontal, Theme.Spacing.edge).padding(.bottom, Theme.Spacing.xl)
                .frame(maxWidth: Theme.contentMaxWidth(1100), alignment: .leading).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Sonarr")
        .toolbar { ToolbarItem { Button { editing = true } label: { Image(systemName: "gearshape") } } }
        .sheet(isPresented: $editing) { SonarrEditor() }
        .task { if env.sonarr.isConfigured && env.sonarr.lastRefresh == nil { await env.sonarr.refresh() } }
    }

    private var setupPrompt: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "calendar.badge.clock").font(.appFont(42)).foregroundStyle(Theme.Colors.textSecondary)
            Text("Connect your Sonarr server").font(Theme.Font.sectionTitle())
            Text("Nova reads series, calendar, missing totals, and queue health. Sonarr continues to manage downloads and quality upgrades.")
                .font(.appFont(16)).foregroundStyle(Theme.Colors.textSecondary).multilineTextAlignment(.center)
            Button("Connect Sonarr") { editing = true }.buttonStyle(NovaRowButtonStyle())
        }.frame(maxWidth: .infinity).padding(Theme.Spacing.lg).refinedCardBackground()
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.sm) {
                metric("Monitored", env.sonarr.monitoredSeriesCount, "tv")
                metric("Missing", env.sonarr.missingEpisodeCount, "exclamationmark.circle")
                metric("Queue", env.sonarr.queue.count, "arrow.down.circle")
                metric("Warnings", env.sonarr.warningCount, "exclamationmark.triangle")
            }
            .frame(maxWidth: .infinity)
            HStack {
                Button { Task { await env.sonarr.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .buttonStyle(NovaChipButtonStyle()).disabled(env.sonarr.isLoading)
                if let url = env.sonarr.baseURL { Link(destination: url) { Label("Open Sonarr", systemImage: "safari") }.buttonStyle(NovaChipButtonStyle()) }
                if env.sonarr.isLoading { ProgressView() }
            }
            if let error = env.sonarr.errorMessage { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.Colors.error) }
            if !env.sonarr.episodes.isEmpty {
                Text("Next 30 Days").font(Theme.Font.sectionTitle())
                ForEach(env.sonarr.episodes.prefix(30)) { episode in
                    let show = env.sonarr.series.first { $0.id == episode.seriesId }?.title ?? "Series"
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(show).font(.appFont(17, weight: .semibold))
                            Text("S\(episode.seasonNumber) E\(episode.episodeNumber) · \(episode.title)").font(.appFont(14)).foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        if let date = episode.airDateUtc { Text(date, style: .date).font(.appFont(14)).foregroundStyle(Theme.Colors.textTertiary) }
                    }.padding(Theme.Spacing.md).refinedCardBackground()
                }
            }
            if !env.sonarr.queue.isEmpty {
                Text("Activity").font(Theme.Font.sectionTitle())
                ForEach(env.sonarr.queue.prefix(20)) { item in
                    HStack { Image(systemName: item.errorMessage == nil ? "arrow.down.circle" : "exclamationmark.triangle")
                        Text(item.title ?? "Queued episode").lineLimit(2); Spacer(); Text(item.status ?? "Queued").foregroundStyle(Theme.Colors.textSecondary) }
                    .padding(Theme.Spacing.md).refinedCardBackground()
                }
            }
        }
    }

    private func metric(_ title: String, _ value: Int, _ icon: String) -> some View {
        VStack(spacing: 5) { Image(systemName: icon); Text("\(value)").font(.appFont(24, weight: .bold)); Text(title).font(.appFont(12)).foregroundStyle(Theme.Colors.textSecondary) }
            .frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.md).refinedCardBackground()
    }
}

private struct SonarrEditor: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var address = "http://"
    @State private var apiKey = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Server address", text: $address).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(env.sonarr.isConfigured ? "New API key (optional)" : "API key", text: $apiKey)
                    Text("Find the API key in Sonarr → Settings → General → Security. It is stored in Keychain.")
                }
                if env.sonarr.isConfigured {
                    Section { Button("Disconnect Sonarr", role: .destructive) { env.sonarr.disconnect(); dismiss() } }
                }
                if let error { Text(error).foregroundStyle(Theme.Colors.error) }
            }
            .navigationTitle("Sonarr Connection")
            .onAppear { address = env.sonarr.configuration.address }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save & Test") { Task { await save() } } }
            }
        }
    }

    private func save() async {
        do {
            try env.sonarr.save(address: address, apiKey: apiKey)
            await env.sonarr.refresh()
            if let message = env.sonarr.errorMessage { error = message } else { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}

struct MediaServersView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var editing: MediaServerConnection?
    @State private var addingKind: MediaServerKind?
    @State private var pendingRemoval: MediaServerConnection?

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    ScreenHeader(title: "Media Servers",
                        subtitle: "Index personal libraries from Jellyfin, Plex, or Emby into Nova.")

                    if env.mediaServers.connections.isEmpty { emptyState }
                    ForEach(env.mediaServers.connections) { connection in serverCard(connection) }

                    Menu {
                        ForEach(MediaServerKind.allCases) { kind in
                            Button { addingKind = kind } label: { Label(kind.title, systemImage: kind.symbol) }
                        }
                    } label: {
                        Label("Add Media Server", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NovaRowButtonStyle())

                    if let message = env.mediaServers.statusMessage {
                        Text(message).font(.appFont(15)).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.bottom, Theme.Spacing.xl)
                .frame(maxWidth: Theme.contentMaxWidth(1100), alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Media Servers")
        .sheet(item: $addingKind) { kind in MediaServerEditor(kind: kind) }
        .sheet(item: $editing) { connection in MediaServerEditor(kind: connection.kind, existing: connection) }
        .alert("Remove Media Server?", isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("Remove Server and Items", role: .destructive) {
                if let pendingRemoval { env.mediaServers.remove(pendingRemoval, removeIndexedItems: true) }
                pendingRemoval = nil
            }
            Button("Remove Server Only") {
                if let pendingRemoval { env.mediaServers.remove(pendingRemoval, removeIndexedItems: false) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { Text("The server credentials will be removed from Keychain.") }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "play.tv").font(.appFont(42)).foregroundStyle(Theme.Colors.accent)
            Text("Bring your server library into Nova").font(Theme.Font.sectionTitle()).foregroundStyle(Theme.Colors.textPrimary)
            Text("Nova keeps a fast local index for Home, Search, Library, Spotlight, and offline browsing. Your server remains the source of the media.")
                .font(.appFont(16)).foregroundStyle(Theme.Colors.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(Theme.Spacing.lg).refinedCardBackground()
    }

    private func serverCard(_ connection: MediaServerConnection) -> some View {
        let syncing = env.mediaServers.syncingIDs.contains(connection.id)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: connection.kind.symbol).foregroundStyle(Theme.Colors.accent).font(.appFont(26))
                VStack(alignment: .leading, spacing: 3) {
                    Text(connection.name).font(.appFont(19, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                    Text(connection.baseURL.host ?? connection.baseURL.absoluteString)
                        .font(.appFont(14)).foregroundStyle(Theme.Colors.textTertiary).lineLimit(1)
                }
                Spacer()
                if syncing { ProgressView().tint(Theme.Colors.accent) }
                else { Text("\(connection.indexedItemCount)").font(.appFont(17, weight: .semibold)).foregroundStyle(Theme.Colors.textSecondary) }
            }
            if let date = connection.lastIndexed {
                Text("Indexed \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.appFont(13)).foregroundStyle(Theme.Colors.textTertiary)
            }
            if let error = connection.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.appFont(14)).foregroundStyle(Theme.Colors.error)
            }
            HStack {
                Button { Task { try? await env.mediaServers.sync(connection.id) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }.buttonStyle(NovaChipButtonStyle()).disabled(syncing)
                Button { editing = connection } label: { Label("Edit", systemImage: "slider.horizontal.3") }
                    .buttonStyle(NovaChipButtonStyle()).disabled(syncing)
                Button(role: .destructive) { pendingRemoval = connection } label: { Label("Remove", systemImage: "trash") }
                    .buttonStyle(NovaChipButtonStyle()).disabled(syncing)
            }
        }
        .padding(Theme.Spacing.md).refinedCardBackground()
    }
}

private struct MediaServerEditor: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let existing: MediaServerConnection?
    @State private var kind: MediaServerKind
    @State private var name: String
    @State private var address: String
    @State private var username: String
    @State private var password = ""
    @State private var token = ""
    @State private var selectedLibraries: Set<String>
    @State private var autoRefresh: Bool
    @State private var working = false
    @State private var error: String?

    init(kind: MediaServerKind, existing: MediaServerConnection? = nil) {
        self.existing = existing
        _kind = State(initialValue: existing?.kind ?? kind)
        _name = State(initialValue: existing?.name ?? kind.title)
        _address = State(initialValue: existing?.baseURL.absoluteString ?? "http://")
        _username = State(initialValue: existing?.username ?? "")
        _selectedLibraries = State(initialValue: existing?.selectedLibraryIDs ?? [])
        _autoRefresh = State(initialValue: existing?.autoRefresh ?? true)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Picker("Server", selection: $kind) {
                            ForEach(MediaServerKind.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).disabled(existing != nil)
                        field("Name", text: $name, content: .name)
                        field("Server address", text: $address, content: .URL)
                        if kind != .plex { field("Username", text: $username, content: .username) }
                        if kind == .plex {
                            secureField("Plex token", text: $token)
                            Text("Use an access token from your own Plex account. Nova stores it in Keychain.")
                                .font(.appFont(13)).foregroundStyle(Theme.Colors.textTertiary)
                        } else if existing == nil {
                            secureField("Password", text: $password)
                        } else {
                            secureField("New token or password (optional)", text: $token)
                        }
                        Toggle("Refresh this server automatically", isOn: $autoRefresh).tint(Theme.Colors.accent)

                        if let existing, !existing.availableLibraries.isEmpty {
                            Text("Libraries").font(Theme.Font.sectionTitle()).foregroundStyle(Theme.Colors.textPrimary)
                            ForEach(existing.availableLibraries) { library in
                                Toggle(isOn: Binding(get: { selectedLibraries.contains(library.id) }, set: { on in
                                    if on { selectedLibraries.insert(library.id) } else { selectedLibraries.remove(library.id) }
                                })) { Text(library.name).foregroundStyle(Theme.Colors.textPrimary) }
                                    .tint(Theme.Colors.accent)
                            }
                        }
                        if let error { Text(error).font(.appFont(14)).foregroundStyle(Theme.Colors.error) }
                    }
                    .padding(Theme.Spacing.edge)
                }
            }
            .navigationTitle(existing == nil ? "Add \(kind.title)" : "Edit \(kind.title)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(working ? "Connecting…" : "Save & Index") { Task { await save() } }
                        .disabled(working || URL(string: address)?.host == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func field(_ prompt: String, text: Binding<String>, content: UITextContentType?) -> some View {
        TextField(prompt, text: text).textContentType(content).textInputAutocapitalization(.never)
            .autocorrectionDisabled().padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
    }
    private func secureField(_ prompt: String, text: Binding<String>) -> some View {
        SecureField(prompt, text: text).textContentType(.password)
            .padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
    }

    private func save() async {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        working = true; error = nil; defer { working = false }
        var draft = existing ?? MediaServerConnection(kind: kind, name: name, baseURL: url)
        draft.kind = kind; draft.name = name; draft.baseURL = url; draft.username = username
        draft.selectedLibraryIDs = selectedLibraries; draft.autoRefresh = autoRefresh
        do {
            _ = try await env.mediaServers.connect(draft, password: password, token: token)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
