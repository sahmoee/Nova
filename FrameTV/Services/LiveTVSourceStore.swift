//
//  LiveTVSourceStore.swift
//  FrameTV
//

import Foundation

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

    init(id: UUID = UUID(), name: String, url: String, kind: Kind,
         isEnabled: Bool = false, isBuiltIn: Bool = false,
         username: String? = nil, password: String? = nil) {
        self.id = id; self.name = name; self.url = url; self.kind = kind
        self.isEnabled = isEnabled; self.isBuiltIn = isBuiltIn
        self.username = username; self.password = password
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
    var group: String?
}

@MainActor
final class LiveTVSourceStore: ObservableObject {
    @Published var sources: [LiveTVSource] = []
    @Published private(set) var channelsBySource: [UUID: [LiveTVChannel]] = [:]
    @Published var isLoading = false
    @Published var lastError: String?

    private let defaultsKey = "livetv.sources.v1"
    private let defaults = UserDefaults.standard
    private let session: URLSession = AppNetworking.shared

    init() { load(); seedBuiltInsIfNeeded() }

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
        if let data = try? JSONEncoder().encode(sources) { defaults.set(data, forKey: defaultsKey) }
    }

    func setEnabled(_ enabled: Bool, for source: LiveTVSource) {
        guard let idx = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[idx].isEnabled = enabled
        persist()
        if enabled { Task { await refresh(sources[idx]) } }
        else { channelsBySource[source.id] = nil }
    }

    func addCustom(name: String, url: String, kind: LiveTVSource.Kind, username: String? = nil, password: String? = nil) {
        let source = LiveTVSource(name: name.isEmpty ? "Custom Playlist" : name, url: url, kind: kind,
                                  isEnabled: true, isBuiltIn: false, username: username, password: password)
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

    func refreshAll() async {
        isLoading = true
        defer { isLoading = false }
        await withTaskGroup(of: Void.self) { group in
            for source in sources where source.isEnabled {
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
        } catch {
            lastError = "Couldn't load \(source.name): \(error.localizedDescription)"
        }
    }

    static func parseM3U(_ text: String) -> [LiveTVChannel] {
        var channels: [LiveTVChannel] = []
        var pendingName: String?
        var pendingLogo: URL?
        var pendingGroup: String?
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXTINF") {
                pendingLogo = attribute("tvg-logo", in: line).flatMap(URL.init(string:))
                pendingGroup = attribute("group-title", in: line)
                if let commaRange = line.range(of: ",", options: .backwards) {
                    pendingName = String(line[commaRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
            } else if !line.isEmpty, !line.hasPrefix("#"), let url = URL(string: line) {
                let name = pendingName ?? url.lastPathComponent
                channels.append(LiveTVChannel(name: name, url: url, logoURL: pendingLogo, group: pendingGroup))
                pendingName = nil; pendingLogo = nil; pendingGroup = nil
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
