import Foundation

/// Read-only adapters for personal Jellyfin, Emby and Plex libraries. Each
/// adapter normalizes its provider payload into Nova's durable MediaItem model.
actor MediaServerClient {
    private let session: URLSession

    init(session: URLSession = AppNetworking.shared) { self.session = session }

    func authenticate(kind: MediaServerKind, baseURL: URL, username: String,
                      password: String, token: String?) async throws -> (token: String, userID: String?) {
        switch kind {
        case .plex:
            guard let token, !token.isEmpty else { throw MediaServerError.missingCredential }
            _ = try await data(baseURL: baseURL, path: "/identity",
                               headers: plexHeaders(token), query: [:])
            return (token, nil)
        case .jellyfin, .emby:
            if let token, !token.isEmpty {
                let users: JellyfinUsers = try await decode(baseURL: baseURL, path: "/Users",
                    headers: embyHeaders(token), query: [:])
                let user = users.first { username.isEmpty || $0.name.caseInsensitiveCompare(username) == .orderedSame }
                return (token, user?.id)
            }
            let body = try JSONSerialization.data(withJSONObject: ["Username": username, "Pw": password])
            let response: JellyfinAuthentication = try await decode(baseURL: baseURL,
                path: "/Users/AuthenticateByName", headers: embyHeaders(nil), query: [:],
                method: "POST", body: body)
            guard !response.accessToken.isEmpty else { throw MediaServerError.unauthorized }
            return (response.accessToken, response.user?.id)
        }
    }

    func index(connection: MediaServerConnection, token: String) async throws -> MediaServerIndexResult {
        switch connection.kind {
        case .jellyfin, .emby: return try await indexEmby(connection, token: token)
        case .plex: return try await indexPlex(connection, token: token)
        }
    }

    private func indexEmby(_ connection: MediaServerConnection, token: String) async throws -> MediaServerIndexResult {
        guard let userID = connection.userID, !userID.isEmpty else {
            throw MediaServerError.unauthorized
        }
        let libraries: [JellyfinLibrary] = try await decode(baseURL: connection.baseURL,
            path: "/Library/VirtualFolders", headers: embyHeaders(token), query: [:])
        let normalizedLibraries = libraries.compactMap { library -> MediaServerLibrary? in
            guard let id = library.itemId, !id.isEmpty else { return nil }
            return MediaServerLibrary(id: id, name: library.name, kind: library.collectionType)
        }
        let selected = connection.selectedLibraryIDs.isEmpty
            ? Set(normalizedLibraries.map(\.id)) : connection.selectedLibraryIDs
        var all: [MediaItem] = []
        for library in normalizedLibraries where selected.contains(library.id) {
            var startIndex = 0
            let pageSize = 500
            repeat {
                try Task.checkCancellation()
                let response: JellyfinItems = try await decode(baseURL: connection.baseURL,
                    path: "/Users/\(userID)/Items", headers: embyHeaders(token),
                    query: ["ParentId": library.id, "Recursive": "true",
                            "IncludeItemTypes": "Movie,Episode", "Fields": "ProviderIds,MediaSources,DateCreated,Overview,Genres,ProductionYear,RunTimeTicks,SeriesName,ParentIndexNumber,IndexNumber,PrimaryImageAspectRatio",
                            "EnableImages": "true", "ImageTypeLimit": "1",
                            "StartIndex": String(startIndex), "Limit": String(pageSize)])
                all.append(contentsOf: response.items.compactMap {
                    jellyfinItem($0, connection: connection, token: token)
                })
                startIndex += response.items.count
                if response.items.isEmpty || startIndex >= response.totalRecordCount { break }
            } while true
        }
        return MediaServerIndexResult(libraries: normalizedLibraries, items: all)
    }

    private func jellyfinItem(_ raw: JellyfinItem, connection: MediaServerConnection,
                              token: String) -> MediaItem? {
        guard raw.type == "Movie" || raw.type == "Episode" else { return nil }
        let isEpisode = raw.type == "Episode"
        let kind: ContentType = isEpisode ? .series : .movie
        let provider = raw.providerIds ?? [:]
        let tmdb = provider["Tmdb"].flatMap(Int.init)
        let imdb = provider["Imdb"]
        let contentID = ContentID(imdb: imdb, tmdb: tmdb,
            addonItemID: "\(connection.kind.rawValue):\(raw.id)", type: kind)
        let base = connection.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let escaped = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
        let playback = URL(string: "\(base)/Videos/\(raw.id)/stream?static=true&api_key=\(escaped)")!
        let image = URL(string: "\(base)/Items/\(raw.id)/Images/Primary?maxWidth=1000&quality=90&api_key=\(escaped)")
        let backdropTag = raw.imageTags?["Backdrop"] ?? raw.backdropImageTags?.first
        let backdrop = backdropTag == nil ? image : URL(string:
            "\(base)/Items/\(raw.id)/Images/Backdrop/0?maxWidth=1920&quality=90&api_key=\(escaped)")
        let episode = isEpisode ? EpisodeRef(season: raw.parentIndexNumber ?? 0,
            number: raw.indexNumber ?? 0, episodeTitle: raw.name) : nil
        var metadata = MediaMetadata(filename: raw.path.map { ($0 as NSString).lastPathComponent },
            season: raw.parentIndexNumber, episode: raw.indexNumber, year: raw.productionYear,
            mediaServerID: connection.id, mediaServerItemID: raw.id)
        metadata.codec = raw.mediaSources?.first?.mediaStreams?.first(where: { $0.type == "Video" })?.codec
        metadata.resolution = raw.mediaSources?.first?.mediaStreams?.first(where: { $0.type == "Video" })?.displayTitle
        return MediaItem(title: raw.name, sourceType: connection.kind.sourceType,
            playbackURL: playback, posterURL: image, backdropURL: backdrop,
            duration: raw.runTimeTicks.map { Double($0) / 10_000_000 },
            legalAccessConfirmed: true, metadata: metadata, contentID: contentID,
            episode: episode, seriesTitle: raw.seriesName)
    }

    private func indexPlex(_ connection: MediaServerConnection, token: String) async throws -> MediaServerIndexResult {
        let sections: PlexSections = try await decode(baseURL: connection.baseURL,
            path: "/library/sections", headers: plexHeaders(token), query: ["X-Plex-Token": token])
        let libraries = sections.mediaContainer.directory.map {
            MediaServerLibrary(id: $0.key, name: $0.title, kind: $0.type)
        }
        let selected = connection.selectedLibraryIDs.isEmpty ? Set(libraries.map(\.id)) : connection.selectedLibraryIDs
        var all: [MediaItem] = []
        for library in libraries where selected.contains(library.id) {
            var startIndex = 0
            let pageSize = 500
            repeat {
                try Task.checkCancellation()
                let page: PlexMetadataPage = try await decode(baseURL: connection.baseURL,
                    path: "/library/sections/\(library.id)/all", headers: plexHeaders(token),
                    query: ["includeGuids": "1", "type": library.kind == "show" ? "4" : "1",
                            "X-Plex-Container-Start": String(startIndex),
                            "X-Plex-Container-Size": String(pageSize), "X-Plex-Token": token])
                let records = page.mediaContainer.metadata ?? []
                all.append(contentsOf: records.compactMap {
                    plexItem($0, connection: connection, token: token)
                })
                startIndex += records.count
                let total = page.mediaContainer.totalSize ?? page.mediaContainer.size ?? records.count
                if records.isEmpty || startIndex >= total { break }
            } while true
        }
        return MediaServerIndexResult(libraries: libraries, items: all)
    }

    private func plexItem(_ raw: PlexMetadata, connection: MediaServerConnection, token: String) -> MediaItem? {
        guard raw.type == "movie" || raw.type == "episode", let part = raw.media?.first?.part?.first else { return nil }
        let isEpisode = raw.type == "episode"
        let guids = raw.guid ?? []
        let imdb = guids.first { $0.id.hasPrefix("imdb://") }?.id.replacingOccurrences(of: "imdb://", with: "")
        let tmdb = guids.first { $0.id.hasPrefix("tmdb://") }.flatMap {
            Int($0.id.replacingOccurrences(of: "tmdb://", with: ""))
        }
        let contentID = ContentID(imdb: imdb, tmdb: tmdb,
            addonItemID: "plex:\(raw.ratingKey)", type: isEpisode ? .series : .movie)
        let base = connection.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        func serverURL(_ path: String?) -> URL? {
            guard let path else { return nil }
            return URL(string: "\(base)\(path)\(path.contains("?") ? "&" : "?")X-Plex-Token=\(token)")
        }
        let metadata = MediaMetadata(filename: part.file.map { ($0 as NSString).lastPathComponent },
            fileSize: part.size, resolution: raw.media?.first?.videoResolution,
            season: raw.parentIndex, episode: raw.index, year: raw.year,
            mediaServerID: connection.id, mediaServerItemID: raw.ratingKey)
        return MediaItem(title: raw.title, sourceType: .plex,
            playbackURL: serverURL(part.key)!, posterURL: serverURL(raw.thumb),
            backdropURL: serverURL(raw.art ?? raw.grandparentThumb),
            duration: raw.duration.map { Double($0) / 1000 }, legalAccessConfirmed: true,
            metadata: metadata, contentID: contentID,
            episode: isEpisode ? EpisodeRef(season: raw.parentIndex ?? 0,
                number: raw.index ?? 0, episodeTitle: raw.title) : nil,
            seriesTitle: raw.grandparentTitle)
    }

    private func embyHeaders(_ token: String?) -> [String: String] {
        var headers = ["X-Emby-Authorization": "MediaBrowser Client=Nova, Device=Apple, DeviceId=nova, Version=1.0"]
        if let token { headers["X-Emby-Token"] = token }
        return headers
    }
    private func plexHeaders(_ token: String) -> [String: String] {
        ["X-Plex-Token": token, "X-Plex-Product": "Nova", "X-Plex-Client-Identifier": "nova-apple",
         "X-Plex-Version": "1.0", "Accept": "application/json"]
    }

    private func decode<T: Decodable>(baseURL: URL, path: String, headers: [String: String],
                                      query: [String: String], method: String = "GET",
                                      body: Data? = nil) async throws -> T {
        let payload = try await data(baseURL: baseURL, path: path, headers: headers,
                                     query: query, method: method, body: body)
        do { return try Coders.decoder.decode(T.self, from: payload) }
        catch { throw MediaServerError.unsupportedResponse }
    }

    private func data(baseURL: URL, path: String, headers: [String: String],
                      query: [String: String], method: String = "GET", body: Data? = nil) async throws -> Data {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(components.scheme?.lowercased() ?? "") else {
            throw MediaServerError.invalidAddress
        }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path
        components.queryItems = query.sorted { $0.key < $1.key }.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        guard let url = components.url else { throw MediaServerError.invalidAddress }
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (payload, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw MediaServerError.unsupportedResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw MediaServerError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw MediaServerError.http(http.statusCode) }
        return payload
    }
}

private typealias JellyfinUsers = [JellyfinUser]
private struct JellyfinUser: Decodable { var id: String; var name: String; enum CodingKeys: String, CodingKey { case id = "Id", name = "Name" } }
private struct JellyfinAuthentication: Decodable { var accessToken: String; var user: JellyfinUser?; enum CodingKeys: String, CodingKey { case accessToken = "AccessToken", user = "User" } }
private struct JellyfinLibrary: Decodable { var name: String; var itemId: String?; var collectionType: String?; enum CodingKeys: String, CodingKey { case name = "Name", itemId = "ItemId", collectionType = "CollectionType" } }
private struct JellyfinItems: Decodable {
    var items: [JellyfinItem]
    var totalRecordCount: Int
    enum CodingKeys: String, CodingKey { case items = "Items", totalRecordCount = "TotalRecordCount" }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([JellyfinItem].self, forKey: .items) ?? []
        totalRecordCount = try container.decodeIfPresent(Int.self, forKey: .totalRecordCount) ?? items.count
    }
}
private struct JellyfinItem: Decodable {
    var id, name, type: String; var path, seriesName: String?; var productionYear, parentIndexNumber, indexNumber: Int?
    var runTimeTicks: Int64?; var providerIds, imageTags: [String: String]?; var backdropImageTags: [String]?
    var mediaSources: [JellyfinMediaSource]?
    enum CodingKeys: String, CodingKey { case id = "Id", name = "Name", type = "Type", path = "Path", seriesName = "SeriesName", productionYear = "ProductionYear", parentIndexNumber = "ParentIndexNumber", indexNumber = "IndexNumber", runTimeTicks = "RunTimeTicks", providerIds = "ProviderIds", imageTags = "ImageTags", backdropImageTags = "BackdropImageTags", mediaSources = "MediaSources" }
}
private struct JellyfinMediaSource: Decodable { var mediaStreams: [JellyfinMediaStream]?; enum CodingKeys: String, CodingKey { case mediaStreams = "MediaStreams" } }
private struct JellyfinMediaStream: Decodable { var type, codec, displayTitle: String?; enum CodingKeys: String, CodingKey { case type = "Type", codec = "Codec", displayTitle = "DisplayTitle" } }

private struct PlexSections: Decodable { var mediaContainer: PlexSectionContainer; enum CodingKeys: String, CodingKey { case mediaContainer = "MediaContainer" } }
private struct PlexSectionContainer: Decodable { var directory: [PlexDirectory]; enum CodingKeys: String, CodingKey { case directory = "Directory" } }
private struct PlexDirectory: Decodable { var key, title, type: String }
private struct PlexMetadataPage: Decodable { var mediaContainer: PlexMetadataContainer; enum CodingKeys: String, CodingKey { case mediaContainer = "MediaContainer" } }
private struct PlexMetadataContainer: Decodable {
    var metadata: [PlexMetadata]?
    var size: Int?
    var totalSize: Int?
    enum CodingKeys: String, CodingKey { case metadata = "Metadata", size, totalSize }
}
private struct PlexMetadata: Decodable {
    var ratingKey, type, title: String; var grandparentTitle, thumb, art, grandparentThumb: String?
    var year, duration, parentIndex, index: Int?; var guid: [PlexGuid]?; var media: [PlexMedia]?
    enum CodingKeys: String, CodingKey {
        case ratingKey, type, title, grandparentTitle, thumb, art, grandparentThumb
        case year, duration, parentIndex, index
        case guid = "Guid", media = "Media"
    }
}
private struct PlexGuid: Decodable { var id: String }
private struct PlexMedia: Decodable { var videoResolution: String?; var part: [PlexPart]?; enum CodingKeys: String, CodingKey { case videoResolution, part = "Part" } }
private struct PlexPart: Decodable { var key: String; var file: String?; var size: Int64? }
