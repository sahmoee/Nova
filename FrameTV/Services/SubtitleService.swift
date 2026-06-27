//
//  SubtitleService.swift
//  FrameTV
//
//  Subtitle discovery from two places:
//    1. Stremio addons that expose a subtitles resource (handled by the caller
//       via StremioAddonClient and merged here).
//    2. OpenSubtitles REST API (when an API key is configured).
//  Plus a converter so SRT subtitles play through AVPlayer (which prefers VTT
//  for sideloaded text tracks).
//

import Foundation

// MARK: - OpenSubtitles

enum OpenSubtitlesError: LocalizedError {
    case missingKey
    case network(Error)
    case http(Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .missingKey:     return "No OpenSubtitles API key set. Add one in Settings to fetch subtitles."
        case .network(let e): return "Network error contacting OpenSubtitles: \(e.localizedDescription)"
        case .http(let c):    return "OpenSubtitles request failed (HTTP \(c))."
        case .decoding:       return "Couldn't read the OpenSubtitles response."
        }
    }
}

actor OpenSubtitlesClient {

    private static let base = URL(string: "https://api.opensubtitles.com/api/v1")!
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let keyProvider: @Sendable () -> String?

    init(session: URLSession = .shared,
         keyProvider: @escaping @Sendable () -> String? = { AppConfig.shared.openSubtitlesKey }) {
        self.session = session
        self.keyProvider = keyProvider
    }

    var hasKey: Bool { keyProvider()?.isEmpty == false }

    /// Searches subtitles by IMDB id (and optional season/episode), returning
    /// tracks with a download URL ready to fetch.
    func search(imdbID: String,
                episode: EpisodeRef?,
                languages: [String]) async throws -> [SubtitleTrack] {
        guard let key = keyProvider(), !key.isEmpty else { throw OpenSubtitlesError.missingKey }

        // Numeric IMDB id (strip the leading "tt").
        let numericID = imdbID.replacingOccurrences(of: "tt", with: "")
        var query: [String: String] = [
            "imdb_id": numericID,
            "languages": languages.joined(separator: ",")
        ]
        if let episode {
            query["season_number"] = String(episode.season)
            query["episode_number"] = String(episode.number)
        }

        var comps = URLComponents(url: Self.base.appendingPathComponent("subtitles"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }

        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 25
        req.setValue(key, forHTTPHeaderField: "Api-Key")
        req.setValue("FrameTV v1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw OpenSubtitlesError.network(error)
        }
        guard let http = response as? HTTPURLResponse else { throw OpenSubtitlesError.http(-1) }
        guard (200...299).contains(http.statusCode) else { throw OpenSubtitlesError.http(http.statusCode) }

        let result: OSSearchResponse
        do { result = try decoder.decode(OSSearchResponse.self, from: data) }
        catch { throw OpenSubtitlesError.decoding(error) }

        return (result.data ?? []).compactMap { entry in
            let attrs = entry.attributes
            guard let fileID = attrs?.files?.first?.fileId else { return nil }
            let lang = attrs?.language ?? "und"
            // We store the file id; the actual download URL is requested on demand.
            return SubtitleTrack(
                id: "os:\(fileID)",
                language: lang,
                languageDisplay: LanguageNames.display(for: lang),
                url: nil,  // resolved via requestDownload when selected
                isEmbedded: false,
                source: "OpenSubtitles"
            )
        }
    }

    /// Requests a temporary download URL for an OpenSubtitles file id.
    func requestDownload(fileID: Int) async throws -> URL {
        guard let key = keyProvider(), !key.isEmpty else { throw OpenSubtitlesError.missingKey }
        let url = Self.base.appendingPathComponent("download")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 25
        req.setValue(key, forHTTPHeaderField: "Api-Key")
        req.setValue("FrameTV v1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["file_id": fileID])

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OpenSubtitlesError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let resp = try decoder.decode(OSDownloadResponse.self, from: data)
        guard let link = resp.link, let url = URL(string: link) else {
            throw OpenSubtitlesError.decoding(NSError(domain: "os", code: 0))
        }
        return url
    }
}

// MARK: - OpenSubtitles response shapes

private struct OSSearchResponse: Codable {
    let data: [OSEntry]?
}
private struct OSEntry: Codable {
    let attributes: OSAttributes?
}
private struct OSAttributes: Codable {
    let language: String?
    let files: [OSFile]?
}
private struct OSFile: Codable {
    let fileId: Int?
    enum CodingKeys: String, CodingKey { case fileId = "file_id" }
}
private struct OSDownloadResponse: Codable {
    let link: String?
}

// MARK: - Subtitle conversion

enum SubtitleConverter {

    /// Converts SRT text to WebVTT, which AVPlayer handles well for sideloaded
    /// text tracks. If the input already looks like VTT, it's returned as-is.
    static func srtToVTT(_ srt: String) -> String {
        if srt.hasPrefix("WEBVTT") { return srt }

        var out = "WEBVTT\n\n"
        // SRT uses comma decimal separators in timestamps; VTT uses dots.
        // Also drop the numeric counter lines.
        let blocks = srt.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard !lines.isEmpty else { continue }

            var idx = 0
            // Skip a leading numeric counter line if present.
            if idx < lines.count, Int(lines[idx].trimmingCharacters(in: .whitespaces)) != nil {
                idx += 1
            }
            guard idx < lines.count else { continue }

            let timing = lines[idx].replacingOccurrences(of: ",", with: ".")
            idx += 1
            let text = lines[idx...].joined(separator: "\n")

            if timing.contains("-->") {
                out += timing + "\n" + text + "\n\n"
            }
        }
        return out
    }
}
