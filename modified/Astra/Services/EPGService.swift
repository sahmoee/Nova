//
//  EPGService.swift
//  Astra
//
//  Minimal XMLTV (EPG) support for Live TV: downloads a guide, indexes the
//  programmes, and answers "what's on <channel> right now". Only plain XML guides
//  are supported (no .gz); guides are cached in memory for an hour.
//

import Foundation

actor EPGService {
    static let shared = EPGService()

    struct Programme {
        let channelID: String
        let title: String
        let start: Date
        let stop: Date
    }

    private var programmesByChannel: [String: [Programme]] = [:]
    private var loadedGuides: [URL: Date] = [:]
    private let guideTTL: TimeInterval = 60 * 60   // 1 hour

    /// Loads (or re-loads, if stale) an XMLTV guide and merges its programmes.
    func loadGuide(from url: URL) async {
        if let loaded = loadedGuides[url], Date().timeIntervalSince(loaded) < guideTTL { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        guard let (data, response) = try? await AppNetworking.shared.data(for: req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return }
        let parsed = XMLTVParser.parse(data)
        guard !parsed.isEmpty else { return }
        // FIX: replace (not append to) the programme lists for channels covered by
        // this guide. Re-loading after the TTL expired previously appended the same
        // programmes again, so lists grew with duplicates on every refresh.
        for key in Set(parsed.map(\.channelID)) {
            programmesByChannel[key] = []
        }
        for programme in parsed {
            programmesByChannel[programme.channelID, default: []].append(programme)
        }
        for key in Set(parsed.map(\.channelID)) {
            programmesByChannel[key]?.sort { $0.start < $1.start }
        }
        loadedGuides[url] = Date()
    }

    /// The programme airing now on a channel (matched by XMLTV/tvg id), if known.
    func nowPlaying(tvgID: String?) -> String? {
        guard let tvgID, let programmes = programmesByChannel[tvgID] else { return nil }
        let now = Date()
        return programmes.first(where: { $0.start <= now && now < $0.stop })?.title
    }

    /// Batch lookup for a whole channel list (one actor hop for the UI).
    func nowPlaying(tvgIDs: [String]) -> [String: String] {
        var out: [String: String] = [:]
        let now = Date()
        for id in tvgIDs {
            if let programmes = programmesByChannel[id],
               let current = programmes.first(where: { $0.start <= now && now < $0.stop }) {
                out[id] = current.title
            }
        }
        return out
    }
}

// MARK: - XMLTV parsing

/// A small streaming parser for XMLTV <programme> elements. Ignores everything
/// else in the guide; tolerant of missing fields.
private final class XMLTVParser: NSObject, XMLParserDelegate {

    static func parse(_ data: Data) -> [EPGService.Programme] {
        let delegate = XMLTVParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.programmes
    }

    private var programmes: [EPGService.Programme] = []
    private var currentChannel: String?
    private var currentStart: Date?
    private var currentStop: Date?
    private var currentTitle = ""
    private var insideTitle = false

    /// XMLTV timestamps look like "20260708193000 +0000" (offset optional).
    /// Built once from a pure closure and only read afterward. `DateFormatter` is
    /// `Sendable`, so this immutable array needs no `nonisolated(unsafe)`.
    private static let formats: [DateFormatter] = {
        ["yyyyMMddHHmmss Z", "yyyyMMddHHmmss"].map { fmt in
            let f = DateFormatter()
            f.dateFormat = fmt
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            return f
        }
    }()

    private static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        for f in formats {
            if let d = f.date(from: raw) { return d }
        }
        return nil
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "programme":
            currentChannel = attributes["channel"]
            currentStart = Self.date(attributes["start"])
            currentStop = Self.date(attributes["stop"])
            currentTitle = ""
        case "title":
            insideTitle = currentChannel != nil
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideTitle { currentTitle += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        switch name {
        case "title":
            insideTitle = false
        case "programme":
            if let channel = currentChannel, let start = currentStart, let stop = currentStop,
               !currentTitle.isEmpty {
                programmes.append(EPGService.Programme(
                    channelID: channel,
                    title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    start: start, stop: stop))
            }
            currentChannel = nil; currentStart = nil; currentStop = nil; currentTitle = ""
        default:
            break
        }
    }
}
