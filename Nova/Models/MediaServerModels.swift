import Foundation

enum MediaServerKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case jellyfin, plex, emby
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var sourceType: SourceType {
        switch self {
        case .jellyfin: return .jellyfin
        case .plex: return .plex
        case .emby: return .emby
        }
    }
    var symbol: String { sourceType.systemImage }
}

struct MediaServerLibrary: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var kind: String?
}

struct MediaServerConnection: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var kind: MediaServerKind
    var name: String
    var baseURL: URL
    var username: String = ""
    var userID: String?
    var selectedLibraryIDs: Set<String> = []
    var availableLibraries: [MediaServerLibrary] = []
    var autoRefresh = true
    var lastIndexed: Date?
    var indexedItemCount = 0
    var lastError: String?

    var tokenAccount: String { "media-server.\(id.uuidString).token" }

    init(id: UUID = UUID(), kind: MediaServerKind, name: String, baseURL: URL) {
        self.id = id; self.kind = kind; self.name = name; self.baseURL = baseURL
    }
    enum CodingKeys: String, CodingKey {
        case id, kind, name, baseURL, username, userID, selectedLibraryIDs, availableLibraries, autoRefresh, lastIndexed, indexedItemCount, lastError
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(MediaServerKind.self, forKey: .kind)
        name = try c.decode(String.self, forKey: .name)
        baseURL = try MediaServerIndexPolicy.normalizedBase(c.decode(URL.self, forKey: .baseURL))
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        userID = try c.decodeIfPresent(String.self, forKey: .userID)
        selectedLibraryIDs = try c.decodeIfPresent(Set<String>.self, forKey: .selectedLibraryIDs) ?? []
        availableLibraries = try c.decodeIfPresent([MediaServerLibrary].self, forKey: .availableLibraries) ?? []
        autoRefresh = try c.decodeIfPresent(Bool.self, forKey: .autoRefresh) ?? true
        lastIndexed = try c.decodeIfPresent(Date.self, forKey: .lastIndexed)
        indexedItemCount = max(0, try c.decodeIfPresent(Int.self, forKey: .indexedItemCount) ?? 0)
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
    }

    func mayReuseCredential(from other: Self) -> Bool {
        guard let current = try? MediaServerIndexPolicy.normalizedBase(baseURL), let previous = try? MediaServerIndexPolicy.normalizedBase(other.baseURL) else { return false }
        return kind == other.kind && username.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(other.username.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame && current == previous
    }
}

struct MediaServerIndexResult: Sendable {
    var libraries: [MediaServerLibrary]
    var items: [MediaItem]
}

enum MediaServerError: LocalizedError {
    case invalidAddress, missingCredential, unauthorized, unsupportedResponse, http(Int)
    case incompleteIndex, responseTooLarge, unreadableConfiguration, userRequired, localPersistence
    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "Enter a valid HTTP or HTTPS server address."
        case .missingCredential: return "This server needs a saved access token."
        case .unauthorized: return "The server rejected the account or access token."
        case .unsupportedResponse: return "The server returned an unsupported response."
        case .http(let status): return "The server returned HTTP \(status)."
        case .incompleteIndex: return "The server's library changed or returned incomplete pages. The previous index was kept; try refreshing again."
        case .responseTooLarge: return "This server response exceeds Nova's supported indexing size. The previous index was kept."
        case .unreadableConfiguration: return "Saved media-server settings could not be read. Original settings are preserved; changes are paused."
        case .userRequired: return "Enter the username associated with this server token so Nova can identify the correct library access."
        case .localPersistence: return "Nova couldn't save the local library changes. The server connection was kept; check Library recovery and retry."
        }
    }
}
