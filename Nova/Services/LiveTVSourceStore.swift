//
//  LiveTVSourceStore.swift
//  Nova
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

    // MARK: Codable — credentials live in the Keychain, not in the JSON

    enum CodingKeys: String, CodingKey {
        case id, name, url, kind, isEnabled, isBuiltIn, username, password, epgURL, refreshHours
    }

    /// Encoder `userInfo` flag. Only when set to `true` (a backup the user explicitly
    /// opted into including secrets) are `username`/`password` written inline.
    /// Otherwise they are omitted, so the JSON persisted to UserDefaults and
    /// iCloud KVS never contains plaintext IPTV credentials.
    static let includeCredentialsKey = CodingUserInfoKey(rawValue: "nova.livetv.includeCredentials")!

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        url = try c.decode(String.self, forKey: .url)
        kind = try c.decode(Kind.self, forKey: .kind)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        isBuiltIn = try c.decode(Bool.self, forKey: .isBuiltIn)
        // Data written by older versions (or restored from a backup) may still carry
        // credentials inline; LiveTVSourceStore migrates them into the Keychain.
        username = try c.decodeIfPresent(String.self, forKey: .username)
        password = try c.decodeIfPresent(String.self, forKey: .password)
        epgURL = try c.decodeIfPresent(String.self, forKey: .epgURL)
        refreshHours = try c.decodeIfPresent(Int.self, forKey: .refreshHours)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(url, forKey: .url)
        try c.encode(kind, forKey: .kind)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(isBuiltIn, forKey: .isBuiltIn)
        if encoder.userInfo[Self.includeCredentialsKey] as? Bool == true {
            try c.encodeIfPresent(username, forKey: .username)
            try c.encodeIfPresent(password, forKey: .password)
        }
        try c.encodeIfPresent(epgURL, forKey: .epgURL)
        try c.encodeIfPresent(refreshHours, forKey: .refreshHours)
    }

    // MARK: Keychain-backed credentials

    /// Keychain account for one credential field of one source (keyed by source id).
    static func keychainAccount(_ field: String, for id: UUID) -> String {
        "livetv.\(id.uuidString).\(field)"
    }

    /// Whether this value carries credentials in memory (e.g. decoded inline).
    var hasCredentials: Bool { username != nil || password != nil }

    /// A copy whose missing credentials are filled in from the Keychain.
    func withKeychainCredentials() -> LiveTVSource {
        guard !isBuiltIn else { return self }
        var copy = self
        let keychain = KeychainStore.shared
        if copy.username == nil { copy.username = keychain.get(Self.keychainAccount("username", for: id)) }
        if copy.password == nil { copy.password = keychain.get(Self.keychainAccount("password", for: id)) }
        return copy
    }

    /// Writes any in-memory credentials to the Keychain.
    func saveCredentialsToKeychain() {
        let keychain = KeychainStore.shared
        do {
            if let username { try keychain.set(username, for: Self.keychainAccount("username", for: id)) }
            if let password { try keychain.set(password, for: Self.keychainAccount("password", for: id)) }
        } catch {
            NovaLog.sync.error("Failed to save Live TV credentials to Keychain: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes a source's credentials from the Keychain.
    static func deleteKeychainCredentials(for id: UUID) {
        let keychain = KeychainStore.shared
        try? keychain.delete(keychainAccount("username", for: id))
        try? keychain.delete(keychainAccount("password", for: id))
    }

    /// Takes a Live TV source-list JSON blob that may contain inline credentials
    /// (legacy data or a restored backup), moves those credentials into the
    /// Keychain, and returns the blob re-encoded without them. Returns the input
    /// unchanged if it can't be decoded.
    static func migratingCredentialsToKeychain(_ data: Data) -> Data {
        guard let sources = try? JSONDecoder().decode([LiveTVSource].self, from: data) else { return data }
        guard sources.contains(where: \.hasCredentials) else { return data }
        for source in sources { source.saveCredentialsToKeychain() }
        return (try? JSONEncoder().encode(sources)) ?? data
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

        // Reload after a backup restore. The restore writes the source list (and any
        // usernames/passwords) to UserDefaults + iCloud, but this store already read
        // its list at launch; without reloading it would keep showing the old list
        // and never fetch the restored playlists.
        NotificationCenter.default.addObserver(
            forName: .novaBackupRestored, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reload() }
        }

        // FIX: register the network-restored observer exactly once here. It used to be
        // added inside mergeFromCloud(), which runs on init, reload, and every iCloud
        // external change, stacking duplicate observers and duplicate refreshes.
        NotificationCenter.default.addObserver(
            forName: NetworkConditionMonitor.networkRestored,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshAll() }
        }
    }

    /// Re-reads the source list from disk (used after a backup restore), adopts any
    /// restored sources/credentials, re-seeds the built-ins, and refreshes the
    /// channels for every enabled source so a restored connection actually works
    /// instead of merely appearing in the list.
    func reload() {
        load()
        mergeFromCloud()
        seedBuiltInsIfNeeded()
        // Force a refresh so enabled sources fetch their playlists with the restored
        // credentials rather than sitting empty.
        Task { await refreshAll(force: true) }
    }

    private static let builtInSources: [LiveTVSource] = [
        LiveTVSource(name: "Pluto TV (Free)", url: "https://i.mjh.nz/PlutoTV/us.m3u8", kind: .curated, isEnabled: false, isBuiltIn: true),
        LiveTVSource(name: "Samsung TV Plus (Free)", url: "https://i.mjh.nz/SamsungTVPlus/us.m3u8", kind: .curated, isEnabled: false, isBuiltIn: true),
        LiveTVSource(name: "Plex Free TV", url: "https://i.mjh.nz/Plex/us.m3u8", kind: .curated, isEnabled: false, isBuiltIn: true),
        LiveTVSource(name: "Roku Channel (Free)", url: "https://i.mjh.nz/Roku/us.m3u8", kind: .curated, isEnabled: false, isBuiltIn: true),
        LiveTVSource(name: "Stirr (Free)", url: "https://i.mjh.nz/Stirr/us.m3u8", kind: .curated, isEnabled: false, isBuiltIn: true)
    ]

    private func seedBuiltInsIfNeeded() {
        var didAppend = false
        for builtIn in Self.builtInSources where !sources.contains(where: { $0.name == builtIn.name && $0.isBuiltIn }) {
            sources.append(builtIn)
            didAppend = true
        }
        // FIX: persist only when a built-in was actually added. This ran on every
        // init/reload/cloud merge and unconditionally re-pushed identical data to
        // iCloud, triggering needless external-change churn on other devices.
        if didAppend { persist() }
    }

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([LiveTVSource].self, from: data) else { return }
        sources = decoded.map { $0.withKeychainCredentials() }
        // Migrate credentials stored inline by older versions (or a restored backup)
        // into the Keychain and rewrite the stored JSON without them.
        if decoded.contains(where: \.hasCredentials) { persist() }
    }

    private func persist() {
        // Credentials go to the Keychain; the JSON below omits them (see
        // LiveTVSource.encode(to:)), so UserDefaults/iCloud KVS never hold them.
        for source in sources where source.hasCredentials { source.saveCredentialsToKeychain() }
        guard let data = try? JSONEncoder().encode(sources) else { return }
        defaults.set(data, forKey: defaultsKey)
        // Mirror to iCloud so other devices pick up the change in real time.
        CloudSync.shared.setData(data, forKey: Self.cloudKey)
    }

    /// Pulls the iCloud Live TV source list if present and different, and adopts it.
    /// Built-in curated sources are re-seeded afterward so they're never lost.
    private func mergeFromCloud() {
        guard let data = CloudSync.shared.data(forKey: Self.cloudKey),
              let decoded = try? JSONDecoder().decode([LiveTVSource].self, from: data) else { return }
        let cloudSources = decoded.map { $0.withKeychainCredentials() }
        if decoded.contains(where: \.hasCredentials) {
            // Legacy plaintext credentials in iCloud KVS: adopt the list, move the
            // credentials into the Keychain, and re-push the list without them.
            let changed = cloudSources != sources
            sources = cloudSources
            persist()
            if changed { Task { await refreshAll() } }
            return
        }
        guard cloudSources != sources else { return }
        sources = cloudSources
        // Persist locally without re-pushing identical data to the cloud.
        if let encoded = try? JSONEncoder().encode(sources) {
            defaults.set(encoded, forKey: defaultsKey)
        }
        // Refresh channels for any enabled sources adopted from the cloud.
        // (Network-restored observer registration moved to init() — see FIX there.)
        Task { await refreshAll() }
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

    /// Saves a portable M3U found inside an imported Kodi package, then registers
    /// it as an ordinary Nova Live TV source. The original ZIP is never executed.
    @discardableResult
    func importKodiPlaylist(data: Data, name: String) throws -> LiveTVSource {
        guard data.count <= 25_000_000,
              String(decoding: data.prefix(16), as: UTF8.self).contains("#EXTM3U") else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first!
            .appendingPathComponent("KodiPlaylists", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeName = name.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-",
                                                  options: .regularExpression)
        let fileURL = folder.appendingPathComponent(safeName.isEmpty ? UUID().uuidString : safeName)
            .appendingPathExtension("m3u")
        try data.write(to: fileURL, options: .atomic)
        let source = LiveTVSource(name: name, url: fileURL.absoluteString, kind: .m3u,
                                  isEnabled: true, isBuiltIn: false)
        sources.append(source)
        persist()
        Task { await refresh(source) }
        return source
    }

    func remove(_ source: LiveTVSource) {
        guard !source.isBuiltIn else { return }
        sources.removeAll { $0.id == source.id }
        channelsBySource[source.id] = nil
        LiveTVSource.deleteKeychainCredentials(for: source.id)
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
            // FIX: clear any stale error once a refresh succeeds, so the UI doesn't
            // keep showing a failure banner after the source has recovered.
            lastError = nil
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
