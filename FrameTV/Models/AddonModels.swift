//
//  AddonModels.swift
//  FrameTV
//
//  Models for Stremio-protocol addons. A user installs an addon by its manifest
//  URL; FrameTV then queries it for streams (and optionally subtitles/catalogs).
//  AIOStreams and Comet are ordinary addons that speak this same protocol, so a
//  generic client covers all three; presets just prefill the URL.
//

import Foundation

// MARK: - Installed addon

/// A user-installed addon. The transport URL points at the addon's manifest.json;
/// resource requests are built relative to its base.
struct InstalledAddon: Identifiable, Codable, Hashable {
    var id: UUID
    var manifestURL: URL
    var name: String
    var version: String?
    var description: String?
    var resources: [String]        // e.g. ["stream", "subtitles", "catalog", "meta"]
    var types: [String]            // e.g. ["movie", "series"]
    var catalogs: [AddonCatalogRef] // browsable catalogs (for live TV + shelves)
    var isEnabled: Bool
    var addedDate: Date
    /// Optional user-assigned category for grouping (e.g. "Movies", "Live TV").
    var category: String?
    /// Optional user tags for filtering.
    var tags: [String]

    init(
        id: UUID = UUID(),
        manifestURL: URL,
        name: String,
        version: String? = nil,
        description: String? = nil,
        resources: [String] = [],
        types: [String] = [],
        catalogs: [AddonCatalogRef] = [],
        isEnabled: Bool = true,
        addedDate: Date = Date(),
        category: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.manifestURL = manifestURL
        self.name = name
        self.version = version
        self.description = description
        self.resources = resources
        self.types = types
        self.catalogs = catalogs
        self.isEnabled = isEnabled
        self.addedDate = addedDate
        self.category = category
        self.tags = tags
    }

    /// Tolerant decoder: older persisted addons predate `category` and `tags`, so
    /// those keys may be absent. Decode them if present, else use safe defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        manifestURL = try c.decode(URL.self, forKey: .manifestURL)
        name = try c.decode(String.self, forKey: .name)
        version = try c.decodeIfPresent(String.self, forKey: .version)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        resources = try c.decodeIfPresent([String].self, forKey: .resources) ?? []
        types = try c.decodeIfPresent([String].self, forKey: .types) ?? []
        catalogs = try c.decodeIfPresent([AddonCatalogRef].self, forKey: .catalogs) ?? []
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        addedDate = try c.decodeIfPresent(Date.self, forKey: .addedDate) ?? Date()
        category = try c.decodeIfPresent(String.self, forKey: .category)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    /// The base URL (manifest URL with the trailing manifest.json removed).
    var baseURL: URL {
        var s = manifestURL.absoluteString
        if let range = s.range(of: "/manifest.json", options: .backwards) {
            s.removeSubrange(range)
        }
        return URL(string: s) ?? manifestURL
    }

    func supports(resource: String) -> Bool {
        resources.contains { $0.caseInsensitiveCompare(resource) == .orderedSame }
    }

    /// Some addons require a secret/config token embedded in the URL path
    /// (AIOStreams, Comet). We keep that in the URL itself, so nothing extra to store.
    var requiresConfiguredURL: Bool {
        let host = manifestURL.host?.lowercased() ?? ""
        return host.contains("aiostreams") || host.contains("comet")
    }
}

// MARK: - Addon manifest (subset of the Stremio manifest schema)

struct AddonManifest: Codable, Hashable {
    let id: String
    let name: String
    let version: String?
    let description: String?
    let resources: [ManifestResource]?
    let types: [String]?
    let catalogs: [ManifestCatalog]?

    /// Normalized resource names ("stream", "subtitles", …) regardless of whether
    /// the manifest used the short string form or the object form.
    var resourceNames: [String] {
        guard let resources else { return [] }
        return resources.map { $0.name }
    }
}

/// Resources can be either a bare string ("stream") or an object
/// ({ name: "stream", types: [...] }). This decodes both.
struct ManifestResource: Codable, Hashable {
    let name: String
    let types: [String]?

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer().decode(String.self) {
            name = single
            types = nil
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        types = try c.decodeIfPresent([String].self, forKey: .types)
    }

    enum CodingKeys: String, CodingKey { case name, types }
}

struct ManifestCatalog: Codable, Hashable {
    let type: String
    let id: String
    let name: String?
}

/// A browsable catalog exposed by an addon (e.g. "Live TV", "Trending"). Stored on
/// the InstalledAddon so the app can offer it as a home shelf or a channel list.
struct AddonCatalogRef: Codable, Hashable, Identifiable {
    var type: String       // "tv", "movie", "series", "channel"
    var catalogID: String  // the addon's catalog id
    var name: String       // display name

    var id: String { "\(type)|\(catalogID)" }
    var isLiveTV: Bool { type == "tv" || type == "channel" }
}

// MARK: - Stream response

/// The shape of an addon's /stream/{type}/{id}.json response.
struct AddonStreamResponse: Codable {
    let streams: [AddonStream]?
}

/// A raw stream entry from an addon, before FrameTV parses/ranks it.
struct AddonStream: Codable {
    let name: String?
    let title: String?
    let description: String?      // some addons use description instead of title
    let url: String?
    let ytId: String?
    let infoHash: String?
    let fileIdx: Int?
    let behaviorHints: AddonBehaviorHints?

    enum CodingKeys: String, CodingKey {
        case name, title, description, url, ytId, infoHash, fileIdx, behaviorHints
    }
}

struct AddonBehaviorHints: Codable, Hashable {
    let bingeGroup: String?
    let notWebReady: Bool?
    let filename: String?
    let videoSize: Int64?
}

// MARK: - Subtitle response

struct AddonSubtitleResponse: Codable {
    let subtitles: [AddonSubtitle]?
}

struct AddonSubtitle: Codable {
    let id: String?
    let url: String?
    let lang: String?
    let SubEncoding: String?
}

// MARK: - Catalog responses (home shelves + live TV)

struct AddonCatalogResponse: Codable {
    let metas: [AddonMeta]?
}

/// A meta preview returned by a catalog. Maps to a CatalogItem for display.
struct AddonMeta: Codable {
    let id: String
    let type: String?
    let name: String?
    let poster: String?
    let background: String?
    let logo: String?
    let description: String?
    let releaseInfo: String?     // often a year or year range
    let imdbRating: String?
    let genres: [String]?

    func toCatalogItem(defaultType: String) -> CatalogItem? {
        let typeStr = type ?? defaultType
        let contentType: ContentType = {
            switch typeStr {
            case "movie": return .movie
            case "series": return .series
            case "tv", "channel": return .tv
            default: return .movie
            }
        }()

        // Build a content id. Live channels and addon-specific ids use the raw id;
        // IMDB-style ids (tt...) populate the imdb field for cross-service linking.
        var cid: ContentID
        if id.hasPrefix("tt") {
            cid = ContentID(imdb: id, type: contentType)
        } else {
            cid = ContentID(addonItemID: id, type: contentType)
        }

        let year = Int(releaseInfo?.prefix(4) ?? "")
        return CatalogItem(
            contentID: cid,
            title: name ?? id,
            overview: description,
            posterURL: URL(string: poster ?? logo ?? ""),
            backdropURL: URL(string: background ?? ""),
            year: year,
            rating: Double(imdbRating ?? ""),
            genres: genres ?? []
        )
    }
}

// MARK: - Preset addons (prefill helpers)

enum AddonPreset: String, CaseIterable, Identifiable {
    case aioStreams
    case mediaFusion
    case comet
    case torrentio
    case tmdb
    case iptvOrg
    case usaTV

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aioStreams:  return "AIOStreams"
        case .mediaFusion: return "MediaFusion"
        case .comet:       return "Comet"
        case .torrentio:   return "Torrentio"
        case .tmdb:        return "TMDB Catalogs"
        case .iptvOrg:     return "IPTV-org (Live TV)"
        case .usaTV:       return "USA TV (Live TV)"
        }
    }

    var blurb: String {
        switch self {
        case .aioStreams:
            return "Aggregates multiple stream providers into one clean, deduplicated, filterable list. The top pick. Needs a configured instance URL."
        case .mediaFusion:
            return "All-in-one movies, series, and live TV/sports. Works with Real-Debrid and other debrid services. Needs a configured instance URL."
        case .comet:
            return "A fast, lightweight stream resolver with built-in proxy streaming. Good secondary source. Needs a configured instance URL."
        case .torrentio:
            return "The long-standing torrent source addon. Pairs with your Real-Debrid account. Best configured on your own instance."
        case .tmdb:
            return "Adds trending, popular, top-rated, and upcoming catalog rows from TMDB for browsing."
        case .iptvOrg:
            return "Free, public live TV channels from the open-source iptv-org project. The safest live-TV source."
        case .usaTV:
            return "180+ live US channels (news, sports, entertainment) from public IPTV links."
        }
    }

    /// A directly-installable manifest URL when the addon offers a public instance
    /// that needs no per-user configuration. nil means the user supplies their own
    /// configured URL (most aggregators require a config path).
    var directURL: String? {
        switch self {
        case .torrentio: return "https://torrentio.strem.fun/manifest.json"
        default:         return nil
        }
    }

    var requiresOwnURL: Bool { directURL == nil }

    /// Step-by-step setup instructions shown in the add sheet.
    var steps: [String] {
        switch self {
        case .aioStreams:
            return [
                "Open aiostreams.elfhosted.com/configure in a browser.",
                "Choose your sources and a debrid provider if you have one.",
                "Copy the generated manifest URL it gives you.",
                "Paste it below and tap Install."
            ]
        case .mediaFusion:
            return [
                "Open the MediaFusion configure page in a browser.",
                "Pick your providers and add your debrid account if you have one.",
                "Copy the generated manifest URL.",
                "Paste it below and tap Install."
            ]
        case .comet:
            return [
                "Open comet.elfhosted.com/configure in a browser.",
                "Configure it and add your debrid account if you have one.",
                "Copy the generated manifest URL.",
                "Paste it below and tap Install."
            ]
        case .torrentio:
            return [
                "Tap Quick Add to install Torrentio, or open torrentio.strem.fun for a custom config.",
                "Connect Real-Debrid in Settings so it can return cached streams."
            ]
        case .tmdb:
            return [
                "Open the TMDB addon's configure page in a browser (search 'TMDB Stremio addon').",
                "Copy its manifest URL.",
                "Paste it below and tap Install for trending and popular catalog rows."
            ]
        case .iptvOrg:
            return [
                "Find the iptv-org Stremio addon manifest URL (from its GitHub or the community addons list).",
                "Paste it below and tap Install.",
                "Open Discover then Live TV to watch the free public channels."
            ]
        case .usaTV:
            return [
                "Find a USA TV addon manifest URL from the Stremio community addons list.",
                "Paste it below and tap Install.",
                "Open Discover ▸ Live TV to watch."
            ]
        }
    }

    /// The host used to expand a pasted bare config id / token into a full manifest
    /// URL, for aggregators whose configure page hands the user only an opaque id.
    /// nil means the user must paste a complete URL.
    var hostForBareConfig: String? {
        switch self {
        case .aioStreams: return "https://aiostreams.elfhosted.com"
        case .comet:      return "https://comet.elfhosted.com"
        default:          return nil
        }
    }

    /// A hint URL template shown as a placeholder.
    var placeholderURL: String {
        switch self {
        case .aioStreams:  return "https://aiostreams.elfhosted.com/<config>/manifest.json"
        case .mediaFusion: return "https://<mediafusion-host>/<config>/manifest.json"
        case .comet:       return "https://comet.elfhosted.com/<config>/manifest.json"
        case .usaTV:       return "https://<usa-tv-host>/manifest.json"
        default:           return "https://…/manifest.json"
        }
    }

    var systemImage: String {
        switch self {
        case .aioStreams:  return "square.stack.3d.up"
        case .mediaFusion: return "rectangle.stack.badge.play"
        case .comet:       return "sparkles"
        case .torrentio:   return "arrow.down.circle"
        case .tmdb:        return "film.stack"
        case .iptvOrg:     return "dot.radiowaves.left.and.right"
        case .usaTV:       return "tv"
        }
    }
}
