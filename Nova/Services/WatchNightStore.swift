import Foundation
import Combine
import CryptoKit

actor WatchNightDisk {
    let fileURL: URL
    init(fileURL: URL) { self.fileURL = fileURL }
    func load() throws -> WatchNightState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return WatchNightState() }
        let handle = try FileHandle(forReadingFrom: fileURL); defer { try? handle.close() }
        let data = try handle.read(upToCount: 4_194_305) ?? Data()
        guard data.count <= 4_194_304 else { throw WatchNightError.invalid("The saved Watch Night file exceeds its supported size. The original file has been kept.") }
        let value = try JSONDecoder().decode(WatchNightState.self, from: data)
        try value.validate(); return value
    }
    func delete() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
    }
    func save(_ value: WatchNightState) throws {
        try value.validate()
        let data = try JSONEncoder().encode(value)
        guard data.count <= 4_194_304 else { throw WatchNightError.invalid("Watch Night has reached its storage limit. Remove an unused plan or note first.") }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS) || os(tvOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: [.atomic])
        #endif
    }
}

/// This device owns these plans and notes. It does not mirror private notes to iCloud or a Worker.
@MainActor
final class WatchNightStore: ObservableObject {
    static let shared = WatchNightStore()
    @Published private(set) var state = WatchNightState()
    @Published private(set) var titles: [WatchNightTitle] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isSaving = false
    @Published private(set) var isIndexing = false
    @Published private(set) var loadFailed = false
    @Published var error: String?
    @Published private(set) var titleRevision = 0
    @Published private(set) var resetRevision = UUID()
    private let disk: WatchNightDisk
    private var indexTask: Task<Void, Never>?
    private var loadInFlight = false
    private var titleItems: [String: MediaItem] = [:]
    var canEdit: Bool { !isLoading && !isSaving && !loadFailed }
    init(fileURL: URL? = nil) {
        let url = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("watch-night.json")
        disk = WatchNightDisk(fileURL: url)
        Task { await reload() }
    }
    func reload() async {
        guard !isSaving, !loadInFlight else { return }
        loadInFlight = true; isLoading = true
        defer { isLoading = false; loadInFlight = false }
        do { state = try await disk.load(); loadFailed = false; error = nil }
        catch { loadFailed = true; self.error = "Watch Night could not open its saved data. Your file is unchanged. Try loading again; existing library and playback are unaffected." }
    }
    @discardableResult
    func update(_ change: (inout WatchNightState) throws -> Void) async -> Bool {
        guard canEdit else { return false }
        var next = state
        do {
            try change(&next); try next.validate()
            isSaving = true; defer { isSaving = false }
            try await disk.save(next)
            state = next; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func savePlan(_ plan: WatchNightPlan) async -> Bool {
        await update { state in
            if let index = state.plans.firstIndex(where: { $0.id == plan.id }) { state.plans[index] = plan }
            else { state.plans.append(plan) }
        }
    }
    func saveNote(_ note: WatchNightNote) async -> Bool {
        await update { state in
            if let index = state.notes.firstIndex(where: { $0.id == note.id }) { state.notes[index] = note }
            else { state.notes.append(note) }
        }
    }
    /// Used only by explicit Library reset/delete actions. It also removes an unreadable saved file.
    func deleteAllLocalData() async -> Bool {
        guard !isSaving, !loadInFlight else {
            error = "Watch Night is saving or loading. Wait for it to finish, then try deleting again."; return false
        }
        isSaving = true; defer { isSaving = false; isLoading = false }
        do {
            try await disk.delete()
            state = WatchNightState(); resetRevision = UUID(); loadFailed = false; error = nil; return true
        } catch { self.error = "Watch Night plans and private notes could not be deleted. Please try again."; return false }
    }
    func mediaItem(for titleID: String) -> MediaItem? { titleItems[titleID] }
    func refreshLibrary(_ items: [MediaItem]) {
        indexTask?.cancel(); isIndexing = true
        indexTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            let child = Task.detached(priority: .userInitiated) {
                var titles: [WatchNightTitle] = []
                var mapping: [String: MediaItem] = [:]
                for item in items where !item.isHidden && item.sourceType != .liveTV && item.contentID?.type != .tv {
                    if Task.isCancelled { break }
                    let id = SHA256.hash(data: Data(item.contentKey.utf8)).map { String(format: "%02x", $0) }.joined()
                    guard mapping[id] == nil else { continue }
                    mapping[id] = item
                    var portableID: String?
                    if let imdb = item.contentID?.imdb, imdb.range(of: "^tt[0-9]{1,12}$", options: .regularExpression) != nil { portableID = "imdb:\(imdb)" }
                    else if let tmdb = item.contentID?.tmdb, tmdb > 0 { portableID = "tmdb:\(item.isSeries ? "series" : "movie"):\(tmdb)" }
                    if let episode = item.episode, let key = portableID { portableID = "\(key)|s\(episode.season)e\(episode.number)" }
                    if let key = portableID, !WatchNightPlan.validPortableID(key) { portableID = nil }
                    let duration = item.duration.flatMap { $0.isFinite && $0 > 0 && $0 <= 86400 ? $0 : nil }
                    let remaining = duration.flatMap { duration -> Double? in
                        guard item.hasResumePoint else { return nil }
                        return max(0, duration - item.lastPlayedPosition)
                    }
                    titles.append(WatchNightTitle(id: id, portableID: portableID, title: item.displayTitle,
                        year: item.metadata.year, duration: duration, remaining: remaining,
                        source: item.sourceType.displayName, isWatched: item.isWatched, isSeries: item.isSeries,
                        isFavorite: item.isFavorite, posterURL: item.posterURL))
                }
                if !Task.isCancelled {
                    titles.sort { $0.title == $1.title ? $0.id < $1.id : $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                }
                return (titles, mapping)
            }
            let projection = await withTaskCancellationHandler(operation: { await child.value }, onCancel: { child.cancel() })
            guard let self, !Task.isCancelled else { return }
            if self.titles != projection.0 { self.titles = projection.0; self.titleRevision &+= 1 }
            self.titleItems = projection.1; self.isIndexing = false
        }
    }
    static func readPortable(_ url: URL) async throws -> WatchNightPlan {
        try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            return try WatchNightPortablePlan.decode(handle.read(upToCount: WatchNightPortablePlan.maximumBytes + 1) ?? Data())
        }.value
    }
}
