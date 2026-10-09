import Foundation

/// A device owns its own transfer snapshot. No paths, URLs, tokens, resume data,
/// or remote control actions cross the iCloud boundary.
struct OfflineDeviceSnapshot: Codable, Identifiable, Equatable {
    struct Transfer: Codable, Identifiable, Equatable {
        var id: UUID
        var title: String
        var state: DownloadLifecycleState
    }
    var id: UUID
    var platform: String
    var revision: Int
    var updatedAt: Date
    var totalCount: Int
    var transfers: [Transfer]
    static let keyPrefix = "cloud.offline.device."
    static let maximumBytes = 16_384
    static let maximumDevices = 8

    static func decode(_ data: Data, key: String) -> Self? {
        guard data.count <= maximumBytes, let value = try? JSONDecoder().decode(Self.self, from: data),
              key == keyPrefix + value.id.uuidString.lowercased(), value.revision >= 0,
              value.updatedAt.timeIntervalSince1970.isFinite,
              ["iPhone", "iPad", "Apple TV"].contains(value.platform),
              value.transfers.count <= 50, value.totalCount >= value.transfers.count,
              Set(value.transfers.map(\.id)).count == value.transfers.count,
              value.transfers.allSatisfy({ !$0.title.isEmpty && $0.title.count <= 120 }) else { return nil }
        return value
    }
}

/// The existing persisted values are unchanged; action permissions are shared by
/// the queue and tests so a completed file cannot accidentally be retried/deleted.
nonisolated enum DownloadLifecycleState: String, Codable, Sendable, CaseIterable {
    case queued, downloading, paused, complete, failed

    var canPause: Bool { self == .queued || self == .downloading }
    var canResume: Bool { self == .paused }
    var canRetry: Bool { self == .failed }
}

/// Shared, side-effect-free rules used by live networking, downloads and playback.
/// Keeping validation here lets the same rules run in native regression checks.
nonisolated enum MediaReliabilityPolicy {
    static func retryAfter(_ raw: String?, now: Date = Date()) -> TimeInterval? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if let seconds = Double(value) {
            return seconds.isFinite && seconds >= 0 ? seconds : nil
        }
        guard let date = httpDateFormatter.date(from: value) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }

    /// Built once: Retry-After is parsed on every throttled response.
    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    static func boundedInterval(_ value: TimeInterval, fallback: TimeInterval, maximum: TimeInterval = 300) -> TimeInterval {
        value.isFinite && value > 0 ? min(value, maximum) : fallback
    }

    /// A server cooldown is a lower bound. If the deadline cannot accommodate it,
    /// fail this operation instead of retrying before the provider permits it.
    static func retryDelay(backoff: TimeInterval, serverMinimum: TimeInterval?, remaining: TimeInterval,
                           jitter: Double) -> TimeInterval? {
        guard remaining.isFinite, remaining > 0, backoff.isFinite, backoff >= 0,
              jitter.isFinite, jitter > 0 else { return nil }
        let localDelay = backoff * min(max(jitter, 0.8), 1.2)
        let minimum = serverMinimum.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? 0
        let delay = max(localDelay, minimum)
        guard delay.isFinite, delay > 0, delay < remaining else { return nil }
        return delay
    }

    static func validDuration(_ duration: TimeInterval?) -> TimeInterval? {
        duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    static func validPosition(_ position: TimeInterval) -> TimeInterval {
        position.isFinite ? max(0, position) : 0
    }

    static func progress(position: TimeInterval, duration: TimeInterval?) -> Double {
        guard let duration = validDuration(duration), position.isFinite else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    static func canResume(position: TimeInterval, duration: TimeInterval?, isLive: Bool) -> Bool {
        guard !isLive, position.isFinite, position > 5 else { return false }
        guard let duration = validDuration(duration) else { return true }
        return position < max(duration - 0.75, 0)
    }

    static func downloadBackoff(failureCount: Int) -> TimeInterval? {
        guard (1...5).contains(failureCount) else { return nil }
        return min(pow(2, Double(failureCount - 1)), 30)
    }

    static func validDownloadResponse(status: Int?, bytes: Int64) -> Bool {
        guard let status, (200..<300).contains(status), status != 204, status != 205 else { return false }
        return bytes > 0
    }

    static func downloadableURL(_ url: URL) -> Bool {
        guard !["m3u", "m3u8", "mpd"].contains(url.pathExtension.lowercased()) else { return false }
        if url.isFileURL { return true }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return false }
        // URLSession saves a playlist, not its segments. Do not advertise that
        // network-dependent file as an offline movie.
        return true
    }

    static func downloadableMIME(_ mime: String?) -> Bool {
        guard let mime else { return true }
        return !["text/html", "application/json", "application/problem+json", "application/xml",
                 "text/xml", "application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl",
                 "audio/x-mpegurl", "application/dash+xml"].contains(mime.lowercased())
    }

    static func downloadExtension(_ raw: String) -> String {
        let value = raw.lowercased()
        return !value.isEmpty && value.count <= 16 && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").contains($0)
        } ? value : "media"
    }

    static func cleanupAge(_ age: TimeInterval) -> TimeInterval? {
        age.isFinite && age >= 0 ? age : nil
    }

    static func downloadProgress(received: Int64, expected: Int64) -> Double {
        expected > 0 ? min(max(Double(max(0, received)) / Double(expected), 0), 1) : 0
    }

    /// Persisted filenames are untrusted input (including backups). Only manager-
    /// owned direct children may be read/deleted; never follow a path out of scope.
    static func ownedFile(_ url: URL, in folder: URL) -> Bool {
        guard url.isFileURL else { return false }
        let parent = url.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent()
        return parent.path == folder.standardizedFileURL.resolvingSymlinksInPath().path
            && (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
            && !url.lastPathComponent.isEmpty && url.lastPathComponent != "." && url.lastPathComponent != ".."
    }

    static func resumeFilename(_ name: String?, id: UUID) -> String? {
        guard let name, name == "\(id.uuidString).resume" else { return nil }
        return name
    }

    static func ownedDownloadFile(_ url: URL, id: UUID, in folder: URL) -> Bool {
        ownedFile(url, in: folder) && url.deletingPathExtension().lastPathComponent == id.uuidString
    }
}
