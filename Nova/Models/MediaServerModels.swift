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
}

struct MediaServerIndexResult: Sendable {
    var libraries: [MediaServerLibrary]
    var items: [MediaItem]
}

enum MediaServerError: LocalizedError {
    case invalidAddress, missingCredential, unauthorized, unsupportedResponse, http(Int)
    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "Enter a valid HTTP or HTTPS server address."
        case .missingCredential: return "This server needs a saved access token."
        case .unauthorized: return "The server rejected the account or access token."
        case .unsupportedResponse: return "The server returned an unsupported response."
        case .http(let status): return "The server returned HTTP \(status)."
        }
    }
}
