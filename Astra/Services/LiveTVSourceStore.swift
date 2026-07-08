//
//  LiveTVSourceStore.swift
//  Astra
//

import Foundation
import Combine

struct LiveTVSource: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case m3u, xtream, curated }
    var id: UUID
    var name: String
    var url: String
    var kind: Kind
    var isEnabled: Bool
    var isBuiltIn: Bool
    var username: String?
    var password: String?
    /// Optional XMLTV guide URL for now-playing info.
    var epgURL: String?
    /// Hours between automatic playlist refreshes (nil = every 12 hours).
    var refreshHours: Int?

    init(id: UUID = UUID(), name: String, url: String, kind: Kind,
         isEnabled: Bool = false, isBuiltIn: Bool = false,
         username: String? = nil, password: String? = nil,
         epgURL: String? = nil, refreshHours: Int? = nil) {
        self.id = id; self.name = name; self.url = url; self.kind = kind
        self.isEnabled = isEnabled; self.isBuiltIn = isBuiltIn
        self.username = username; self.password = password
        self.epgURL = epgURL; self.refreshHours = refreshHours
    }

    var playlistURL: URL? {
        switch kind {
        case .m3u, .curated:
            return URL(string: url)
        case .xtream:
            guard let user = username, let pass = password,
                  var comps = URLComponents(string: url.hasSuffix("/") ? url : url + "/") else {
                return URL(string: url)
            }
            comps.path = (comps.path as NSString).appendingPathComponent("get.php")
            comps.queryItems = [
                URLQueryItem(name: "username", value: user),
                URLQueryItem(name: "password", value: pass),
                URLQueryItem(name: "type", value: "m3u_plus"),
                URLQueryItem(name: "output", value: "ts")
            ]
            return comps.url
        }
    }
}

struct LiveTVChannel: Identifiable, Hashable {
    var id: String { url.absoluteString }
    var name: String
    var url: URL
    var logoURL: URL?
    var tvgID: String?
    var group: String?
}

@MainActor
final class LiveTVSourceStore: ObservableObject {
    @Published var sources: [LiveTVSource] = []
    @Published private(set) var channelsBySource: [UUID: [LiveTVChannel]] = [:]
    @Published var isLoading = false
    @Published var lastError: String?

    private let defaultsKey = "livetv.sources.v1"
    /// iCloud KVS key for the Live TV source list, so it syncs across devices in
    /// real time like SMB shares and addons.
    static let cloudKey = "cloud.livetv.sources.v1"
    private let defaults = UserDefaults.standard
    private let session: URLSession = AppNetworking.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        load()
        mergeFromCloud()
        seedBuiltInsIfNeeded()

        // Live updates when another device changes the Live TV source list.
        CloudSync.shared.externalChange
            .receive(on: RunLoop.main)
            .sink { [weak self] keys in
                if keys.contains(Self.cloudKey) { self?.mergeFromCloud() }
            }
            .store(in: &cancellables)
    }

    private static let builtInSources: [LiveTVSource] = [
        LiveTVSource(name: "Pluto TV (Free)", url: "https://i.mjh.nz/PlutoTV/us.m3u8", kind: .curated, isEnabled: false, isBuiltIn: true),
        LiveTVSource(name: "Samsung TV Plus (Free)", url: "https://i.mjh.nz/SamsungTVPlus/us.m3u8", kind: .curated, isEnabled: false, isBuiltIn: true),
        LiveTVSource(name: "Plex Free TV", url: "https://i.mjh.nz/Plex/us.m3u8", kind: .curated, isEnabled: false, isBuiltIn: true),
        LiveTVSource(name: "Roku Channel (Free)", url: "https://i.mjh.nz/Roku/us.m3u8", kind: .curated, isEnabled: false, isBuiltIn: true),
        LiveTVSource(name: "Stirr (Free)", url: "https://i.mjh.nz/Stirr/us.m3u8", kind: .curated, isEnabled: false, isBuiltIn: true)
    ]

    private func seedBuiltInsIfNeeded() {
        for builtIn in Self.builtInSources where !sources.contains(where: { $0.name == builtIn.name && $0.isBuiltIn }) {
            sources.append(builtIn)
        }
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([LiveTVSource].self, from: data) else { return }
        sources = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(sources) else { return }
        defaults.set(data, forKey: defaultsKey)
        // Mirror to iCloud so other devices pick up the change in real time.
        CloudSync.shared.setData(data, forKey: Self.cloudKey)
    }

    /// Pulls the iCloud Live TV source list if present and different, and adopts it.
    /// Built-in curated sources are re-seeded afterward so they're never lost.
    private func mergeFromCloud() {
        guard let data = CloudSync.shared.data(forKey: Self.cloudKey),
              let cloudSources = try? JSONDecoder().decode([LiveTVSource].self, from: data),
              cloudSources != sources else { return }
        sources = cloudSources
        // Persist locally without re-pushing identical data to the cloud.
        if let encoded = try? JSONEncoder().encode(sources) {
            defaults.set(encoded, forKey: defaultsKey)
        }
        // Refresh channels for any enabled sources adopted from the cloud.
        Task { await refreshAll() }
        // When connectivity returns after an outage, reload stale playlists.
        NotificationCenter.default.addObserver(
            forName: NetworkConditionMonitor.networkRestored,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshAll() }
        }
    }

    func setEnabled(_ enabled: Bool, for source: LiveTVSource) {
        guard let idx = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[idx].isEnabled = enabled
        persist()
        if enabled { Task { await refresh(sources[idx]) } }
        else { channelsBySource[source.id] = nil }
    }

    func addCustom(name: String, url: String, kind: LiveTVSource.Kind,
                   username: String? = nil, password: String? = nil,
                   epgURL: String? = nil, refreshHours: Int? = nil) {
        let source = LiveTVSource(name: name.isEmpty ? "Custom Playlist" : name, url: url, kind: kind,
                                  isEnabled: true, isBuiltIn: false, username: username, password: password,
                                  epgURL: epgURL, refreshHours: refreshHours)
        sources.append(source); persist()
        Task { await refresh(source) }
    }

    func remove(_ source: LiveTVSource) {
        guard !source.isBuiltIn else { return }
        sources.removeAll { $0.id == source.id }
        channelsBySource[source.id] = nil
        persist()
    }

    var allChannels: [LiveTVChannel] {
        sources.filter(\.isEnabled).flatMap { channelsBySource[$0.id] ?? [] }
    }

    /// When each source was last successfully refreshed (session-persistent).
    private var lastRefreshed: [UUID: Date] = [:]

    func refreshAll(force: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        await withTaskGroup(of: Void.self) { group in
            for source in sources where source.isEnabled {
                // Respect the per-source refresh interval unless forced; playlists
                // rarely change minute to minute, so skip fresh-enough sources.
                if !force, let last = lastRefreshed[source.id] {
                    let interval = TimeInterval((source.refreshHours ?? 12)) * 3600
                    if Date().timeIntervalSince(last) < interval,
                       !(channelsBySource[source.id] ?? []).isEmpty {
                        continue
                    }
                }
                group.addTask { await self.refresh(source) }
            }
        }
    }

    func refresh(_ source: LiveTVSource) async {
        guard source.isEnabled, let url = source.playlistURL else { return }
        do {
            var req = URLRequest(url: url); req.timeoutInterval = 30
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                lastError = "Couldn't load \(source.name)."; return
            }
            let text = String(decoding: data, as: UTF8.self)
            channelsBySource[source.id] = Self.parseM3U(text)
            lastRefreshed[source.id] = Date()
        } catch {
            lastError = "Couldn't load \(source.name): \(error.localizedDescription)"
        }
    }

    static func parseM3U(_ text: String) -> [LiveTVChannel] {
        var channels: [LiveTVChannel] = []
        var pendingName: String?
        var pendingLogo: URL?
        var pendingGroup: String?
        var pendingTVGID: String?
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXTINF") {
                pendingLogo = attribute("tvg-logo", in: line).flatMap(URL.init(string:))
                pendingTVGID = attribute("tvg-id", in: line)
                pendingGroup = attribute("group-title", in: line)
                if let commaRange = line.range(of: ",", options: .backwards) {
                    pendingName = String(line[commaRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
            } else if !line.isEmpty, !line.hasPrefix("#"), let url = URL(string: line) {
                let name = pendingName ?? url.lastPathComponent
                channels.append(LiveTVChannel(name: name, url: url, logoURL: pendingLogo,
                                              tvgID: pendingTVGID, group: pendingGroup))
                pendingName = nil; pendingLogo = nil; pendingGroup = nil; pendingTVGID = nil
            }
        }
        return channels
    }

    private static func attribute(_ key: String, in line: String) -> String? {
        guard let keyRange = line.range(of: "\(key)=\"") else { return nil }
        let rest = line[keyRange.upperBound...]
        guard let endQuote = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<endQuote])
    }

    func makePlayable(_ channel: LiveTVChannel) -> MediaItem {
        MediaItem(title: channel.name, sourceType: .liveTV, playbackURL: channel.url,
                  posterURL: channel.logoURL, legalAccessConfirmed: true, metadata: MediaMetadata())
    }
}
