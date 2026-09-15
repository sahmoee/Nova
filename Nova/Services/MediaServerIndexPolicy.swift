import Foundation

enum MediaServerIndexPolicy {
    static let maximumResponseBytes = 16 * 1024 * 1024
    static let maximumItems = 200_000

    // These are optional ItemFields, not arbitrary BaseItemDto property names.
    static let jellyfinFields = "ProviderIds,MediaSources,MediaStreams,Path"

    static func selectedLibraries(available: [String], known: [String], selected: Set<String>) throws -> Set<String> {
        let all = Set(known), supported = Set(available)
        guard known.count <= 1024, !all.contains(""), all.count == known.count,
              supported.count == available.count, supported.isSubset(of: all) else { throw MediaServerError.unsupportedResponse }
        guard selected.isSubset(of: all) else { throw MediaServerError.incompleteIndex }
        if selected.isEmpty { return supported }
        // Older versions saved non-video sections as selected. Ignore those only
        // when a supported selection remains; never silently change to all videos.
        let result = selected.intersection(supported)
        guard !result.isEmpty else { throw MediaServerError.incompleteIndex }
        return result
    }

    static func normalizedBase(_ url: URL) throws -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.port.map({ (1...65535).contains($0) }) ?? true else { throw MediaServerError.invalidAddress }
        let decoded = parts.path
        guard !decoded.contains("\\"), !decoded.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
              !decoded.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw MediaServerError.invalidAddress }
        parts.scheme = parts.scheme?.lowercased(); parts.host = host.lowercased()
        parts.path = decoded == "/" ? "" : decoded.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty ? "" : "/" + decoded.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let result = parts.url else { throw MediaServerError.invalidAddress }
        return result
    }

    static func endpoint(base: URL, components: [String], query: [String: String] = [:]) throws -> URL {
        let base = try normalizedBase(base)
        var url = base
        for component in components {
            guard !component.isEmpty, component != ".", component != "..",
                  !component.contains("/"), !component.contains("\\"),
                  !component.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw MediaServerError.unsupportedResponse }
            url.appendPathComponent(component)
        }
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw MediaServerError.invalidAddress }
        parts.queryItems = query.isEmpty ? nil : query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let result = parts.url else { throw MediaServerError.invalidAddress }
        return result
    }

    /// Provider paths are server-relative; never append a saved token to another origin.
    static func resource(base: URL, path: String, token: String) throws -> URL {
        guard let relative = URLComponents(string: path), relative.scheme == nil, relative.host == nil,
              relative.user == nil, relative.password == nil, relative.fragment == nil,
              path.hasPrefix("/"), !path.hasPrefix("//"), !relative.path.contains("\\"),
              !relative.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { throw MediaServerError.unsupportedResponse }
        guard var result = URLComponents(url: try normalizedBase(base), resolvingAgainstBaseURL: false) else { throw MediaServerError.invalidAddress }
        result.path += relative.path
        result.queryItems = (relative.queryItems ?? []).filter { $0.name.caseInsensitiveCompare("X-Plex-Token") != .orderedSame } + [URLQueryItem(name: "X-Plex-Token", value: token)]
        guard let url = result.url else { throw MediaServerError.unsupportedResponse }
        return url
    }

    static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let a = URLComponents(url: lhs, resolvingAgainstBaseURL: false), let b = URLComponents(url: rhs, resolvingAgainstBaseURL: false),
              let scheme = a.scheme?.lowercased(), ["http", "https"].contains(scheme), let host = a.host?.lowercased() else { return false }
        return scheme == b.scheme?.lowercased() && host == b.host?.lowercased()
            && (a.port ?? (scheme == "https" ? 443 : 80)) == (b.port ?? (scheme == "https" ? 443 : 80))
            && b.user == nil && b.password == nil
    }
    static func token(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) ? nil : trimmed
    }
    static func imdb(_ value: String?) -> String? {
        guard let value = value?.lowercased(), value.range(of: "^tt[0-9]{5,12}$", options: .regularExpression) != nil else { return nil }
        return value
    }
    static func tmdb(_ value: String?) -> Int? { value.flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil } }

    /// Tracks raw provider records, not the smaller set of supported playable items.
    struct Pager {
        private(set) var offset = 0
        private var seen = Set<String>()
        private var advertisedTotal: Int?
        let pageSize: Int
        init(pageSize: Int = 500) { self.pageSize = max(1, pageSize) }
        mutating func accept(ids: [String], total: Int?, returnedOffset: Int? = nil) throws -> Bool {
            guard ids.count <= pageSize, offset <= maximumItems - ids.count,
                  total.map({ $0 >= 0 && $0 <= maximumItems }) ?? true,
                  returnedOffset.map({ $0 == offset }) ?? true else { throw MediaServerError.incompleteIndex }
            if let total {
                if let advertisedTotal, total != advertisedTotal { throw MediaServerError.incompleteIndex }
                advertisedTotal = total
            }
            for id in ids {
                guard !id.isEmpty, seen.insert(id).inserted else { throw MediaServerError.incompleteIndex }
            }
            offset += ids.count
            if let advertisedTotal {
                guard offset <= advertisedTotal, !ids.isEmpty || offset == advertisedTotal else { throw MediaServerError.incompleteIndex }
                return offset < advertisedTotal
            }
            // An absent total is unknown, never the count of the first page.
            return !ids.isEmpty
        }
    }
}

struct MediaServerOperationGate {
    private var owners: [UUID: UUID] = [:]
    mutating func begin(_ id: UUID) -> UUID { let token = UUID(); owners[id] = token; return token }
    func owns(_ token: UUID, id: UUID) -> Bool { owners[id] == token }
    mutating func retire(_ id: UUID) { owners.removeValue(forKey: id) }
    mutating func finish(_ token: UUID, id: UUID) { if owns(token, id: id) { retire(id) } }
}

/// Only same-origin redirects may carry provider authentication headers.
final class MediaServerRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let origin: URL
    init(origin: URL) { self.origin = origin }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map { MediaServerIndexPolicy.sameOrigin(origin, $0) } == true ? request : nil)
    }
}

struct JellyfinUser: Decodable { var id: String; var name: String; enum CodingKeys: String, CodingKey { case id = "Id", name = "Name" } }
struct JellyfinAuthentication: Decodable { var accessToken: String; var user: JellyfinUser?; enum CodingKeys: String, CodingKey { case accessToken = "AccessToken", user = "User" } }
struct JellyfinView: Decodable { var id: String; var name: String; var collectionType: String?; enum CodingKeys: String, CodingKey { case id = "Id", name = "Name", collectionType = "CollectionType" } }
struct JellyfinPage<Item: Decodable>: Decodable {
    var items: [Item]
    var totalRecordCount: Int?
    var startIndex: Int?
    enum CodingKeys: String, CodingKey { case items = "Items", totalRecordCount = "TotalRecordCount", startIndex = "StartIndex" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode([Item].self, forKey: .items)
        totalRecordCount = try c.decodeIfPresent(Int.self, forKey: .totalRecordCount)
        startIndex = try c.decodeIfPresent(Int.self, forKey: .startIndex)
    }
}
struct JellyfinItem: Decodable {
    var id, name, type: String; var path, seriesName: String?; var productionYear, parentIndexNumber, indexNumber: Int?
    var runTimeTicks: Int64?; var providerIds, imageTags: [String: String]?; var backdropImageTags: [String]?
    var mediaSources: [JellyfinMediaSource]?
    enum CodingKeys: String, CodingKey { case id = "Id", name = "Name", type = "Type", path = "Path", seriesName = "SeriesName", productionYear = "ProductionYear", parentIndexNumber = "ParentIndexNumber", indexNumber = "IndexNumber", runTimeTicks = "RunTimeTicks", providerIds = "ProviderIds", imageTags = "ImageTags", backdropImageTags = "BackdropImageTags", mediaSources = "MediaSources" }
}
struct JellyfinMediaSource: Decodable { var mediaStreams: [JellyfinMediaStream]?; enum CodingKeys: String, CodingKey { case mediaStreams = "MediaStreams" } }
struct JellyfinMediaStream: Decodable { var type, codec, displayTitle: String?; enum CodingKeys: String, CodingKey { case type = "Type", codec = "Codec", displayTitle = "DisplayTitle" } }
struct PlexSections: Decodable { var mediaContainer: PlexSectionContainer; enum CodingKeys: String, CodingKey { case mediaContainer = "MediaContainer" } }
struct PlexSectionContainer: Decodable {
    var directory: [PlexDirectory]
    enum CodingKeys: String, CodingKey { case directory = "Directory", size }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let values = try c.decodeIfPresent([PlexDirectory].self, forKey: .directory) { directory = values }
        else if try c.decodeIfPresent(Int.self, forKey: .size) == 0 { directory = [] }
        else { throw MediaServerError.unsupportedResponse }
    }
}
struct PlexDirectory: Decodable { var key, title, type: String }
struct PlexMetadataPage: Decodable { var mediaContainer: PlexMetadataContainer; enum CodingKeys: String, CodingKey { case mediaContainer = "MediaContainer" } }
struct PlexMetadataContainer: Decodable {
    var metadata: [PlexMetadata]
    var size: Int?
    var totalSize: Int?
    var offset: Int?
    enum CodingKeys: String, CodingKey { case metadata = "Metadata", size, totalSize, offset }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        size = try c.decodeIfPresent(Int.self, forKey: .size); totalSize = try c.decodeIfPresent(Int.self, forKey: .totalSize)
        offset = try c.decodeIfPresent(Int.self, forKey: .offset)
        if let values = try c.decodeIfPresent([PlexMetadata].self, forKey: .metadata) { metadata = values }
        else if size == 0 || totalSize == 0 { metadata = [] }
        else { throw MediaServerError.unsupportedResponse }
        if let size, size != metadata.count { throw MediaServerError.incompleteIndex }
    }
}
struct PlexMetadata: Decodable {
    var ratingKey, type, title: String; var grandparentTitle, thumb, art, grandparentThumb: String?
    var year, duration, parentIndex, index: Int?; var guid: [PlexGuid]?; var media: [PlexMedia]?
    enum CodingKeys: String, CodingKey {
        case ratingKey, type, title, grandparentTitle, thumb, art, grandparentThumb
        case year, duration, parentIndex, index
        case guid = "Guid", media = "Media"
    }
}
struct PlexGuid: Decodable { var id: String }
struct PlexMedia: Decodable { var videoResolution: String?; var part: [PlexPart]?; enum CodingKeys: String, CodingKey { case videoResolution, part = "Part" } }
struct PlexPart: Decodable { var key: String; var file: String?; var size: Int64? }
