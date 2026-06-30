//
//  AppConfig.swift
//  FrameTV
//
//  Credential resolution with a two-tier strategy:
//    1. In-app values stored in the Keychain (set via Settings) take priority.
//    2. A bundled/Documents `FrameTVConfig.json` provides fallback defaults.
//
//  This lets a user either type credentials into Settings or drop a config file
//  next to the app (handy for sideloaded / self-hosted setups).
//

import Foundation

/// Keys for the various credentials FrameTV can use.
enum CredentialKey: String, CaseIterable {
    case tmdbAPIKey = "tmdb.apiKey"
    case traktClientID = "trakt.clientId"
    case traktClientSecret = "trakt.clientSecret"
    case traktAccessToken = "trakt.accessToken"
    case traktRefreshToken = "trakt.refreshToken"
    case openSubtitlesAPIKey = "opensubtitles.apiKey"
    case omdbAPIKey = "omdb.apiKey"
}

/// Shape of the optional FrameTVConfig.json fallback file.
struct FrameTVConfigFile: Codable {
    var tmdbApiKey: String?
    var traktClientId: String?
    var traktClientSecret: String?
    var openSubtitlesApiKey: String?
    var omdbApiKey: String?
    /// Optional list of addon manifest URLs to preinstall on first run.
    var addonManifestURLs: [String]?
    /// Optional Cloudflare Worker URL for Claude-powered AI search.
    var aiWorkerUrl: String?
}

final class AppConfig {

    static let shared = AppConfig()

    private let keychain = KeychainStore.shared
    private(set) var fileConfig: FrameTVConfigFile?

    private init() {
        loadFileConfig()
    }

    // MARK: - Config file

    /// Looks for FrameTVConfig.json first in the app bundle, then in the app's
    /// Documents directory (so it can be dropped in via file sharing).
    private func loadFileConfig() {
        let decoder = JSONDecoder()

        if let bundleURL = Bundle.main.url(forResource: "FrameTVConfig", withExtension: "json"),
           let data = try? Data(contentsOf: bundleURL),
           let cfg = try? decoder.decode(FrameTVConfigFile.self, from: data) {
            fileConfig = cfg
            return
        }

        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first
        if let docs {
            let docURL = docs.appendingPathComponent("FrameTVConfig.json")
            if let data = try? Data(contentsOf: docURL),
               let cfg = try? decoder.decode(FrameTVConfigFile.self, from: data) {
                fileConfig = cfg
            }
        }
    }

    func reloadFileConfig() { loadFileConfig() }

    // MARK: - Credential access (Keychain first, then config file)

    func value(for key: CredentialKey) -> String? {
        if let stored = keychain.get(key.rawValue), !stored.isEmpty {
            return stored
        }
        return fileFallback(for: key)
    }

    private func fileFallback(for key: CredentialKey) -> String? {
        guard let fileConfig else { return nil }
        switch key {
        case .tmdbAPIKey:            return nonEmpty(fileConfig.tmdbApiKey)
        case .traktClientID:         return nonEmpty(fileConfig.traktClientId)
        case .traktClientSecret:     return nonEmpty(fileConfig.traktClientSecret)
        case .openSubtitlesAPIKey:   return nonEmpty(fileConfig.openSubtitlesApiKey)
        case .omdbAPIKey:            return nonEmpty(fileConfig.omdbApiKey)
        case .traktAccessToken, .traktRefreshToken:
            return nil   // tokens are runtime-only, never from the static file
        }
    }

    private func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }

    // MARK: - Setters (Keychain)

    func set(_ value: String?, for key: CredentialKey) {
        if let value, !value.isEmpty {
            try? keychain.set(value, for: key.rawValue)
        } else {
            try? keychain.delete(key.rawValue)
        }
    }

    func isPresent(_ key: CredentialKey) -> Bool {
        value(for: key) != nil
    }

    // MARK: - Convenience

    var tmdbKey: String? { value(for: .tmdbAPIKey) }
    var traktClientID: String? { value(for: .traktClientID) }
    var traktClientSecret: String? { value(for: .traktClientSecret) }
    var openSubtitlesKey: String? { value(for: .openSubtitlesAPIKey) }
    var omdbKey: String? { value(for: .omdbAPIKey) }

    /// Addon manifest URLs to seed on first run, from the config file (if any).
    var seedAddonURLs: [URL] {
        (fileConfig?.addonManifestURLs ?? []).compactMap { URL(string: $0) }
    }

    /// Optional Worker URL for AI search, from the config file (user setting wins).
    var aiWorkerURL: String? {
        let v = fileConfig?.aiWorkerUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (v?.isEmpty == false) ? v : nil
    }
}
