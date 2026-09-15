import Foundation

protocol MediaServerIndexing: Sendable {
    func authenticate(kind: MediaServerKind, baseURL: URL, username: String, password: String, token: String?) async throws -> (token: String, userID: String?)
    func index(connection: MediaServerConnection, token: String) async throws -> MediaServerIndexResult
}

/// Read-only adapters. A complete, validated snapshot is the only successful result.
actor MediaServerClient: MediaServerIndexing {
    private let session: URLSession
    init(session: URLSession = AppNetworking.shared) { self.session = session }

    func authenticate(kind: MediaServerKind, baseURL: URL, username: String,
                      password: String, token: String?) async throws -> (token: String, userID: String?) {
        let baseURL = try MediaServerIndexPolicy.normalizedBase(baseURL)
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .plex:
            guard let token = MediaServerIndexPolicy.token(token) else { throw MediaServerError.missingCredential }
            let identity: PlexIdentity = try await decode(baseURL: baseURL, path: ["identity"], headers: plexHeaders(token))
            guard !identity.mediaContainer.machineIdentifier.isEmpty else { throw MediaServerError.unsupportedResponse }
            return (token, nil)
        case .jellyfin, .emby:
            if let token = MediaServerIndexPolicy.token(token) {
                if kind == .jellyfin {
                    do {
                        let user: JellyfinUser = try await decode(baseURL: baseURL, path: ["Users", "Me"], headers: embyHeaders(token))
                        guard !user.id.isEmpty, username.isEmpty || user.name.caseInsensitiveCompare(username) == .orderedSame else { throw MediaServerError.userRequired }
                        return (token, user.id)
                    } catch MediaServerError.unauthorized {
                        // An administrator API key may not identify a current user.
                        guard !username.isEmpty else { throw MediaServerError.userRequired }
                    }
                }
                let users: [JellyfinUser] = try await decode(baseURL: baseURL, path: ["Users"], headers: embyHeaders(token))
                let matching = users.filter { username.isEmpty || $0.name.caseInsensitiveCompare(username) == .orderedSame }
                guard matching.count == 1, let user = matching.first, !user.id.isEmpty else { throw MediaServerError.userRequired }
                return (token, user.id)
            }
            guard !username.isEmpty, !password.isEmpty else { throw MediaServerError.missingCredential }
            let body = try JSONSerialization.data(withJSONObject: ["Username": username, "Pw": password])
            let response: JellyfinAuthentication = try await decode(baseURL: baseURL,
                path: ["Users", "AuthenticateByName"], headers: embyHeaders(nil), method: "POST", body: body)
            guard let token = MediaServerIndexPolicy.token(response.accessToken), let user = response.user, !user.id.isEmpty else { throw MediaServerError.unauthorized }
            return (token, user.id)
        }
    }

    func index(connection: MediaServerConnection, token: String) async throws -> MediaServerIndexResult {
        try Task.checkCancellation()
        guard let token = MediaServerIndexPolicy.token(token) else { throw MediaServerError.missingCredential }
        switch connection.kind {
        case .jellyfin, .emby: return try await indexEmby(connection, token: token)
        case .plex: return try await indexPlex(connection, token: token)
        }
    }

    private func indexEmby(_ connection: MediaServerConnection, token: String) async throws -> MediaServerIndexResult {
        guard let userID = connection.userID, !userID.isEmpty else { throw MediaServerError.userRequired }
        // User-scoped Views does not require the administrator-only VirtualFolders API.
        let views: JellyfinPage<JellyfinView> = try await decode(baseURL: connection.baseURL,
            path: ["Users", userID, "Views"], headers: embyHeaders(token), query: ["IncludeExternalContent": "false"])
        if let total = views.totalRecordCount, total != views.items.count { throw MediaServerError.incompleteIndex }
        let libraries = views.items.filter { $0.collectionType == nil || ["", "movies", "tvshows", "mixed"].contains($0.collectionType?.lowercased() ?? "") }.map {
            MediaServerLibrary(id: $0.id, name: $0.name, kind: $0.collectionType)
        }
        let selected = try MediaServerIndexPolicy.selectedLibraries(available: libraries.map(\.id),
            known: views.items.map(\.id), selected: connection.selectedLibraryIDs)
        var all: [MediaItem] = [], seenItems = Set<String>()
        for library in libraries where selected.contains(library.id) {
            var pager = MediaServerIndexPolicy.Pager()
            var more = true
            while more {
                try Task.checkCancellation()
                let response: JellyfinPage<JellyfinItem> = try await decode(baseURL: connection.baseURL,
                    path: ["Users", userID, "Items"], headers: embyHeaders(token),
                    query: ["ParentId": library.id, "Recursive": "true", "IncludeItemTypes": "Movie,Episode",
                            "Fields": MediaServerIndexPolicy.jellyfinFields,
                            "EnableImages": "true", "ImageTypeLimit": "1", "EnableTotalRecordCount": "true",
                            "SortBy": "SortName", "SortOrder": "Ascending",
                            "StartIndex": String(pager.offset), "Limit": String(pager.pageSize)])
                more = try pager.accept(ids: response.items.map(\.id), total: response.totalRecordCount, returnedOffset: response.startIndex)
                for raw in response.items where seenItems.insert(raw.id).inserted {
                    guard seenItems.count <= MediaServerIndexPolicy.maximumItems else { throw MediaServerError.responseTooLarge }
                    if let item = try jellyfinItem(raw, connection: connection, token: token) { all.append(item) }
                }
                guard all.count <= MediaServerIndexPolicy.maximumItems else { throw MediaServerError.responseTooLarge }
            }
        }
        try Task.checkCancellation()
        return MediaServerIndexResult(libraries: libraries, items: all)
    }

    private func jellyfinItem(_ raw: JellyfinItem, connection: MediaServerConnection, token: String) throws -> MediaItem? {
        guard raw.type == "Movie" || raw.type == "Episode" else { return nil }
        let isEpisode = raw.type == "Episode"
        let provider = raw.providerIds ?? [:]
        let contentID = ContentID(imdb: MediaServerIndexPolicy.imdb(provider["Imdb"]), tmdb: MediaServerIndexPolicy.tmdb(provider["Tmdb"]),
            addonItemID: "\(connection.kind.rawValue):\(connection.id.uuidString.lowercased()):\(raw.id)", type: isEpisode ? .series : .movie)
        let playback = try MediaServerIndexPolicy.endpoint(base: connection.baseURL, components: ["Videos", raw.id, "stream"], query: ["static": "true", "api_key": token])
        let image = try MediaServerIndexPolicy.endpoint(base: connection.baseURL, components: ["Items", raw.id, "Images", "Primary"], query: ["maxWidth": "1000", "quality": "90", "api_key": token])
        let backdrop = raw.backdropImageTags?.isEmpty == false ? try MediaServerIndexPolicy.endpoint(base: connection.baseURL,
            components: ["Items", raw.id, "Images", "Backdrop", "0"], query: ["maxWidth": "1920", "quality": "90", "api_key": token]) : image
        let episode = isEpisode ? EpisodeRef(season: max(0, raw.parentIndexNumber ?? 0), number: max(0, raw.indexNumber ?? 0), episodeTitle: raw.name) : nil
        var metadata = MediaMetadata(filename: raw.path.map { ($0 as NSString).lastPathComponent },
            season: raw.parentIndexNumber, episode: raw.indexNumber, year: raw.productionYear,
            mediaServerID: connection.id, mediaServerItemID: raw.id)
        let video = raw.mediaSources?.lazy.compactMap { $0.mediaStreams?.first(where: { $0.type == "Video" }) }.first
        metadata.codec = video?.codec; metadata.resolution = video?.displayTitle
        return MediaItem(title: raw.name, sourceType: connection.kind.sourceType, playbackURL: playback, posterURL: image, backdropURL: backdrop,
            duration: raw.runTimeTicks.map { Double($0) / 10_000_000 }, legalAccessConfirmed: true,
            metadata: metadata, contentID: contentID, episode: episode, seriesTitle: raw.seriesName)
    }

    private func indexPlex(_ connection: MediaServerConnection, token: String) async throws -> MediaServerIndexResult {
        let sections: PlexSections = try await decode(baseURL: connection.baseURL, path: ["library", "sections"], headers: plexHeaders(token))
        let libraries = sections.mediaContainer.directory.filter { $0.type == "movie" || $0.type == "show" }.map {
            MediaServerLibrary(id: $0.key, name: $0.title, kind: $0.type)
        }
        let selected = try MediaServerIndexPolicy.selectedLibraries(available: libraries.map(\.id),
            known: sections.mediaContainer.directory.map(\.key), selected: connection.selectedLibraryIDs)
        var all: [MediaItem] = [], seenItems = Set<String>()
        for library in libraries where selected.contains(library.id) {
            var pager = MediaServerIndexPolicy.Pager()
            var more = true
            while more {
                try Task.checkCancellation()
                let page: PlexMetadataPage = try await decode(baseURL: connection.baseURL,
                    path: ["library", "sections", library.id, "all"], headers: plexHeaders(token),
                    query: ["includeGuids": "1", "type": library.kind == "show" ? "4" : "1", "sort": "titleSort:asc",
                            "X-Plex-Container-Start": String(pager.offset), "X-Plex-Container-Size": String(pager.pageSize)])
                let records = page.mediaContainer.metadata
                // `size` describes this page; it is not the library total.
                more = try pager.accept(ids: records.map(\.ratingKey), total: page.mediaContainer.totalSize, returnedOffset: page.mediaContainer.offset)
                for raw in records where seenItems.insert(raw.ratingKey).inserted {
                    guard seenItems.count <= MediaServerIndexPolicy.maximumItems else { throw MediaServerError.responseTooLarge }
                    if let item = try plexItem(raw, connection: connection, token: token) { all.append(item) }
                }
                guard all.count <= MediaServerIndexPolicy.maximumItems else { throw MediaServerError.responseTooLarge }
            }
        }
        try Task.checkCancellation()
        return MediaServerIndexResult(libraries: libraries, items: all)
    }

    private func plexItem(_ raw: PlexMetadata, connection: MediaServerConnection, token: String) throws -> MediaItem? {
        guard raw.type == "movie" || raw.type == "episode" else { return nil }
        // A missing first media version must not hide a playable later version.
        guard let media = raw.media?.first(where: { $0.part?.contains(where: { !$0.key.isEmpty }) == true }),
              let part = media.part?.first(where: { !$0.key.isEmpty }) else { return nil }
        let isEpisode = raw.type == "episode", guids = raw.guid ?? []
        let imdb = guids.lazy.compactMap { $0.id.hasPrefix("imdb://") ? MediaServerIndexPolicy.imdb(String($0.id.dropFirst(7))) : nil }.first
        let tmdb = guids.lazy.compactMap { $0.id.hasPrefix("tmdb://") ? MediaServerIndexPolicy.tmdb(String($0.id.dropFirst(7))) : nil }.first
        let contentID = ContentID(imdb: imdb, tmdb: tmdb, addonItemID: "plex:\(connection.id.uuidString.lowercased()):\(raw.ratingKey)", type: isEpisode ? .series : .movie)
        func serverURL(_ path: String?) throws -> URL? {
            guard let path, !path.isEmpty else { return nil }
            return try MediaServerIndexPolicy.resource(base: connection.baseURL, path: path, token: token)
        }
        let metadata = MediaMetadata(filename: part.file.map { ($0 as NSString).lastPathComponent },
            fileSize: part.size.flatMap { $0 >= 0 ? $0 : nil }, resolution: media.videoResolution,
            season: raw.parentIndex, episode: raw.index, year: raw.year,
            mediaServerID: connection.id, mediaServerItemID: raw.ratingKey)
        return MediaItem(title: raw.title, sourceType: .plex,
            playbackURL: try MediaServerIndexPolicy.resource(base: connection.baseURL, path: part.key, token: token),
            posterURL: try serverURL(raw.thumb), backdropURL: try serverURL(raw.art ?? raw.grandparentThumb),
            duration: raw.duration.map { Double($0) / 1000 }, legalAccessConfirmed: true, metadata: metadata, contentID: contentID,
            episode: isEpisode ? EpisodeRef(season: max(0, raw.parentIndex ?? 0), number: max(0, raw.index ?? 0), episodeTitle: raw.title) : nil, seriesTitle: raw.grandparentTitle)
    }

    private func embyHeaders(_ token: String?) -> [String: String] {
        var headers = ["X-Emby-Authorization": "MediaBrowser Client=Nova, Device=Apple, DeviceId=nova, Version=1.0"]
        if let token { headers["X-Emby-Token"] = token }; return headers
    }
    private func plexHeaders(_ token: String) -> [String: String] {
        ["X-Plex-Token": token, "X-Plex-Product": "Nova", "X-Plex-Client-Identifier": "nova-apple", "X-Plex-Version": "1.0", "Accept": "application/json"]
    }
    private func decode<T: Decodable>(baseURL: URL, path: [String], headers: [String: String], query: [String: String] = [:], method: String = "GET", body: Data? = nil) async throws -> T {
        let url = try MediaServerIndexPolicy.endpoint(base: baseURL, components: path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (bytes, response) = try await session.bytes(for: request, delegate: MediaServerRedirectDelegate(origin: url))
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw MediaServerError.unsupportedResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw MediaServerError.unauthorized }
        guard http.statusCode == 200 else { throw MediaServerError.http(http.statusCode) }
        guard response.expectedContentLength <= MediaServerIndexPolicy.maximumResponseBytes else { throw MediaServerError.responseTooLarge }
        var payload = Data()
        if response.expectedContentLength > 0 { payload.reserveCapacity(Int(response.expectedContentLength)) }
        for try await byte in bytes {
            guard payload.count < MediaServerIndexPolicy.maximumResponseBytes else { throw MediaServerError.responseTooLarge }
            payload.append(byte)
            if payload.count % (64 * 1024) == 0 { try Task.checkCancellation() }
        }
        try Task.checkCancellation()
        do { return try JSONDecoder().decode(T.self, from: payload) }
        catch { throw MediaServerError.unsupportedResponse }
    }
}

private struct PlexIdentity: Decodable {
    struct Container: Decodable { var machineIdentifier: String }
    var mediaContainer: Container
    enum CodingKeys: String, CodingKey { case mediaContainer = "MediaContainer" }
}
