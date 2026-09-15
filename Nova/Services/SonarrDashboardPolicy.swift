import Foundation

struct SonarrSeries: Decodable, Identifiable, Sendable {
    let id: Int
    let title: String
    let monitored: Bool
    let statistics: Statistics?
    struct Statistics: Decodable, Sendable {
        let episodeCount: Int?
        let episodeFileCount: Int?
        let totalEpisodeCount: Int?
        let sizeOnDisk: Int64?
    }
    var missing: Int? { SonarrDashboardPolicy.missing(expected: statistics?.episodeCount, files: statistics?.episodeFileCount) }
}

struct SonarrEpisode: Decodable, Identifiable, Sendable {
    let id: Int
    let seriesId: Int
    let seasonNumber: Int
    let episodeNumber: Int
    let title: String
    let airDateUtc: Date?
    let hasFile: Bool
    let monitored: Bool
}

struct SonarrQueueItem: Decodable, Identifiable, Sendable {
    let id: Int
    let title: String?
    let status: String?
    let trackedDownloadStatus: String?
    let errorMessage: String?
    let size: Double?
    let sizeleft: Double?
    let timeleft: String?
    let estimatedCompletionTime: Date?
    let downloadClient: String?
    let statusMessages: [StatusMessage]?
    struct StatusMessage: Decodable, Sendable { let title: String?; let messages: [String]? }
    var progress: Double? { SonarrDashboardPolicy.progress(size: size, remaining: sizeleft) }
    var hasWarning: Bool {
        ["warning", "error"].contains(trackedDownloadStatus?.lowercased() ?? "") || errorMessage?.isEmpty == false
    }
}

enum SonarrSeriesFilter: String, CaseIterable, Identifiable {
    case all = "All series", monitored = "Monitored", missing = "Missing episodes", complete = "Files complete"
    var id: String { rawValue }
}
enum SonarrSeriesSort: String, CaseIterable, Identifiable {
    case title = "Title", missing = "Most missing", files = "Most files"
    var id: String { rawValue }
}
enum SonarrFileFilter: String, CaseIterable, Identifiable {
    case all = "Any availability", available = "File available", missing = "No file yet"
    var id: String { rawValue }
}
enum SonarrMonitoringFilter: String, CaseIterable, Identifiable {
    case all = "All monitoring", monitored = "Monitored", unmonitored = "Unmonitored"
    var id: String { rawValue }
}

enum SonarrDashboardPolicy {
    static func serverURL(_ address: String) -> URL? {
        guard var parts = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else { return nil }
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        return parts.url
    }

    static func missing(expected: Int?, files: Int?) -> Int? {
        guard let expected, let files, expected >= 0, files >= 0 else { return nil }
        return max(0, expected - files)
    }

    static func progress(size: Double?, remaining: Double?) -> Double? {
        guard let size, let remaining, size.isFinite, remaining.isFinite,
              size > 0, remaining >= 0, remaining <= size else { return nil }
        return (size - remaining) / size
    }

    static func filterSeries(_ series: [SonarrSeries], query: String, filter: SonarrSeriesFilter, sort: SonarrSeriesSort) -> [SonarrSeries] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return series.filter { item in
            guard search.isEmpty || item.title.localizedStandardContains(search) else { return false }
            switch filter {
            case .all: return true
            case .monitored: return item.monitored
            case .missing: return (item.missing ?? 0) > 0
            case .complete: return item.missing == 0 && (item.statistics?.episodeCount ?? 0) > 0
            }
        }.sorted { lhs, rhs in
            switch sort {
            case .missing:
                let l = lhs.missing ?? -1, r = rhs.missing ?? -1
                if l != r { return l > r }
            case .files:
                let l = lhs.statistics?.episodeFileCount ?? -1, r = rhs.statistics?.episodeFileCount ?? -1
                if l != r { return l > r }
            case .title: break
            }
            let order = lhs.title.localizedStandardCompare(rhs.title)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
    }

    static func filterEpisodes(_ episodes: [SonarrEpisode], days: Int, monitoring: SonarrMonitoringFilter,
                               files: SonarrFileFilter, now: Date, calendar: Calendar = .current) -> [SonarrEpisode] {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: days, to: start) ?? start
        return episodes.filter { item in
            guard let date = item.airDateUtc, date >= start, date < end else { return false }
            if monitoring == .monitored && !item.monitored { return false }
            if monitoring == .unmonitored && item.monitored { return false }
            if files == .available && !item.hasFile { return false }
            if files == .missing && item.hasFile { return false }
            return true
        }.sorted {
            $0.airDateUtc == $1.airDateUtc ? $0.id < $1.id : ($0.airDateUtc ?? .distantFuture) < ($1.airDateUtc ?? .distantFuture)
        }
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid Sonarr date"))
        }
        return decoder
    }
}
