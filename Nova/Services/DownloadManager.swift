import Foundation
import Combine

/// One durable transfer record. Optional metrics keep the v1 persistence format
/// backward-compatible while adding resume, rate, ETA, retry and update state.
struct OfflineDownload: Identifiable, Codable, Hashable, Sendable {
    enum State: String, Codable, Sendable, CaseIterable { case queued, downloading, paused, complete, failed }
    let id: UUID
    let mediaID: UUID
    let title: String
    let sourceURL: URL
    var localURL: URL?
    var progress: Double
    var receivedBytes: Int64
    var expectedBytes: Int64?
    var state: State
    var errorMessage: String?
    let createdAt: Date
    var completedAt: Date?
    var bytesPerSecond: Double?
    var estimatedSecondsRemaining: TimeInterval?
    var retryCount: Int?
    var resumeDataFilename: String?
    var lastUpdatedAt: Date?
}

/// A bounded, resumable queue using the same principles as Stocked's import engine:
/// atomic persistence, coalesced progress writes, durable partial work and fault isolation.
@MainActor
final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published private(set) var downloads: [OfflineDownload] = []
    @Published private(set) var availableStorageBytes: Int64?
    @Published private(set) var isNetworkAvailable = NetworkConditionMonitor.shared.isOnline

    private let legacyDefaultsKey = "offline.downloads.v1"
    private let store = CodableFileStore<[OfflineDownload]>(filename: "offline-downloads.json", prettyPrinted: false)
    private let maximumConcurrentDownloads = 2
    private var taskByID: [UUID: URLSessionDownloadTask] = [:]
    private var intentionalPauses = Set<UUID>()
    private var samples: [UUID: (Date, Int64)] = [:]
    private var persistTask: Task<Void, Never>?
    private var networkCancellable: AnyCancellable?

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = maximumConcurrentDownloads
        configuration.timeoutIntervalForResource = 86_400
        return URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue())
    }()

    override init() {
        super.init()
        downloads = loadPersisted().map(Self.recovered)
        reconcileFiles()
        refreshAvailableStorage()
        networkCancellable = NetworkConditionMonitor.shared.$isOnline
            .removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] online in
                self?.isNetworkAvailable = online
                if online { self?.pumpQueue() }
            }
        pumpQueue()
    }

    deinit { persistTask?.cancel() }

    var activeCount: Int { downloads.filter { $0.state == .downloading }.count }
    var queuedCount: Int { downloads.filter { $0.state == .queued }.count }
    var completedCount: Int { downloads.filter { $0.state == .complete }.count }
    var failedCount: Int { downloads.filter { $0.state == .failed }.count }
    var storageBytes: Int64 { downloads.filter { $0.state == .complete }.reduce(0) { $0 + $1.receivedBytes } }
    var aggregateProgress: Double {
        let pending = downloads.filter { [.queued, .downloading, .paused].contains($0.state) }
        return pending.isEmpty ? (completedCount > 0 ? 1 : 0) : pending.map(\.progress).reduce(0, +) / Double(pending.count)
    }

    func isEligible(_ item: MediaItem) -> Bool {
        guard item.legalAccessConfirmed, item.sourceType != .liveTV else { return false }
        return ["https", "http", "file"].contains(item.playbackURL.scheme?.lowercased() ?? "")
    }

    @discardableResult
    func enqueue(_ item: MediaItem) -> UUID? {
        guard isEligible(item) else { return nil }
        if let existing = downloads.first(where: {
            ($0.mediaID == item.id || $0.sourceURL == item.playbackURL) && $0.state != .failed
        }) { return existing.id }
        let id = UUID()
        downloads.append(OfflineDownload(id: id, mediaID: item.id, title: item.displayTitle,
            sourceURL: item.playbackURL, localURL: nil, progress: 0, receivedBytes: 0,
            expectedBytes: nil, state: .queued, errorMessage: nil, createdAt: Date(),
            completedAt: nil, bytesPerSecond: nil, estimatedSecondsRemaining: nil,
            retryCount: 0, resumeDataFilename: nil, lastUpdatedAt: Date()))
        persistNow()
        item.playbackURL.isFileURL ? copyLocalFile(id: id, source: item.playbackURL) : pumpQueue()
        return id
    }

    func pause(_ id: UUID) {
        guard let task = taskByID[id] else { update(id, immediate: true) { $0.state = .paused }; return }
        intentionalPauses.insert(id)
        task.cancel { [weak self] data in
            Task { @MainActor in
                guard let self else { return }
                self.taskByID.removeValue(forKey: id)
                let filename = data.flatMap { self.writeResumeData($0, id: id) }
                self.update(id, immediate: true) {
                    $0.state = .paused; $0.resumeDataFilename = filename; $0.errorMessage = nil
                    $0.bytesPerSecond = nil; $0.estimatedSecondsRemaining = nil
                }
                self.pumpQueue()
            }
        }
    }

    func resume(_ id: UUID) {
        guard downloads.contains(where: { $0.id == id }) else { return }
        update(id) { $0.state = .queued; $0.errorMessage = nil }
        pumpQueue()
    }

    func retry(_ id: UUID) {
        guard let record = downloads.first(where: { $0.id == id }) else { return }
        removeFiles(record)
        update(id, immediate: true) {
            $0.progress = 0; $0.receivedBytes = 0; $0.expectedBytes = nil; $0.errorMessage = nil
            $0.state = .queued; $0.localURL = nil; $0.bytesPerSecond = nil
            $0.estimatedSecondsRemaining = nil; $0.resumeDataFilename = nil
            $0.retryCount = ($0.retryCount ?? 0) + 1
        }
        pumpQueue()
    }

    func pauseAll() {
        downloads.filter { $0.state == .downloading }.map(\.id).forEach(pause)
        for id in downloads.filter({ $0.state == .queued }).map(\.id) { update(id) { $0.state = .paused } }
        persistNow()
    }
    func resumeAll() { downloads.filter { $0.state == .paused }.map(\.id).forEach(resume) }
    func retryAllFailed() { downloads.filter { $0.state == .failed }.map(\.id).forEach(retry) }

    func remove(_ id: UUID) {
        taskByID.removeValue(forKey: id)?.cancel()
        if let record = downloads.first(where: { $0.id == id }) { removeFiles(record) }
        downloads.removeAll { $0.id == id }
        persistNow(); refreshAvailableStorage(); pumpQueue()
    }

    func removeCompleted() {
        downloads.filter { $0.state == .complete }.forEach(removeFiles)
        downloads.removeAll { $0.state == .complete }
        persistNow(); refreshAvailableStorage()
    }

    func cleanupCompleted(olderThan age: TimeInterval = 30 * 86_400) {
        let cutoff = Date().addingTimeInterval(-age)
        let expired = downloads.filter { $0.state == .complete && ($0.completedAt ?? $0.createdAt) < cutoff }
        expired.forEach(removeFiles)
        let ids = Set(expired.map(\.id)); downloads.removeAll { ids.contains($0.id) }
        persistNow(); refreshAvailableStorage()
    }

    func reconcileFiles() {
        for index in downloads.indices where downloads[index].localURL != nil {
            if !FileManager.default.fileExists(atPath: downloads[index].localURL!.path) {
                downloads[index].localURL = nil; downloads[index].state = .failed
                downloads[index].errorMessage = "The offline file is no longer on this device."
            }
        }
        persistSoon()
    }

    private func pumpQueue() {
        guard isNetworkAvailable else { return }
        var slots = maximumConcurrentDownloads - taskByID.count
        for record in downloads where record.state == .queued && slots > 0 {
            if let filename = record.resumeDataFilename,
               let data = try? Data(contentsOf: resumeFolder.appendingPathComponent(filename)) {
                start(id: record.id, task: session.downloadTask(withResumeData: data))
            } else {
                var request = URLRequest(url: record.sourceURL, timeoutInterval: 60)
                request.setValue("video/*,application/octet-stream;q=0.9,*/*;q=0.1", forHTTPHeaderField: "Accept")
                start(id: record.id, task: session.downloadTask(with: request))
            }
            slots -= 1
        }
    }

    private func start(id: UUID, task: URLSessionDownloadTask) {
        task.taskDescription = id.uuidString; taskByID[id] = task
        samples[id] = (Date(), downloads.first { $0.id == id }?.receivedBytes ?? 0)
        update(id) { $0.state = .downloading; $0.errorMessage = nil }; task.resume()
    }

    private func copyLocalFile(id: UUID, source: URL) {
        do {
            let destination = try Self.destinationURL(id: id, sourceURL: source)
            try? FileManager.default.removeItem(at: destination); try FileManager.default.copyItem(at: source, to: destination)
            let size = Self.fileSize(destination)
            update(id, immediate: true) { $0.localURL = destination; $0.progress = 1; $0.receivedBytes = size
                $0.expectedBytes = size; $0.state = .complete; $0.completedAt = Date() }
            refreshAvailableStorage()
        } catch { fail(id, error.localizedDescription) }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let text = downloadTask.taskDescription, let id = UUID(uuidString: text) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let now = Date(), previous = self.samples[id] ?? (now, totalBytesWritten - bytesWritten)
            let instantaneous = Double(max(0, totalBytesWritten - previous.1)) / max(now.timeIntervalSince(previous.0), 0.05)
            let old = self.downloads.first { $0.id == id }?.bytesPerSecond ?? instantaneous
            let rate = old * 0.7 + instantaneous * 0.3; self.samples[id] = (now, totalBytesWritten)
            self.update(id) {
                $0.receivedBytes = totalBytesWritten; $0.expectedBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
                $0.progress = totalBytesExpectedToWrite > 0 ? min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 1) : 0
                $0.bytesPerSecond = rate > 0 ? rate : nil
                $0.estimatedSecondsRemaining = totalBytesExpectedToWrite > totalBytesWritten && rate > 0
                    ? Double(totalBytesExpectedToWrite - totalBytesWritten) / rate : nil
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let text = downloadTask.taskDescription, let id = UUID(uuidString: text) else { return }
        do {
            let destination = try Self.destinationURL(id: id, sourceURL: downloadTask.originalRequest?.url ?? location)
            try? FileManager.default.removeItem(at: destination); try FileManager.default.moveItem(at: location, to: destination)
            let size = Self.fileSize(destination)
            Task { @MainActor [weak self] in
                guard let self else { return }; self.taskByID.removeValue(forKey: id); self.samples.removeValue(forKey: id)
                self.update(id, immediate: true) { $0.localURL = destination; $0.progress = 1
                    $0.receivedBytes = max($0.receivedBytes, size); $0.expectedBytes = max($0.expectedBytes ?? 0, size)
                    $0.state = .complete; $0.completedAt = Date(); $0.errorMessage = nil
                    $0.bytesPerSecond = nil; $0.estimatedSecondsRemaining = nil; $0.resumeDataFilename = nil }
                self.removeResumeData(id); self.refreshAvailableStorage(); self.pumpQueue()
            }
        } catch { Task { @MainActor [weak self] in self?.fail(id, error.localizedDescription) } }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let text = task.taskDescription, let id = UUID(uuidString: text) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.taskByID.removeValue(forKey: id); self.samples.removeValue(forKey: id)
            if self.intentionalPauses.remove(id) != nil { return }
            if !self.isNetworkAvailable || Self.isConnectivityError(error) {
                self.update(id, immediate: true) {
                    $0.state = .queued; $0.errorMessage = "Waiting for a stable connection."
                    $0.bytesPerSecond = nil; $0.estimatedSecondsRemaining = nil
                }
                self.pumpQueue()
                return
            }
            self.fail(id, error.localizedDescription); self.pumpQueue()
        }
    }

    nonisolated private static func isConnectivityError(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(error.code)
    }

    private func loadPersisted() -> [OfflineDownload] {
        if let saved = store.load() { return saved }
        guard let data = UserDefaults.standard.data(forKey: legacyDefaultsKey),
              let legacy = try? JSONDecoder().decode([OfflineDownload].self, from: data) else { return [] }
        store.save(legacy); UserDefaults.standard.removeObject(forKey: legacyDefaultsKey); return legacy
    }
    private static func recovered(_ record: OfflineDownload) -> OfflineDownload {
        var copy = record
        if copy.state == .downloading { copy.state = copy.resumeDataFilename == nil ? .queued : .paused }
        return copy
    }
    private func update(_ id: UUID, immediate: Bool = false, _ mutation: (inout OfflineDownload) -> Void) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        mutation(&downloads[index]); downloads[index].lastUpdatedAt = Date(); immediate ? persistNow() : persistSoon()
    }
    private func fail(_ id: UUID, _ message: String) {
        taskByID.removeValue(forKey: id); update(id, immediate: true) { $0.state = .failed
            $0.errorMessage = message; $0.bytesPerSecond = nil; $0.estimatedSecondsRemaining = nil }
    }
    private func persistSoon() {
        persistTask?.cancel(); persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(750)); guard !Task.isCancelled else { return }; self?.persistNow()
        }
    }
    private func persistNow() { persistTask?.cancel(); persistTask = nil; store.save(downloads) }
    private var resumeFolder: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineResumeData", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); return folder
    }
    private func writeResumeData(_ data: Data, id: UUID) -> String? {
        guard !data.isEmpty else { return nil }; let name = "\(id.uuidString).resume"
        do { try data.write(to: resumeFolder.appendingPathComponent(name), options: .atomic); return name } catch { return nil }
    }
    private func removeResumeData(_ id: UUID) { try? FileManager.default.removeItem(at: resumeFolder.appendingPathComponent("\(id.uuidString).resume")) }
    private func removeFiles(_ record: OfflineDownload) {
        if let url = record.localURL { try? FileManager.default.removeItem(at: url) }
        if let name = record.resumeDataFilename { try? FileManager.default.removeItem(at: resumeFolder.appendingPathComponent(name)) }
        else { removeResumeData(record.id) }
    }
    private func refreshAvailableStorage() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        availableStorageBytes = (try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity.map(Int64.init)
    }
    nonisolated private static func destinationURL(id: UUID, sourceURL: URL) throws -> URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineMedia", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(id.uuidString).appendingPathExtension(sourceURL.pathExtension.isEmpty ? "media" : sourceURL.pathExtension)
    }
    nonisolated private static func fileSize(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
    }
}
