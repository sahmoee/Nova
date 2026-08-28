import Foundation
import Combine
import CryptoKit
import Network
#if canImport(FoundationXML)
import FoundationXML
#endif

// MARK: - Smart playlists

struct NovaSmartPlaylist: Identifiable, Codable, Hashable {
    enum Field: String, Codable, CaseIterable { case title, genre, year, source, watched, favorite, tag }
    enum Operation: String, Codable, CaseIterable { case contains, equals, greaterThan, lessThan }
    struct Rule: Identifiable, Codable, Hashable { var id = UUID(); var field: Field; var operation: Operation; var value: String }
    var id = UUID()
    var name: String
    var matchAll = true
    var rules: [Rule]

    func matches(_ item: MediaItem) -> Bool {
        guard !rules.isEmpty else { return true }
        let values = rules.map { rule -> Bool in
            let candidate: String
            switch rule.field {
            case .title: candidate = item.displayTitle
            case .genre: candidate = item.tags.joined(separator: " ")
            case .year: candidate = item.metadata.year.map(String.init) ?? ""
            case .source: candidate = item.sourceType.rawValue
            case .watched: candidate = String(item.isWatched)
            case .favorite: candidate = String(item.isFavorite)
            case .tag: candidate = item.tags.joined(separator: " ")
            }
            switch rule.operation {
            case .contains: return candidate.localizedCaseInsensitiveContains(rule.value)
            case .equals: return candidate.caseInsensitiveCompare(rule.value) == .orderedSame
            case .greaterThan: return (Double(candidate) ?? 0) > (Double(rule.value) ?? 0)
            case .lessThan: return (Double(candidate) ?? 0) < (Double(rule.value) ?? 0)
            }
        }
        return matchAll ? values.allSatisfy { $0 } : values.contains(true)
    }
}

// MARK: - NFO import/export

struct KodiNFORecord: Hashable {
    var title = ""
    var plot: String?
    var year: Int?
    var season: Int?
    var episode: Int?
    var uniqueIDs: [String: String] = [:]
    var genres: [String] = []
    var posterURL: URL?
}

enum KodiNFOCodec {
    static func parse(_ data: Data) throws -> KodiNFORecord {
        let delegate = NFOParser()
        let parser = XMLParser(data: data); parser.delegate = delegate
        guard parser.parse(), !delegate.record.title.isEmpty else { throw KodiRepositoryError.invalidXML }
        return delegate.record
    }

    static func export(_ item: MediaItem) -> Data {
        func xml(_ value: String) -> String { value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        let root = item.isEpisode ? "episodedetails" : (item.isSeries ? "tvshow" : "movie")
        var lines = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>", "<\(root)>", "  <title>\(xml(item.title))</title>"]
        if let year = item.metadata.year { lines.append("  <year>\(year)</year>") }
        if let episode = item.episode { lines += ["  <season>\(episode.season)</season>", "  <episode>\(episode.number)</episode>"] }
        if let imdb = item.contentID?.imdb { lines.append("  <uniqueid type=\"imdb\" default=\"true\">\(xml(imdb))</uniqueid>") }
        if let tmdb = item.contentID?.tmdb { lines.append("  <uniqueid type=\"tmdb\">\(tmdb)</uniqueid>") }
        for tag in item.tags { lines.append("  <genre>\(xml(tag))</genre>") }
        lines.append("</\(root)>")
        return Data(lines.joined(separator: "\n").utf8)
    }

    static func mediaItem(from record: KodiNFORecord, mediaURL: URL) -> MediaItem {
        let type: ContentType = record.season == nil ? .movie : .series
        let contentID = ContentID(imdb: record.uniqueIDs["imdb"], tmdb: record.uniqueIDs["tmdb"].flatMap(Int.init), type: type)
        return MediaItem(title: record.title, sourceType: .directURL, playbackURL: mediaURL,
                         posterURL: record.posterURL, legalAccessConfirmed: true,
                         metadata: MediaMetadata(season: record.season, episode: record.episode, year: record.year),
                         contentID: contentID,
                         episode: record.season.flatMap { season in record.episode.map { EpisodeRef(season: season, number: $0) } },
                         tags: record.genres)
    }
}

private final class NFOParser: NSObject, XMLParserDelegate {
    var record = KodiNFORecord(); private var text = ""; private var uniqueIDType: String?
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String : String] = [:]) { text = ""; if elementName == "uniqueid" { uniqueIDType = attributeDict["type"] } }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName { case "title": record.title = value; case "plot": record.plot = value; case "year": record.year = Int(value); case "season": record.season = Int(value); case "episode": record.episode = Int(value); case "genre": if !value.isEmpty { record.genres.append(value) }; case "thumb": if record.posterURL == nil { record.posterURL = URL(string: value) }; case "uniqueid": if let key = uniqueIDType, !value.isEmpty { record.uniqueIDs[key] = value }; default: break }
    }
}

// MARK: - Safe declarative providers and signed repositories

struct NovaDeclarativeExtension: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case subtitle, metadata, playlist }
    var id: String
    var name: String
    var version: String
    var kind: Kind
    var endpointTemplate: String
    var allowedHosts: [String]
    var sha256: String? = nil
    var signature: String? = nil
    var signingKey: String? = nil

    func validatedURL(values: [String: String]) -> URL? {
        var rendered = endpointTemplate
        for (key, value) in values { rendered = rendered.replacingOccurrences(of: "{\(key)}", with: value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value) }
        guard let url = URL(string: rendered), url.scheme == "https", let host = url.host,
              allowedHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) else { return nil }
        return url
    }

    func hasValidSignature() -> Bool {
        guard let signature, let signingKey,
              let signatureData = Data(base64Encoded: signature),
              let keyData = Data(base64Encoded: signingKey),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else { return false }
        var unsigned = self; unsigned.signature = nil
        guard let payload = try? JSONEncoder().encode(unsigned) else { return false }
        return publicKey.isValidSignature(signatureData, for: payload)
    }

    func matchesDeclaredChecksum(_ data: Data) -> Bool {
        guard let expected = sha256?.lowercased(), !expected.isEmpty else { return true }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return actual == expected
    }
}

struct NovaExtensionRepository: Codable, Hashable {
    var name: String
    var generatedAt: Date
    var extensions: [NovaDeclarativeExtension]
}

// MARK: - UPnP/DLNA discovery

struct UPnPDevice: Identifiable, Hashable {
    var location: URL
    var server: String?
    var usn: String?
    var id: String { usn ?? location.absoluteString }
}

actor UPnPDiscoveryClient {
    func discover(timeout: Duration = .seconds(3)) async -> [UPnPDevice] {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(host: "239.255.255.250", port: 1900, using: .udp)
            let queue = DispatchQueue(label: "nova.ssdp")
            let collector = SSDPCollector()
            let request = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: ssdp:all\r\n\r\n"
            connection.start(queue: queue)
            connection.send(content: Data(request.utf8), completion: .contentProcessed { _ in Self.receive(on: connection, collector: collector) })
            queue.asyncAfter(deadline: .now() + 3) { connection.cancel(); continuation.resume(returning: collector.values) }
        }
    }

    private nonisolated static func receive(on connection: NWConnection, collector: SSDPCollector) {
        connection.receiveMessage { data, _, _, _ in
            if let data, let text = String(data: data, encoding: .utf8) { collector.insert(text) }
            Self.receive(on: connection, collector: collector)
        }
    }
}

private final class SSDPCollector: @unchecked Sendable {
    private let lock = NSLock(); private var devices: [String: UPnPDevice] = [:]
    var values: [UPnPDevice] { lock.withLock { Array(devices.values) } }
    func insert(_ text: String) {
        let headers = Dictionary(uniqueKeysWithValues: text.split(whereSeparator: \.isNewline).compactMap { line -> (String, String)? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return (String(line[..<colon]).lowercased(), String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
        })
        guard let raw = headers["location"], let url = URL(string: raw) else { return }
        lock.withLock { devices[headers["usn"] ?? raw] = UPnPDevice(location: url, server: headers["server"], usn: headers["usn"]) }
    }
}

actor NovaDeclarativeProviderClient {
    private struct SubtitleResponse: Decodable { var subtitles: [Item]; struct Item: Decodable { var url: URL; var language: String; var name: String? } }
    func subtitles(extensions: [NovaDeclarativeExtension], content: ContentID, episode: EpisodeRef?) async -> [SubtitleTrack] {
        let providers = extensions.filter { $0.kind == .subtitle && $0.hasValidSignature() }
        return await withTaskGroup(of: [SubtitleTrack].self) { group in
            for provider in providers {
                group.addTask {
                    let values = ["imdb": content.imdb ?? "", "tmdb": content.tmdb.map(String.init) ?? "", "season": episode.map { String($0.season) } ?? "", "episode": episode.map { String($0.number) } ?? ""]
                    guard let url = provider.validatedURL(values: values) else { return [] }
                    do {
                        var request = URLRequest(url: url); request.timeoutInterval = 12; request.setValue("application/json", forHTTPHeaderField: "Accept")
                        let (data, response) = try await AppNetworking.shared.data(for: request)
                        guard let http = response as? HTTPURLResponse,
                              (200..<300).contains(http.statusCode),
                              data.count <= 2_000_000,
                              provider.matchesDeclaredChecksum(data) else { return [] }
                        return try JSONDecoder().decode(SubtitleResponse.self, from: data).subtitles.map { .init(language: $0.language, languageDisplay: $0.name ?? $0.language, url: $0.url, source: provider.name) }
                    } catch { return [] }
                }
            }
            var result: [SubtitleTrack] = []; for await tracks in group { result += tracks }; return result
        }
    }
}

// MARK: - Persistent integration state

@MainActor
final class MediaIntegrationStore: ObservableObject {
    @Published var smartPlaylists: [NovaSmartPlaylist] = [] { didSet { save() } }
    @Published var extensions: [NovaDeclarativeExtension] = [] { didSet { save() } }
    @Published var repositoryURLs: [URL] = [] { didSet { save() } }
    @Published var discoveredDevices: [UPnPDevice] = []
    @Published var status: String?
    private let url: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        url = support.appendingPathComponent("media-integrations.json")
        if let data = try? Data(contentsOf: url), let state = try? JSONDecoder().decode(State.self, from: data) { smartPlaylists = state.smartPlaylists; extensions = state.extensions; repositoryURLs = state.repositoryURLs }
        Task { await refreshRepositories() }
    }
    private struct State: Codable { var smartPlaylists: [NovaSmartPlaylist]; var extensions: [NovaDeclarativeExtension]; var repositoryURLs: [URL] = [] }
    private func save() { try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); if let data = try? JSONEncoder().encode(State(smartPlaylists: smartPlaylists, extensions: extensions, repositoryURLs: repositoryURLs)) { try? data.write(to: url, options: .atomic) } }
    func discoverUPnP() async { discoveredDevices = await UPnPDiscoveryClient().discover(); status = discoveredDevices.isEmpty ? "No UPnP/DLNA devices answered" : "Found \(discoveredDevices.count) devices" }
    func installRepository(_ repository: NovaExtensionRepository) { let valid = repository.extensions.filter { $0.hasValidSignature() }; for item in valid { extensions.removeAll { $0.id == item.id }; extensions.append(item) }; status = "Installed \(valid.count) verified extensions" }
    func addRepository(_ url: URL) { if !repositoryURLs.contains(url) { repositoryURLs.append(url) }; Task { await refreshRepositories() } }
    func refreshRepositories() async {
        var count = 0
        for url in repositoryURLs where url.scheme == "https" {
            do {
                var request = URLRequest(url: url); request.timeoutInterval = 15
                let (data, response) = try await AppNetworking.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count <= 5_000_000 else { continue }
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                let repo = try decoder.decode(NovaExtensionRepository.self, from: data)
                let valid = repo.extensions.filter { $0.hasValidSignature() }
                for item in valid { extensions.removeAll { $0.id == item.id }; extensions.append(item) }
                count += valid.count
            } catch { continue }
        }
        if !repositoryURLs.isEmpty { status = "Verified \(count) provider updates" }
    }
}
