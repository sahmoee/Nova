import SwiftUI

// Sonarr remains authoritative for acquisition. Nova keeps only the server address and
// a short-lived dashboard snapshot; the API key stays in Keychain.
@MainActor
final class SonarrStore: ObservableObject {
    struct Configuration: Codable, Equatable {
        var address: String = "http://"
    }
    typealias Series = SonarrSeries
    typealias Episode = SonarrEpisode
    typealias QueueItem = SonarrQueueItem
    struct QueuePage: Decodable {
        let totalRecords: Int
        let records: [QueueItem]
    }
    struct Status: Decodable { let appName: String?; let version: String? }

    @Published private(set) var configuration = Configuration()
    @Published private(set) var series: [Series] = []
    @Published private(set) var episodes: [Episode] = []
    @Published private(set) var queue: [QueueItem] = []
    @Published private(set) var queueTotalRecords = 0
    @Published private(set) var version: String?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var retryAfter: Date?

    private static let keyAccount = "sonarr.apiKey"
    private static let configKey = "nova.sonarr.configuration.v1"
    private var generation = UUID()
    private let decoder = SonarrDashboardPolicy.decoder()

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.configKey),
           let saved = try? JSONDecoder().decode(Configuration.self, from: data) {
            configuration = saved
        }
    }

    var isConfigured: Bool { baseURL != nil && KeychainStore.shared.get(Self.keyAccount)?.isEmpty == false }
    var monitoredSeriesCount: Int { series.filter(\.monitored).count }
    var missingEpisodeCount: Int { series.filter(\.monitored).compactMap(\.missing).reduce(0, +) }
    var missingStatisticsCount: Int { series.filter { $0.monitored && $0.missing == nil }.count }
    var warningCount: Int { queue.filter(\.hasWarning).count }
    var baseURL: URL? { SonarrDashboardPolicy.serverURL(configuration.address) }

    func save(address: String, apiKey: String) throws {
        guard let url = SonarrDashboardPolicy.serverURL(address) else {
            throw SonarrConnectionError.message("Use an HTTP or HTTPS server address without a username, password, query, or fragment.")
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let sameServer = url == baseURL
        guard !key.isEmpty || (sameServer && isConfigured) else {
            throw SonarrConnectionError.message("Enter the API key for this server. Changing servers requires its own key.")
        }
        let next = Configuration(address: url.absoluteString)
        let data = try JSONEncoder().encode(next)
        if !key.isEmpty { try KeychainStore.shared.set(key, for: Self.keyAccount) }
        generation = UUID(); isLoading = false
        UserDefaults.standard.set(data, forKey: Self.configKey)
        configuration = next
        if !sameServer || !key.isEmpty {
            let cooldown = sameServer ? retryAfter : nil
            clearSnapshot(); retryAfter = cooldown
        } else { errorMessage = nil }
    }

    func disconnect() throws {
        try KeychainStore.shared.delete(Self.keyAccount)
        generation = UUID(); isLoading = false
        UserDefaults.standard.removeObject(forKey: Self.configKey)
        configuration = Configuration()
        clearSnapshot()
    }

    private func clearSnapshot() {
        series = []; episodes = []; queue = []; version = nil; lastRefresh = nil
        queueTotalRecords = 0; errorMessage = nil; retryAfter = nil
    }

    func refresh() async {
        guard !isLoading else { return }
        if let retryAfter, retryAfter > Date() {
            errorMessage = "Sonarr requested a cooldown. Try again after \(retryAfter.formatted(date: .omitted, time: .standard))."
            return
        }
        guard let baseURL, let key = KeychainStore.shared.get(Self.keyAccount), !key.isEmpty else {
            errorMessage = "Enter your Sonarr address and API key first."; return
        }
        let requestGeneration = generation
        isLoading = true; errorMessage = nil
        defer { if generation == requestGeneration { isLoading = false } }
        do {
            async let status: Status = request("system/status", baseURL: baseURL, key: key, generation: requestGeneration)
            async let loadedSeries: [Series] = request("series", baseURL: baseURL, key: key, generation: requestGeneration)
            async let loadedEpisodes: [Episode] = request(calendarPath(), baseURL: baseURL, key: key, generation: requestGeneration)
            async let loadedQueue: QueuePage = request("queue?page=1&pageSize=50&includeUnknownSeriesItems=true", baseURL: baseURL, key: key, generation: requestGeneration)
            let result = try await (status, loadedSeries, loadedEpisodes, loadedQueue)
            try Task.checkCancellation()
            guard generation == requestGeneration else { return }
            version = result.0.version
            series = result.1.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            episodes = result.2.sorted { ($0.airDateUtc ?? .distantFuture) < ($1.airDateUtc ?? .distantFuture) }
            queue = result.3.records
            queueTotalRecords = max(result.3.totalRecords, queue.count)
            lastRefresh = Date()
        } catch is CancellationError {
            // Keep the last successful snapshot when a view-owned refresh is cancelled.
        } catch {
            guard !Task.isCancelled, generation == requestGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func calendarPath() -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]
        let start = formatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        let end = formatter.string(from: Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date())
        return "calendar?start=\(start)&end=\(end)&unmonitored=true&includeSeries=false&includeEpisodeFile=false"
    }

    private func request<T: Decodable>(_ path: String, baseURL: URL, key: String, generation requestGeneration: UUID) async throws -> T {
        try Task.checkCancellation()
        guard generation == requestGeneration else { throw CancellationError() }
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
        try Task.checkCancellation()
        guard generation == requestGeneration else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            switch http.statusCode {
            case 401, 403: throw SonarrConnectionError.message("Sonarr refused access. Check the address and API key in Connection settings.")
            case 404: throw SonarrConnectionError.message("Sonarr's v3 API was not found. Check the server address and any reverse-proxy path.")
            case 429:
                let delay = MediaReliabilityPolicy.retryAfter(http.value(forHTTPHeaderField: "Retry-After")) ?? 30
                let until = Date().addingTimeInterval(delay)
                retryAfter = max(retryAfter ?? .distantPast, until)
                throw SonarrConnectionError.message("Sonarr is limiting requests. Wait before refreshing again.")
            default: throw SonarrConnectionError.message("Sonarr could not complete the request (HTTP \(http.statusCode)). Your last successful snapshot is unchanged.")
            }
        }
        return try decoder.decode(T.self, from: data)
    }
}

private enum SonarrConnectionError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}

struct SonarrView: View {
    @EnvironmentObject private var env: AppEnvironment
    var body: some View { SonarrDashboard(store: env.sonarr) }
}

private struct SonarrDashboard: View {
    @ObservedObject var store: SonarrStore
    @State private var editing = false
    @State private var section = "Series"
    @State private var search = ""
    @State private var seriesFilter: SonarrSeriesFilter = .all
    @State private var seriesSort: SonarrSeriesSort = .title
    @State private var calendarDays = 30
    @State private var monitoring: SonarrMonitoringFilter = .monitored
    @State private var availability: SonarrFileFilter = .all
    @State private var warningsOnly = false

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    ScreenHeader(title: "Sonarr", subtitle: "Your server's series, calendar, and download status. Read only.")
                    if store.isConfigured { dashboard } else { setupPrompt }
                }
                .padding(.horizontal, Theme.Spacing.edge).padding(.bottom, Theme.Spacing.xl)
                .frame(maxWidth: Theme.contentMaxWidth(1100), alignment: .leading).frame(maxWidth: .infinity)
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { if store.isConfigured { await store.refresh() } }
            #endif
        }
        .navigationTitle("Sonarr")
        .toolbar { ToolbarItem { Button { editing = true } label: { Label("Connection", systemImage: "gearshape") } } }
        .sheet(isPresented: $editing) { SonarrEditor(store: store) }
        .task { if store.isConfigured && store.lastRefresh == nil { await store.refresh() } }
    }

    private var metricMinWidth: CGFloat {
        #if os(tvOS)
        210
        #else
        125
        #endif
    }

    private var setupPrompt: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "calendar.badge.clock").font(.appFont(42)).foregroundStyle(Theme.Colors.textSecondary)
            Text("Connect your Sonarr server").font(Theme.Font.sectionTitle())
            Text("Nova reads existing series, calendar, and queue data. Downloads and quality upgrades remain in Sonarr.")
                .font(.body).foregroundStyle(Theme.Colors.textSecondary).multilineTextAlignment(.center)
            Button("Connect Sonarr") { editing = true }.buttonStyle(NovaRowButtonStyle())
        }.frame(maxWidth: .infinity).padding(Theme.Spacing.lg).refinedCardBackground()
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: metricMinWidth), spacing: Theme.Spacing.sm)], spacing: Theme.Spacing.sm) {
                metric("Monitored", store.monitoredSeriesCount, "tv")
                metric("Missing estimate", store.missingEpisodeCount, "exclamationmark.circle")
                metric("Queue", store.queueTotalRecords, "arrow.down.circle")
                metric("Visible warnings", store.warningCount, "exclamationmark.triangle")
            }
            if store.missingStatisticsCount > 0 {
                Text("Missing totals exclude \(store.missingStatisticsCount) monitored series with unavailable statistics.")
                    .font(.footnote).foregroundStyle(Theme.Colors.textSecondary)
            }
            FlowLayout(spacing: Theme.Spacing.sm) {
                Button { Task { await store.refresh() } } label: { Label(store.isLoading ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise") }
                    .buttonStyle(NovaChipButtonStyle(providesSurface: true)).disabled(store.isLoading)
                #if os(iOS)
                if let url = store.baseURL { Link(destination: url) { Label("Open Sonarr", systemImage: "safari") }.buttonStyle(NovaChipButtonStyle(providesSurface: true)) }
                #endif
            }
            if store.isLoading { ProgressView("Reading Sonarr…").accessibilityLabel("Refreshing Sonarr dashboard") }
            if let date = store.lastRefresh {
                Text("Last successful refresh: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote).foregroundStyle(Theme.Colors.textSecondary)
            } else if !store.isLoading && store.errorMessage == nil {
                Text("Refresh to load your server's data.").foregroundStyle(Theme.Colors.textSecondary)
            }
            if let error = store.errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.Colors.error)
                    if store.lastRefresh != nil { Text("Showing the last successful snapshot; it may be out of date.").font(.footnote) }
                }
            }
            Picker("Dashboard section", selection: $section) {
                Text("Series").tag("Series"); Text("Calendar").tag("Calendar"); Text("Activity").tag("Activity")
            }.pickerStyle(.automatic)
            if section == "Calendar" { calendarContent }
            else if section == "Activity" { queueContent }
            else { seriesContent }
        }
    }

    private var seriesContent: some View {
        let results = SonarrDashboardPolicy.filterSeries(store.series, query: search, filter: seriesFilter, sort: seriesSort)
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: 8) {
                TextField("Search Sonarr series", text: $search).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("Search Sonarr series")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").frame(minWidth: 44, minHeight: 44) }
                        .buttonStyle(NovaIconButtonStyle()).accessibilityLabel("Clear series search")
                }
            }
            FlowLayout(spacing: Theme.Spacing.sm) {
                Picker("Series filter", selection: $seriesFilter) { ForEach(SonarrSeriesFilter.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Series sort", selection: $seriesSort) { ForEach(SonarrSeriesSort.allCases) { Text($0.rawValue).tag($0) } }
            }
            Text("\(results.count) of \(store.series.count) series").font(.footnote).foregroundStyle(Theme.Colors.textSecondary)
            if results.isEmpty && !store.isLoading && store.lastRefresh != nil {
                empty("No matching series", detail: "Change the filters or add series in Sonarr.")
                if !search.isEmpty || seriesFilter != .all {
                    Button("Clear series filters") { search = ""; seriesFilter = .all }.buttonStyle(NovaChipButtonStyle(providesSurface: true))
                }
            }
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(results) { item in
                    NavigationLink { SonarrSeriesDetail(series: item) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title).font(.headline)
                            Text(item.monitored ? "Monitored" : "Unmonitored").font(.subheadline)
                            if let missing = item.missing { Text("\(missing) missing · \(item.statistics?.episodeFileCount ?? 0) files").font(.footnote) }
                            else { Text("Episode statistics unavailable").font(.footnote) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(NovaRowButtonStyle()).accessibilityHint("Open episode availability details")
                }
            }
        }
    }

    private var calendarContent: some View {
        let matches = SonarrDashboardPolicy.filterEpisodes(store.episodes, days: calendarDays, monitoring: monitoring, files: availability, now: Date())
        let groups = Dictionary(grouping: matches) { Calendar.current.startOfDay(for: $0.airDateUtc ?? .distantFuture) }
        let names = Dictionary(store.series.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            FlowLayout(spacing: Theme.Spacing.sm) {
                Picker("Calendar range", selection: $calendarDays) { Text("Today").tag(1); Text("7 days").tag(7); Text("30 days").tag(30) }
                Picker("Monitoring", selection: $monitoring) { ForEach(SonarrMonitoringFilter.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Availability", selection: $availability) { ForEach(SonarrFileFilter.allCases) { Text($0.rawValue).tag($0) } }
            }
            Text("\(matches.count) episodes · times in your current time zone").font(.footnote).foregroundStyle(Theme.Colors.textSecondary)
            if matches.isEmpty && !store.isLoading && store.lastRefresh != nil {
                empty("No episodes match", detail: "Try a longer range or include unmonitored episodes.")
                Button("Reset calendar filters") { calendarDays = 30; monitoring = .all; availability = .all }.buttonStyle(NovaChipButtonStyle(providesSurface: true))
            }
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ForEach(groups.keys.sorted(), id: \.self) { day in
                    Text(day.formatted(date: .complete, time: .omitted)).font(.headline).accessibilityAddTraits(.isHeader)
                    ForEach(groups[day] ?? []) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(names[item.seriesId] ?? "Series \(item.seriesId)").font(.headline)
                            Text("S\(item.seasonNumber) E\(item.episodeNumber) · \(item.title)").font(.body)
                            if let date = item.airDateUtc { Text(date.formatted(date: .omitted, time: .shortened)).font(.subheadline) }
                            Label(item.hasFile ? "File available" : "No file yet", systemImage: item.hasFile ? "checkmark.circle" : "clock")
                            Text(item.monitored ? "Monitored" : "Unmonitored").font(.footnote)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(Theme.Spacing.md).refinedCardBackground()
                            .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var queueContent: some View {
        let results = warningsOnly ? store.queue.filter(\.hasWarning) : store.queue
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Toggle("Warnings only", isOn: $warningsOnly)
            Text("Loaded \(store.queue.count) of \(store.queueTotalRecords) queue records.")
                .font(.footnote).foregroundStyle(Theme.Colors.textSecondary)
            if store.queueTotalRecords > store.queue.count {
                Text("This dashboard shows the first 50 records. Open Sonarr to inspect the remaining queue.").font(.footnote).foregroundStyle(Theme.Colors.textSecondary)
            }
            if results.isEmpty && !store.isLoading && store.lastRefresh != nil {
                empty(warningsOnly ? "No visible warnings" : "No queued downloads", detail: warningsOnly ? "Turn off Warnings only to see all loaded records." : "Queue activity appears here when Sonarr reports it.")
            }
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(results) { item in
                    NavigationLink { SonarrQueueDetail(item: item) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(item.title ?? "Queued episode", systemImage: item.hasWarning ? "exclamationmark.triangle" : "arrow.down.circle").font(.headline)
                            Text(item.status ?? "Status unavailable").font(.subheadline)
                            if let progress = item.progress {
                                Text(progress.formatted(.percent.precision(.fractionLength(0)))).font(.footnote).monospacedDigit()
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(NovaRowButtonStyle()).accessibilityHint("Open download progress and messages")
                }
            }
        }
    }

    private func metric(_ title: String, _ value: Int, _ icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).accessibilityHidden(true)
            Text(store.lastRefresh == nil ? "—" : "\(value)").font(.title2.bold()).monospacedDigit()
            Text(title).font(.footnote).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(Theme.Spacing.md).refinedCardBackground().accessibilityElement(children: .combine)
    }
    private func empty(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline); Text(detail).font(.body).foregroundStyle(Theme.Colors.textSecondary) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(Theme.Spacing.md).refinedCardBackground()
    }
}

private struct SonarrSeriesDetail: View {
    let series: SonarrSeries
    var body: some View {
        SonarrDetailCanvas(title: series.title) {
            Label(series.monitored ? "Monitored by Sonarr" : "Unmonitored", systemImage: series.monitored ? "checkmark.circle" : "minus.circle")
            if let stats = series.statistics {
                detail("Episode files", stats.episodeFileCount.map(String.init) ?? "Unavailable")
                detail("Expected episodes", stats.episodeCount.map(String.init) ?? "Unavailable")
                detail("Missing estimate", series.missing.map(String.init) ?? "Unavailable")
                detail("Total episodes reported", stats.totalEpisodeCount.map(String.init) ?? "Unavailable")
                if let size = stats.sizeOnDisk, size >= 0 { detail("Storage on Sonarr", ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
            } else { Text("Sonarr did not return episode statistics for this series.") }
            Text("Counts are Sonarr's series statistics, not a check that Nova can play every file. The missing estimate is expected episodes minus files, with a minimum of zero. This page does not change monitoring or trigger searches.")
                .font(.footnote).foregroundStyle(Theme.Colors.textSecondary)
        }
    }
    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.subheadline).foregroundStyle(Theme.Colors.textSecondary); Text(value).font(.title3).monospacedDigit() }
            .accessibilityElement(children: .combine)
    }
}

private struct SonarrQueueDetail: View {
    let item: SonarrQueueItem
    var body: some View {
        SonarrDetailCanvas(title: item.title ?? "Queue details") {
            Text(item.status ?? "Status unavailable").font(.title3)
            if let progress = item.progress {
                ProgressView(value: progress).accessibilityLabel("Downloaded").accessibilityValue(progress.formatted(.percent))
                Text(progress.formatted(.percent.precision(.fractionLength(1))))
            } else { Text("Progress unavailable").foregroundStyle(Theme.Colors.textSecondary) }
            if let size = item.size, let remaining = item.sizeleft, item.progress != nil {
                Text("\(bytes(size - remaining)) of \(bytes(size)) downloaded")
                Text("\(bytes(remaining)) remaining").foregroundStyle(Theme.Colors.textSecondary)
            }
            if let left = item.timeleft, !left.isEmpty { Label("Sonarr time left: \(left)", systemImage: "clock") }
            if let eta = item.estimatedCompletionTime { Text("Estimated completion: \(eta.formatted(date: .abbreviated, time: .shortened))") }
            if let client = item.downloadClient, !client.isEmpty { Text("Download client: \(client)") }
            if let status = item.trackedDownloadStatus { Text("Download health: \(status)") }
            if let error = item.errorMessage, !error.isEmpty { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.Colors.error) }
            ForEach(Array((item.statusMessages ?? []).enumerated()), id: \.offset) { _, message in
                VStack(alignment: .leading, spacing: 5) {
                    if let title = message.title { Text(title).font(.headline) }
                    ForEach(Array((message.messages ?? []).enumerated()), id: \.offset) { _, text in Text(text).font(.body) }
                }
            }
            Text("Snapshot captured when this page opened. Return to the dashboard and refresh for updates. Sonarr controls completion and import; downloading 100% does not guarantee the episode was imported.")
                .font(.footnote).foregroundStyle(Theme.Colors.textSecondary)
        }
    }
    private func bytes(_ value: Double) -> String {
        guard value.isFinite, value >= 0, value < Double(Int64.max) else { return "Unknown size" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }
}

private struct SonarrDetailCanvas<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) { Text(title).font(.title2.bold()); content }
                    .frame(maxWidth: Theme.contentMaxWidth(900), alignment: .leading).padding(Theme.Spacing.edge).frame(maxWidth: .infinity)
            }
        }.navigationTitle("Sonarr")
    }
}

private struct SonarrEditor: View {
    @ObservedObject var store: SonarrStore
    @Environment(\.dismiss) private var dismiss
    @State private var address = "http://"
    @State private var baselineAddress = "http://"
    @State private var apiKey = ""
    @State private var error: String?
    @State private var working = false
    @State private var loaded = false
    @State private var discard = false
    @State private var confirmDisconnect = false
    private var hasChanges: Bool { address != baselineAddress || !apiKey.isEmpty }
    private var canSave: Bool {
        guard let url = SonarrDashboardPolicy.serverURL(address) else { return false }
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (store.isConfigured && store.baseURL == url)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Server address", text: $address).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Sonarr server address")
                    SecureField(store.isConfigured && SonarrDashboardPolicy.serverURL(address) == store.baseURL ? "New API key (optional)" : "API key", text: $apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel("Sonarr API key")
                    Text("Use the server's base address, including its reverse-proxy path if needed. Find its API key in Sonarr → Settings → General → Security.").font(.footnote)
                    if store.isConfigured && SonarrDashboardPolicy.serverURL(address) != store.baseURL {
                        Text("A different address requires its API key; the saved key is not sent to a new server.").font(.footnote)
                    }
                }.disabled(working)
                if store.isConfigured {
                    Section { Button("Disconnect Sonarr", role: .destructive) { confirmDisconnect = true }.disabled(working) }
                }
                if working { ProgressView("Testing connection…") }
                if let error { Text(error).foregroundStyle(Theme.Colors.error) }
            }
            #if os(iOS)
            .scrollContentBackground(.hidden)
            #endif
            .background(Theme.Colors.appBackground)
            .navigationTitle("Sonarr Connection")
            .onAppear {
                guard !loaded else { return }; loaded = true
                address = store.configuration.address; baselineAddress = address
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if hasChanges { discard = true } else { dismiss() } }.disabled(working) }
                ToolbarItem(placement: .confirmationAction) { Button(working ? "Testing…" : "Save & Test") { Task { await save() } }.disabled(working || !canSave) }
            }
            .interactiveDismissDisabled(working || hasChanges)
            .confirmationDialog("Discard connection changes?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }; Button("Keep editing", role: .cancel) { }
            }
            .confirmationDialog("Disconnect Sonarr?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) {
                    do { try store.disconnect(); dismiss() } catch { self.error = error.localizedDescription }
                }
            } message: { Text("Removes this connection and its saved API key. Sonarr's files, queue, and series are unchanged.") }
        }.presentationBackground(Theme.Colors.appBackground)
    }

    private func save() async {
        guard !working, canSave else { return }
        working = true; error = nil; defer { working = false }
        do {
            try store.save(address: address, apiKey: apiKey)
            baselineAddress = store.configuration.address; address = baselineAddress; apiKey = ""
            await store.refresh()
            if let message = store.errorMessage { error = message } else { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}

struct MediaServersView: View {
    @EnvironmentObject private var env: AppEnvironment
    var body: some View { MediaServersContent(store: env.mediaServers) }
}

private struct MediaServersContent: View {
    @ObservedObject var store: MediaServerStore
    @State private var refreshError: String?
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

                    if store.connections.isEmpty { emptyState }
                    ForEach(store.connections) { connection in serverCard(connection) }

                    Menu {
                        ForEach(MediaServerKind.allCases) { kind in
                            Button { addingKind = kind } label: { Label(kind.title, systemImage: kind.symbol) }
                        }
                    } label: {
                        Label("Add Media Server", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NovaRowButtonStyle())

                    if let refreshError { Label(refreshError, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.Colors.error) }
                    if let message = store.statusMessage {
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
                if let pendingRemoval { store.remove(pendingRemoval, removeIndexedItems: true) }
                pendingRemoval = nil
            }
            Button("Remove Server Only") {
                if let pendingRemoval { store.remove(pendingRemoval, removeIndexedItems: false) }
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
        let syncing = store.syncingIDs.contains(connection.id)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: connection.kind.symbol).foregroundStyle(Theme.Colors.accent).font(.appFont(26))
                VStack(alignment: .leading, spacing: 3) {
                    Text(connection.name).font(.appFont(19, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                    Text(connection.baseURL.host ?? connection.baseURL.absoluteString)
                        .font(.subheadline).foregroundStyle(Theme.Colors.textTertiary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if syncing { ProgressView().tint(Theme.Colors.accent) }
                else { Text("\(connection.indexedItemCount) indexed").font(.subheadline).foregroundStyle(Theme.Colors.textSecondary).monospacedDigit() }
            }
            if let date = connection.lastIndexed {
                Text("Indexed \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.appFont(13)).foregroundStyle(Theme.Colors.textTertiary)
            }
            if let error = connection.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.appFont(14)).foregroundStyle(Theme.Colors.error)
            }
            FlowLayout(spacing: Theme.Spacing.sm) {
                Button { Task {
                    refreshError = nil
                    do { try await store.sync(connection.id) } catch { refreshError = error.localizedDescription }
                } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }.buttonStyle(NovaChipButtonStyle(providesSurface: true)).disabled(syncing)
                Button { editing = connection } label: { Label("Edit", systemImage: "slider.horizontal.3") }
                    .buttonStyle(NovaChipButtonStyle(providesSurface: true)).disabled(syncing)
                Button(role: .destructive) { pendingRemoval = connection } label: { Label("Remove", systemImage: "trash") }
                    .buttonStyle(NovaChipButtonStyle(providesSurface: true)).disabled(syncing)
            }
        }
        .padding(Theme.Spacing.md).refinedCardBackground()
    }
}

private struct MediaServerEditor: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let existing: MediaServerConnection?
    private let initialKind: MediaServerKind
    @State private var discard = false
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
        self.existing = existing; self.initialKind = kind
        _kind = State(initialValue: existing?.kind ?? kind)
        _name = State(initialValue: existing?.name ?? kind.title)
        _address = State(initialValue: existing?.baseURL.absoluteString ?? "http://")
        _username = State(initialValue: existing?.username ?? "")
        _selectedLibraries = State(initialValue: existing?.selectedLibraryIDs ?? [])
        _autoRefresh = State(initialValue: existing?.autoRefresh ?? true)
    }

    private var hasChanges: Bool {
        kind != (existing?.kind ?? initialKind) || name != (existing?.name ?? initialKind.title) ||
        address != (existing?.baseURL.absoluteString ?? "http://") || username != (existing?.username ?? "") ||
        !password.isEmpty || !token.isEmpty || selectedLibraries != (existing?.selectedLibraryIDs ?? []) ||
        autoRefresh != (existing?.autoRefresh ?? true)
    }
    private var canSave: Bool {
        guard let url = SonarrDashboardPolicy.serverURL(address), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if let existing, (url != SonarrDashboardPolicy.serverURL(existing.baseURL.absoluteString) || username != existing.username) && token.isEmpty && password.isEmpty { return false }
        return kind != .plex || existing != nil || !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                            secureField("New access token (optional)", text: $token)
                            secureField("New password (optional)", text: $password)
                            Text("Use either an access token or your server password. Leave both blank to retain this connection's saved token.")
                                .font(.footnote).foregroundStyle(Theme.Colors.textSecondary)
                        }
                        if let existing, SonarrDashboardPolicy.serverURL(address) != SonarrDashboardPolicy.serverURL(existing.baseURL.absoluteString) || username != existing.username {
                            Text("Changing the address or username requires a new token or password before saving.")
                                .font(.footnote).foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Toggle("Refresh this server automatically", isOn: $autoRefresh).tint(Theme.Colors.accent)

                        if let existing, !existing.availableLibraries.isEmpty {
                            Text("Libraries").font(Theme.Font.sectionTitle()).foregroundStyle(Theme.Colors.textPrimary)
                            Text("Select the libraries to index. Leaving all unselected includes every available library.")
                                .font(.footnote).foregroundStyle(Theme.Colors.textSecondary)
                            ForEach(existing.availableLibraries) { library in
                                Toggle(isOn: Binding(get: { selectedLibraries.contains(library.id) }, set: { on in
                                    if on { selectedLibraries.insert(library.id) } else { selectedLibraries.remove(library.id) }
                                })) { Text(library.name).foregroundStyle(Theme.Colors.textPrimary) }
                                    .tint(Theme.Colors.accent)
                            }
                        }
                        if let error { Text(error).font(.appFont(14)).foregroundStyle(Theme.Colors.error) }
                    }
                    .padding(Theme.Spacing.edge).disabled(working)
                    .frame(maxWidth: Theme.contentMaxWidth(900), alignment: .leading).frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(existing == nil ? "Add \(kind.title)" : "Edit \(kind.title)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if hasChanges { discard = true } else { dismiss() } }.disabled(working) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(working ? "Connecting…" : "Save & Index") { Task { await save() } }
                        .disabled(working || !canSave)
                }
            }
            .interactiveDismissDisabled(working || hasChanges)
            .confirmationDialog("Discard server changes?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }; Button("Keep editing", role: .cancel) { }
            }
        }.presentationBackground(Theme.Colors.appBackground)
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
        guard !working, canSave, let url = SonarrDashboardPolicy.serverURL(address) else { return }
        working = true; error = nil; defer { working = false }
        var draft = existing ?? MediaServerConnection(kind: kind, name: name, baseURL: url)
        draft.kind = kind; draft.name = name.trimmingCharacters(in: .whitespacesAndNewlines); draft.baseURL = url; draft.username = username
        draft.selectedLibraryIDs = selectedLibraries; draft.autoRefresh = autoRefresh
        do {
            _ = try await env.mediaServers.connect(draft, password: password, token: token)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
