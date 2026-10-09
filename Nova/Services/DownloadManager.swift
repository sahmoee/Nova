import Foundation
import Combine
import UIKit

/// One durable transfer record. Optional metrics keep the v1 persistence format
/// backward-compatible while adding resume, rate, ETA, retry and update state.
struct OfflineDownload: Identifiable, Codable, Hashable, Sendable {
    typealias State = DownloadLifecycleState
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
    @Published private(set) var otherDevices: [OfflineDeviceSnapshot] = []
    @Published private(set) var deviceStatusMessage: String?
    @Published private(set) var persistenceError: String?
    @Published private(set) var availableStorageBytes: Int64?
    @Published private(set) var isNetworkAvailable = NetworkConditionMonitor.shared.isOnline

    private let legacyDefaultsKey = "offline.downloads.v1"
    private let store = CodableFileStore<[OfflineDownload]>(filename: "offline-downloads.json", prettyPrinted: false,
        validate: { $0.count <= 10_000 && Set($0.map(\.id)).count == $0.count })
    private let maximumConcurrentDownloads = 2
    private var legacyNeedsRecovery = false
    private var taskByID: [UUID: URLSessionDownloadTask] = [:]
    private var localCopyByID: [UUID: Task<Void, Never>] = [:]
    private var localCopyGeneration: [UUID: UUID] = [:]
    private var intentionalPauses = Set<UUID>()
    private var samples: [UUID: (Date, Int64)] = [:]
    private var retryTasks: [UUID: Task<Void, Never>] = [:]
    private var connectionFailures: [UUID: Int] = [:]
    private var persistTask: Task<Void, Never>?
    private var networkCancellable: AnyCancellable?
    private var cloudCancellable: AnyCancellable?
    private var statusPublishTask: Task<Void, Never>?
    private var lastPublishedTransfers: [OfflineDeviceSnapshot.Transfer]?
    private var lastPublishedCount: Int?
    private var lastPublishedAt = Date.distantPast
    private let deviceID: UUID = {
        let key = "offline.device.identity.v1"
        let bindingKey = "offline.device.binding.v1"
        let binding = UIDevice.current.identifierForVendor?.uuidString
        if let saved = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: saved),
           binding == nil || UserDefaults.standard.string(forKey: bindingKey) == binding { return id }
        // Restoring defaults onto another device must not create two writers for
        // the same snapshot. The vendor identifier stays local and is never sent.
        let id = UUID(); UserDefaults.standard.set(id.uuidString, forKey: key)
        if let binding { UserDefaults.standard.set(binding, forKey: bindingKey) }
        UserDefaults.standard.set(0, forKey: "offline.device.revision.v1")
        return id
    }()

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
        Self.cleanupAbandonedStaging()
        reconcileFiles()
        refreshAvailableStorage()
        networkCancellable = NetworkConditionMonitor.shared.$isOnline
            .removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] online in
                self?.isNetworkAvailable = online
                if online { self?.pumpQueue() }
            }
        pumpQueue()
        cloudCancellable = CloudSync.shared.externalChange.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.refreshDeviceStatuses()
        }
        refreshDeviceStatuses()
    }

    deinit {
        persistTask?.cancel()
        statusPublishTask?.cancel()
        retryTasks.values.forEach { $0.cancel() }
        localCopyByID.values.forEach { $0.cancel() }
    }

    var activeCount: Int { downloads.filter { $0.state == .downloading }.count }
    var queuedCount: Int { downloads.filter { $0.state == .queued }.count }
    var completedCount: Int { downloads.filter { $0.state == .complete }.count }
    var failedCount: Int { downloads.filter { $0.state == .failed }.count }
    var storageBytes: Int64 {
        downloads.filter { $0.state == .complete }.reduce(0) {
            let (sum, overflow) = $0.addingReportingOverflow(max(0, $1.receivedBytes))
            return overflow ? Int64.max : sum
        }
    }
    var aggregateProgress: Double {
        let pending = downloads.filter { [.queued, .downloading, .paused].contains($0.state) }
        return pending.isEmpty ? (completedCount > 0 ? 1 : 0)
            : pending.map { $0.progress.isFinite ? min(max($0.progress, 0), 1) : 0 }.reduce(0, +) / Double(pending.count)
    }

    /// Builds a direct-play item for a completed file without re-resolving its
    /// original network source. A missing file is deliberately not playable:
    /// `reconcileFiles()` will surface it as a recoverable failed download.
    func playbackItem(for download: OfflineDownload) -> MediaItem? {
        guard download.state == .complete,
              let localURL = download.localURL,
              Self.validOfflineFile(localURL, id: download.id) else { return nil }

        return MediaItem(
            id: download.mediaID,
            title: download.title,
            sourceType: .directURL,
            playbackURL: localURL,
            legalAccessConfirmed: true
        )
    }

    func isEligible(_ item: MediaItem) -> Bool {
        guard item.legalAccessConfirmed, item.sourceType != .liveTV else { return false }
        return MediaReliabilityPolicy.downloadableURL(item.playbackURL)
    }

    @discardableResult
    func enqueue(_ item: MediaItem) -> UUID? {
        guard isEligible(item), !store.needsRecovery, !legacyNeedsRecovery else { return nil }
        if let existing = downloads.first(where: {
            ($0.mediaID == item.id || $0.sourceURL == item.playbackURL) && $0.state != .failed
        }) {
            if existing.state == .complete, playbackItem(for: existing) == nil {
                update(existing.id, immediate: true) { $0.state = .failed; $0.localURL = nil; $0.errorMessage = "The offline file is no longer on this device." }
                retry(existing.id)
            }
            return existing.id
        }
        let id = UUID()
        downloads.append(OfflineDownload(id: id, mediaID: item.id, title: item.displayTitle,
            sourceURL: item.playbackURL, localURL: nil, progress: 0, receivedBytes: 0,
            expectedBytes: nil, state: .queued, errorMessage: nil, createdAt: Date(),
            completedAt: nil, bytesPerSecond: nil, estimatedSecondsRemaining: nil,
            retryCount: 0, resumeDataFilename: nil, lastUpdatedAt: Date()))
        guard persistNow() else { downloads.removeAll { $0.id == id }; return nil }
        item.playbackURL.isFileURL ? copyLocalFile(id: id, source: item.playbackURL) : pumpQueue()
        return id
    }

    func pause(_ id: UUID) {
        guard let record = downloads.first(where: { $0.id == id }),
              record.state.canPause, !intentionalPauses.contains(id) else { return }
        retryTasks.removeValue(forKey: id)?.cancel()
        if let copy = localCopyByID.removeValue(forKey: id) {
            localCopyGeneration[id] = nil; copy.cancel()
        }
        guard let task = taskByID[id] else {
            update(id, immediate: true) { $0.state = .paused; $0.errorMessage = nil }
            return
        }
        intentionalPauses.insert(id)
        task.cancel { [weak self] data in
            Task { @MainActor in
                guard let self, self.taskByID[id] === task else { return }
                self.taskByID.removeValue(forKey: id)
                self.intentionalPauses.remove(id)
                self.samples.removeValue(forKey: id)
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
        guard downloads.contains(where: { $0.id == id && $0.state.canResume }), taskByID[id] == nil, localCopyByID[id] == nil else { return }
        connectionFailures[id] = nil
        update(id, immediate: true) { $0.state = .queued; $0.errorMessage = nil }
        pumpQueue()
    }

    func retry(_ id: UUID) {
        guard let record = downloads.first(where: { $0.id == id && $0.state.canRetry }), taskByID[id] == nil, localCopyByID[id] == nil else { return }
        retryTasks.removeValue(forKey: id)?.cancel()
        connectionFailures[id] = nil
        guard removeFiles(record) else { return }
        update(id, immediate: true) {
            $0.progress = 0; $0.receivedBytes = 0; $0.expectedBytes = nil; $0.errorMessage = nil
            $0.state = .queued; $0.localURL = nil; $0.bytesPerSecond = nil
            $0.estimatedSecondsRemaining = nil; $0.resumeDataFilename = nil
            $0.retryCount = min(max(0, $0.retryCount ?? 0), 1_000_000) + 1
        }
        pumpQueue()
    }

    func pauseAll() {
        downloads.filter { $0.state == .downloading }.map(\.id).forEach(pause)
        downloads.filter { $0.state == .queued }.map(\.id).forEach(pause)
        persistNow()
    }
    func resumeAll() { downloads.filter { $0.state == .paused }.map(\.id).forEach(resume) }
    func retryAllFailed() { downloads.filter { $0.state == .failed }.map(\.id).forEach(retry) }

    func remove(_ id: UUID) {
        retryTasks.removeValue(forKey: id)?.cancel()
        connectionFailures[id] = nil
        intentionalPauses.remove(id)
        localCopyGeneration[id] = nil
        localCopyByID.removeValue(forKey: id)?.cancel()
        samples[id] = nil
        taskByID.removeValue(forKey: id)?.cancel()
        if let record = downloads.first(where: { $0.id == id }), !removeFiles(record) { return }
        downloads.removeAll { $0.id == id }
        persistNow(); refreshAvailableStorage(); pumpQueue()
    }

    func removeCompleted() {
        let removed = Set(downloads.filter { $0.state == .complete }.filter { removeFiles($0) }.map(\.id))
        downloads.removeAll { removed.contains($0.id) }
        persistNow(); refreshAvailableStorage()
    }

    func cleanupCompleted(olderThan age: TimeInterval = 30 * 86_400) {
        guard let age = MediaReliabilityPolicy.cleanupAge(age) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        let expired = downloads.filter { $0.state == .complete && ($0.completedAt ?? $0.createdAt) < cutoff }
        let ids = Set(expired.filter { removeFiles($0) }.map(\.id)); downloads.removeAll { ids.contains($0.id) }
        persistNow(); refreshAvailableStorage()
    }

    func reconcileFiles() {
        for index in downloads.indices where downloads[index].localURL != nil {
            if !Self.validOfflineFile(downloads[index].localURL!, id: downloads[index].id) {
                downloads[index].localURL = nil; downloads[index].state = .failed
                downloads[index].errorMessage = "The offline file is no longer on this device."
            }
        }
        persistSoon()
    }

    private func pumpQueue() {
        guard persistenceError == nil else { return }
        // Local copies share the bounded queue but need no network connection.
        var slots = maximumConcurrentDownloads - taskByID.count - localCopyByID.count
        for record in downloads where record.state == .queued && record.sourceURL.isFileURL && slots > 0 {
            copyLocalFile(id: record.id, source: record.sourceURL)
            slots -= 1
        }
        guard isNetworkAvailable, persistenceError == nil else { return }
        slots = maximumConcurrentDownloads - taskByID.count - localCopyByID.count
        for record in downloads where record.state == .queued && !record.sourceURL.isFileURL
            && slots > 0 && taskByID[record.id] == nil && retryTasks[record.id] == nil {
            guard MediaReliabilityPolicy.downloadableURL(record.sourceURL) else {
                fail(record.id, "This source cannot be saved as an offline media file."); continue
            }
            if let filename = MediaReliabilityPolicy.resumeFilename(record.resumeDataFilename, id: record.id),
               let data = try? LibraryFilePolicy.read(resumeFolder.appendingPathComponent(filename), maximumBytes: 8 * 1_024 * 1_024), !data.isEmpty {
                start(id: record.id, task: session.downloadTask(withResumeData: data))
            } else {
                removeResumeData(record.id)
                update(record.id) { $0.resumeDataFilename = nil; $0.receivedBytes = 0; $0.progress = 0 }
                var request = URLRequest(url: record.sourceURL, timeoutInterval: 60)
                request.setValue("video/*,application/octet-stream;q=0.9,*/*;q=0.1", forHTTPHeaderField: "Accept")
                start(id: record.id, task: session.downloadTask(with: request))
            }
            slots -= 1
        }
    }

    private func start(id: UUID, task: URLSessionDownloadTask) {
        retryTasks.removeValue(forKey: id)?.cancel()
        task.taskDescription = id.uuidString; taskByID[id] = task
        samples[id] = (Date(), downloads.first { $0.id == id }?.receivedBytes ?? 0)
        update(id) { $0.state = .downloading; $0.errorMessage = nil }; task.resume()
    }

    private func copyLocalFile(id: UUID, source: URL) {
        guard localCopyByID[id] == nil, downloads.contains(where: { $0.id == id && $0.state == .queued }),
              localCopyByID.count + taskByID.count < maximumConcurrentDownloads else { return }
        let generation = UUID()
        localCopyGeneration[id] = generation
        update(id, immediate: true) { $0.state = .downloading; $0.errorMessage = nil }
        guard persistenceError == nil else {
            localCopyGeneration[id] = nil
            if let index = downloads.firstIndex(where: { $0.id == id }) { downloads[index].state = .queued }
            return
        }
        localCopyByID[id] = Task { [weak self] in
            do {
                let transfer = Task.detached { try Self.stageLocalCopy(id: id, source: source) }
                let result = try await withTaskCancellationHandler(operation: { try await transfer.value },
                    onCancel: { transfer.cancel() })
                defer { try? FileManager.default.removeItem(at: result.staged) }
                guard let self, !Task.isCancelled, self.localCopyGeneration[id] == generation,
                      self.downloads.contains(where: { $0.id == id && $0.state == .downloading }) else { return }
                if FileManager.default.fileExists(atPath: result.destination.path) {
                    _ = try FileManager.default.replaceItemAt(result.destination, withItemAt: result.staged)
                } else { try FileManager.default.moveItem(at: result.staged, to: result.destination) }
                self.localCopyByID[id] = nil; self.localCopyGeneration[id] = nil
                self.update(id, immediate: true) {
                    $0.localURL = result.destination; $0.progress = 1; $0.receivedBytes = result.size
                    $0.expectedBytes = result.size; $0.state = .complete; $0.completedAt = Date()
                    $0.errorMessage = nil; $0.bytesPerSecond = nil; $0.estimatedSecondsRemaining = nil
                }
                self.refreshAvailableStorage(); self.pumpQueue()
            } catch {
                guard let self, !Task.isCancelled, self.localCopyGeneration[id] == generation else { return }
                self.localCopyByID[id] = nil; self.localCopyGeneration[id] = nil
                self.fail(id, "The local file could not be copied. Check file access and available storage, then retry.")
                self.pumpQueue()
            }
        }
    }

    nonisolated private static func stageLocalCopy(id: UUID, source: URL) throws -> (staged: URL, destination: URL, size: Int64) {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let destination = try destinationURL(id: id, sourceURL: source)
        let staged = destination.deletingLastPathComponent().appendingPathComponent("\(id).\(UUID()).pending")
        do {
            try Task.checkCancellation()
            guard FileManager.default.createFile(atPath: staged.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
            let input = try FileHandle(forReadingFrom: source)
            defer { try? input.close() }
            let output = try FileHandle(forWritingTo: staged)
            defer { try? output.close() }
            while true {
                try Task.checkCancellation()
                guard let chunk = try input.read(upToCount: 1_024 * 1_024), !chunk.isEmpty else { break }
                try output.write(contentsOf: chunk)
            }
            try output.synchronize()
            try Task.checkCancellation()
            let size = fileSize(staged)
            guard size > 0 else { throw CocoaError(.fileReadCorruptFile) }
            return (staged, destination, size)
        } catch { try? FileManager.default.removeItem(at: staged); throw error }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let text = downloadTask.taskDescription, let id = UUID(uuidString: text) else { return }
        Task { @MainActor [weak self] in
            guard let self, self.taskByID[id] === downloadTask, !self.intentionalPauses.contains(id) else { return }
            let received = max(0, totalBytesWritten)
            let now = Date(), previous = self.samples[id] ?? (now, received >= max(0, bytesWritten) ? received - max(0, bytesWritten) : 0)
            let instantaneous = Double(max(0, received - max(0, previous.1))) / max(now.timeIntervalSince(previous.0), 0.05)
            let old = self.downloads.first { $0.id == id }?.bytesPerSecond ?? instantaneous
            let rate = (old.isFinite && old > 0 ? old : 0) * 0.7 + instantaneous * 0.3; self.samples[id] = (now, received)
            self.update(id) {
                $0.receivedBytes = received; $0.expectedBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
                $0.progress = MediaReliabilityPolicy.downloadProgress(received: received, expected: totalBytesExpectedToWrite)
                $0.bytesPerSecond = rate > 0 ? rate : nil
                $0.estimatedSecondsRemaining = totalBytesExpectedToWrite > received && rate > 0
                    ? Double(totalBytesExpectedToWrite - received) / rate : nil
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let text = downloadTask.taskDescription, let id = UUID(uuidString: text) else { return }
        let response = downloadTask.response as? HTTPURLResponse
        let size = Self.fileSize(location)
        guard MediaReliabilityPolicy.validDownloadResponse(status: response?.statusCode, bytes: size),
              MediaReliabilityPolicy.downloadableMIME(response?.mimeType) else {
            let message = response.map { !(200..<300).contains($0.statusCode)
                ? "The source returned HTTP \($0.statusCode). Choose another source or retry later."
                : "The source did not return a playable download. Choose another source." }
                ?? "The source returned an invalid download response."
            Task { @MainActor [weak self] in
                guard let self, self.taskByID[id] === downloadTask, !self.intentionalPauses.contains(id) else { return }
                self.fail(id, message); self.pumpQueue()
            }
            return
        }
        do {
            let destination = try Self.destinationURL(id: id, sourceURL: downloadTask.originalRequest?.url ?? location)
            // Delegate temporary files disappear after this callback. Stage one
            // unique file, then validate ownership on the main actor before commit.
            let staged = destination.deletingLastPathComponent()
                .appendingPathComponent("\(id.uuidString).\(UUID().uuidString).pending")
            try FileManager.default.moveItem(at: location, to: staged)
            Task { @MainActor [weak self] in
                defer { try? FileManager.default.removeItem(at: staged) }
                guard let self, self.taskByID[id] === downloadTask,
                      self.downloads.contains(where: { $0.id == id }), !self.intentionalPauses.contains(id) else { return }
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged)
                    } else { try FileManager.default.moveItem(at: staged, to: destination) }
                } catch {
                    self.fail(id, "The download could not be saved. Check available storage and retry.")
                    self.pumpQueue(); return
                }
                self.taskByID.removeValue(forKey: id); self.samples.removeValue(forKey: id)
                self.connectionFailures[id] = nil
                self.update(id, immediate: true) { $0.localURL = destination; $0.progress = 1
                    $0.receivedBytes = size; $0.expectedBytes = size
                    $0.state = .complete; $0.completedAt = Date(); $0.errorMessage = nil
                    $0.bytesPerSecond = nil; $0.estimatedSecondsRemaining = nil; $0.resumeDataFilename = nil }
                self.removeResumeData(id); self.refreshAvailableStorage(); self.pumpQueue()
            }
        } catch {
            Task { @MainActor [weak self] in
                guard let self, self.taskByID[id] === downloadTask, !self.intentionalPauses.contains(id) else { return }
                self.fail(id, "The download could not be saved. Check available storage and retry.")
                self.pumpQueue()
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let text = task.taskDescription, let id = UUID(uuidString: text) else { return }
        Task { @MainActor [weak self] in
            guard let self, self.taskByID[id] === task else { return }
            // Pause owns its cancellation callback and resume-data write. A stale
            // callback from an earlier task must never remove the replacement task.
            if self.intentionalPauses.contains(id) { return }
            self.taskByID.removeValue(forKey: id); self.samples.removeValue(forKey: id)
            if !self.isNetworkAvailable || Self.isConnectivityError(error) {
                let resumeData = (error as NSError).userInfo["NSURLSessionDownloadTaskResumeData"] as? Data
                let filename = resumeData.flatMap { self.writeResumeData($0, id: id) }
                let failures = (self.connectionFailures[id] ?? 0) + 1
                self.connectionFailures[id] = failures
                guard let delay = MediaReliabilityPolicy.downloadBackoff(failureCount: failures) else {
                    self.update(id) { if let filename { $0.resumeDataFilename = filename } }
                    self.fail(id, "The connection kept failing. Retry when the source is available.")
                    self.pumpQueue(); return
                }
                self.update(id, immediate: true) {
                    $0.state = .queued; $0.errorMessage = "Waiting for a stable connection."
                    if let filename { $0.resumeDataFilename = filename }
                    $0.bytesPerSecond = nil; $0.estimatedSecondsRemaining = nil
                }
                self.retryTasks[id]?.cancel()
                self.retryTasks[id] = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                    guard let self, !Task.isCancelled else { return }
                    self.retryTasks[id] = nil; self.pumpQueue()
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
        persistenceError = store.lastError
        guard !store.needsRecovery else { return [] }
        guard let data = UserDefaults.standard.data(forKey: legacyDefaultsKey) else { return [] }
        guard data.count <= 16 * 1_024 * 1_024,
              let legacy = try? JSONDecoder().decode([OfflineDownload].self, from: data),
              legacy.count <= 10_000, Set(legacy.map(\.id)).count == legacy.count else {
            legacyNeedsRecovery = true
            persistenceError = "Legacy download records need recovery. Their original data has been preserved."
            return []
        }
        if store.save(legacy) { UserDefaults.standard.removeObject(forKey: legacyDefaultsKey) }
        else { persistenceError = store.lastError }
        return legacy
    }
    private static func recovered(_ record: OfflineDownload) -> OfflineDownload {
        var copy = record
        copy.progress = copy.progress.isFinite ? min(max(copy.progress, 0), 1) : 0
        copy.receivedBytes = max(0, copy.receivedBytes)
        copy.expectedBytes = copy.expectedBytes.flatMap { $0 > 0 ? $0 : nil }
        copy.bytesPerSecond = nil
        copy.estimatedSecondsRemaining = nil
        copy.retryCount = min(max(0, copy.retryCount ?? 0), 1_000_000)
        copy.resumeDataFilename = MediaReliabilityPolicy.resumeFilename(copy.resumeDataFilename, id: copy.id)
        if copy.state == .downloading { copy.state = copy.resumeDataFilename == nil ? .queued : .paused }
        if copy.state == .complete && copy.localURL == nil {
            copy.state = .failed; copy.errorMessage = "The offline file is no longer on this device."
        }
        return copy
    }
    private func update(_ id: UUID, immediate: Bool = false, _ mutation: (inout OfflineDownload) -> Void) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        mutation(&downloads[index]); downloads[index].lastUpdatedAt = Date()
        if immediate { persistNow() } else { persistSoon() }
    }
    private func fail(_ id: UUID, _ message: String) {
        taskByID.removeValue(forKey: id); samples[id] = nil
        retryTasks.removeValue(forKey: id)?.cancel()
        update(id, immediate: true) { $0.state = .failed
            $0.errorMessage = message; $0.bytesPerSecond = nil; $0.estimatedSecondsRemaining = nil }
    }
    private func persistSoon() {
        persistTask?.cancel(); persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(750)); guard !Task.isCancelled else { return }; self?.persistNow()
        }
    }
    @discardableResult private func persistNow() -> Bool {
        persistTask?.cancel(); persistTask = nil
        guard !legacyNeedsRecovery else { return false }
        guard store.save(downloads) else { persistenceError = store.lastError; return false }
        persistenceError = nil
        scheduleDeviceStatus()
        return true
    }

    var requiresRecordRecovery: Bool { store.needsRecovery || legacyNeedsRecovery }

    func resetRecordStorageKeepingOriginal() {
        guard requiresRecordRecovery else { return }
        guard store.resetRetainingOriginal(downloads) else { persistenceError = store.lastError; return }
        // An invalid legacy defaults blob remains untouched. The new valid journal
        // takes precedence on the next launch, preserving that old recovery evidence.
        legacyNeedsRecovery = false
        persistenceError = nil
        pumpQueue(); scheduleDeviceStatus()
    }

    func retryPersistence() {
        if store.needsRecovery || legacyNeedsRecovery {
            if let restored = store.load() {
                legacyNeedsRecovery = false
                downloads = restored.map(Self.recovered)
            } else {
                guard !store.needsRecovery,
                      let data = UserDefaults.standard.data(forKey: legacyDefaultsKey), data.count <= 16 * 1_024 * 1_024,
                      let restored = try? JSONDecoder().decode([OfflineDownload].self, from: data),
                      restored.count <= 10_000, Set(restored.map(\.id)).count == restored.count else {
                    persistenceError = store.lastError ?? "Restore valid download records before retrying."
                    return
                }
                legacyNeedsRecovery = false
                downloads = restored.map(Self.recovered)
            }
            reconcileFiles()
        }
        if persistNow() { pumpQueue() }
    }

    func refreshDeviceStatuses() {
        let cloud = CloudSync.shared
        let key = OfflineDeviceSnapshot.keyPrefix + deviceID.uuidString.lowercased()
        otherDevices = cloud.storedKeys.filter { $0.hasPrefix(OfflineDeviceSnapshot.keyPrefix) && $0 != key }
            .sorted().prefix(OfflineDeviceSnapshot.maximumDevices).compactMap { name in
                cloud.data(forKey: name).flatMap { OfflineDeviceSnapshot.decode($0, key: name) }
            }.sorted { $0.updatedAt > $1.updatedAt }
        deviceStatusMessage = !cloud.accountAvailable ? "Sign in to iCloud to share device download status."
            : cloud.isPaused(.library) ? "Device status sharing is paused with Library sync."
            : cloud.syncIssue
        scheduleDeviceStatus()
    }

    private func scheduleDeviceStatus() {
        guard statusPublishTask == nil else { return }
        statusPublishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            self.statusPublishTask = nil
            self.publishDeviceStatus()
        }
    }

    private func publishDeviceStatus() {
        let cloud = CloudSync.shared
        guard cloud.accountAvailable, !cloud.isPaused(.library), !store.needsRecovery, !legacyNeedsRecovery, persistenceError == nil else { return }
        let key = OfflineDeviceSnapshot.keyPrefix + deviceID.uuidString.lowercased()
        let keys = cloud.storedKeys.filter { $0.hasPrefix(OfflineDeviceSnapshot.keyPrefix) }
        guard keys.contains(key) || keys.count < OfflineDeviceSnapshot.maximumDevices else {
            deviceStatusMessage = "Device status sharing supports up to eight installations. Local downloads are unchanged."
            return
        }
        let transfers = downloads.sorted { $0.createdAt > $1.createdAt }.prefix(50).map {
            OfflineDeviceSnapshot.Transfer(id: $0.id, title: String(($0.title.isEmpty ? "Untitled" : $0.title).prefix(120)), state: $0.state)
        }
        // Progress byte updates do not flood KVS. Refresh last-seen at most every
        // five minutes, or publish immediately when a lifecycle state changes.
        guard transfers != lastPublishedTransfers || downloads.count != lastPublishedCount
            || Date().timeIntervalSince(lastPublishedAt) >= 300 || cloud.data(forKey: key) == nil else { return }
        let revisionKey = "offline.device.revision.v1"
        let previous = UserDefaults.standard.integer(forKey: revisionKey)
        guard previous < Int.max else { return }
        let platform: String
        #if os(tvOS)
        platform = "Apple TV"
        #else
        platform = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
        let snapshot = OfflineDeviceSnapshot(id: deviceID, platform: platform, revision: previous + 1,
            updatedAt: Date(), totalCount: downloads.count, transfers: transfers)
        guard let data = try? JSONEncoder().encode(snapshot), data.count <= OfflineDeviceSnapshot.maximumBytes else { return }
        UserDefaults.standard.set(snapshot.revision, forKey: revisionKey)
        cloud.setData(data, forKey: key)
        lastPublishedTransfers = transfers; lastPublishedCount = downloads.count; lastPublishedAt = snapshot.updatedAt
    }
    private var resumeFolder: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineResumeData", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); return folder
    }
    private func writeResumeData(_ data: Data, id: UUID) -> String? {
        guard !data.isEmpty, data.count <= 8 * 1_024 * 1_024 else { return nil }; let name = "\(id.uuidString).resume"
        do { try data.write(to: resumeFolder.appendingPathComponent(name), options: .atomic); return name } catch { return nil }
    }
    private func removeResumeData(_ id: UUID) { try? FileManager.default.removeItem(at: resumeFolder.appendingPathComponent("\(id.uuidString).resume")) }
    @discardableResult private func removeFiles(_ record: OfflineDownload) -> Bool {
        do {
            if let url = record.localURL, MediaReliabilityPolicy.ownedDownloadFile(url, id: record.id, in: Self.mediaFolder),
               FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            if let name = MediaReliabilityPolicy.resumeFilename(record.resumeDataFilename, id: record.id) {
                let url = resumeFolder.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            } else { removeResumeData(record.id) }
            return true
        } catch {
            update(record.id, immediate: true) { $0.errorMessage = "The downloaded file could not be removed. Check storage access and retry removal." }
            return false
        }
    }
    private func refreshAvailableStorage() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        availableStorageBytes = (try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity.map(Int64.init)
    }
    nonisolated private static func destinationURL(id: UUID, sourceURL: URL) throws -> URL {
        let folder = mediaFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(id.uuidString).appendingPathExtension(MediaReliabilityPolicy.downloadExtension(sourceURL.pathExtension))
    }
    nonisolated private static func cleanupAbandonedStaging() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: mediaFolder,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-86_400)
        for file in files.prefix(512) {
            let parts = file.lastPathComponent.split(separator: ".")
            guard parts.count == 3, UUID(uuidString: String(parts[0])) != nil,
                  UUID(uuidString: String(parts[1])) != nil, parts[2] == "pending",
                  let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let date = values.contentModificationDate, date < cutoff else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    nonisolated private static func fileSize(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
    }
    nonisolated private static var mediaFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineMedia", isDirectory: true)
    }
    nonisolated private static func validOfflineFile(_ url: URL, id: UUID) -> Bool {
        guard MediaReliabilityPolicy.ownedDownloadFile(url, id: id, in: mediaFolder),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else { return false }
        return values.isRegularFile == true && (values.fileSize ?? 0) > 0
    }
}
