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
    var isEnabled: Bool
    var addedDate: Date

    init(
        id: UUID = UUID(),
        manifestURL: URL,
        name: String,
        version: String? = nil,
        description: String? = nil,
        resources: [String] = [],
        types: [String] = [],
        isEnabled: Bool = true,
        addedDate: Date = Date()
    ) {
        self.id = id
        self.manifestURL = manifestURL
        self.name = name
        self.version = version
        self.description = description
        self.resources = resources
        self.types = types
        self.isEnabled = isEnabled
        self.addedDate = addedDate
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

// MARK: - Preset addons (prefill helpers)

enum AddonPreset: String, CaseIterable, Identifiable {
    case aioStreams
    case comet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aioStreams: return "AIOStreams"
        case .comet:      return "Comet"
        }
    }

    var blurb: String {
        switch self {
        case .aioStreams:
            return "Aggregates multiple stream providers behind one addon. Paste your configured AIOStreams manifest URL."
        case .comet:
            return "A fast stream resolver addon. Paste your configured Comet manifest URL."
        }
    }

    /// A hint URL template shown as a placeholder. Users supply their own
    /// configured instance URL (these addons require a per-user config path).
    var placeholderURL: String {
        switch self {
        case .aioStreams: return "https://aiostreams.<your-host>/<config>/manifest.json"
        case .comet:      return "https://comet.<your-host>/<config>/manifest.json"
        }
    }

    var systemImage: String {
        switch self {
        case .aioStreams: return "square.stack.3d.up"
        case .comet:      return "sparkles"
        }
    }
}
