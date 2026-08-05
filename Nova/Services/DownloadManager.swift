//
//  DownloadManager.swift
//  Nova
//
//  Managed offline copies for user-authorized direct media. Downloads expose
//  progress, survive ordinary navigation, report storage use, and can be cleaned up.
//

import Foundation
import Combine

struct OfflineDownload: Identifiable, Codable, Hashable, Sendable {
    enum State: String, Codable, Sendable { case queued, downloading, paused, complete, failed }

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
}

@MainActor
final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published private(set) var downloads: [OfflineDownload] = []

    private let defaultsKey = "offline.downloads.v1"
    private var taskByDownloadID: [UUID: URLSessionDownloadTask] = [:]
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: self,
                          delegateQueue: OperationQueue())
    }()

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([OfflineDownload].self, from: data) {
            downloads = saved.map { record in
                var copy = record
                if copy.state == .downloading || copy.state == .queued {
                    copy.state = .failed
                    copy.errorMessage = "Download was interrupted. Start it again."
                }
                if let localURL = copy.localURL,
                   !FileManager.default.fileExists(atPath: localURL.path) {
                    copy.localURL = nil
                    copy.state = .failed
                    copy.errorMessage = "The offline file is no longer on this device."
                }
                return copy
            }
        }
    }

    func isEligible(_ item: MediaItem) -> Bool {
        guard item.legalAccessConfirmed, item.sourceType != .liveTV else { return false }
        switch item.playbackURL.scheme?.lowercased() {
        case "https", "http", "file": return true
        default: return false
        }
    }

    @discardableResult
    func enqueue(_ item: MediaItem) -> UUID? {
        guard isEligible(item) else { return nil }
        if let existing = downloads.first(where: { $0.mediaID == item.id && $0.state == .complete }) {
            return existing.id
        }
        let id = UUID()
        let record = OfflineDownload(id: id, mediaID: item.id, title: item.displayTitle,
                                     sourceURL: item.playbackURL, localURL: nil, progress: 0,
                                     receivedBytes: 0, expectedBytes: nil, state: .queued,
                                     errorMessage: nil, createdAt: Date(), completedAt: nil)
        downloads.append(record)
        persist()

        if item.playbackURL.isFileURL {
            copyLocalFile(for: id, source: item.playbackURL)
        } else {
            startNetworkDownload(id: id, source: item.playbackURL)
        }
        return id
    }

    func retry(_ id: UUID) {
        guard let record = downloads.first(where: { $0.id == id }) else { return }
        removeFile(for: record)
        update(id) {
            $0.progress = 0
            $0.receivedBytes = 0
            $0.expectedBytes = nil
            $0.errorMessage = nil
            $0.state = .queued
            $0.localURL = nil
        }
        startNetworkDownload(id: id, source: record.sourceURL)
    }

    func pause(_ id: UUID) {
        taskByDownloadID[id]?.suspend()
        update(id) { $0.state = .paused }
    }

    func resume(_ id: UUID) {
        guard let task = taskByDownloadID[id] else { retry(id); return }
        task.resume()
        update(id) { $0.state = .downloading }
    }

    func remove(_ id: UUID) {
        taskByDownloadID.removeValue(forKey: id)?.cancel()
        if let record = downloads.first(where: { $0.id == id }) { removeFile(for: record) }
        downloads.removeAll { $0.id == id }
        persist()
    }

    func cleanupCompleted(olderThan age: TimeInterval = 30 * 86_400) {
        let cutoff = Date().addingTimeInterval(-age)
        for record in downloads where record.state == .complete && (record.completedAt ?? record.createdAt) < cutoff {
            removeFile(for: record)
        }
        downloads.removeAll {
            $0.state == .complete && ($0.completedAt ?? $0.createdAt) < cutoff
        }
        persist()
    }

    var storageBytes: Int64 {
        downloads.reduce(0) { $0 + ($1.state == .complete ? $1.receivedBytes : 0) }
    }

    private func startNetworkDownload(id: UUID, source: URL) {
        var request = URLRequest(url: source, timeoutInterval: 60)
        request.setValue("video/*,application/octet-stream;q=0.9,*/*;q=0.1", forHTTPHeaderField: "Accept")
        let task = session.downloadTask(with: request)
        task.taskDescription = id.uuidString
        taskByDownloadID[id] = task
        update(id) { $0.state = .downloading }
        task.resume()
    }

    private func copyLocalFile(for id: UUID, source: URL) {
        do {
            let destination = try Self.destinationURL(id: id, sourceURL: source)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            update(id) {
                $0.localURL = destination
                $0.progress = 1
                $0.receivedBytes = size
                $0.expectedBytes = size
                $0.state = .complete
                $0.completedAt = Date()
            }
        } catch {
            update(id) { $0.state = .failed; $0.errorMessage = error.localizedDescription }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard let text = downloadTask.taskDescription, let id = UUID(uuidString: text) else { return }
        Task { @MainActor [weak self] in
            self?.update(id) {
                $0.receivedBytes = totalBytesWritten
                $0.expectedBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
                $0.progress = totalBytesExpectedToWrite > 0
                    ? min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 1) : 0
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let text = downloadTask.taskDescription, let id = UUID(uuidString: text) else { return }
        do {
            let destination = try Self.destinationURL(id: id,
                                                      sourceURL: downloadTask.originalRequest?.url ?? location)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            Task { @MainActor [weak self] in
                self?.taskByDownloadID.removeValue(forKey: id)
                self?.update(id) {
                    $0.localURL = destination
                    $0.progress = 1
                    $0.receivedBytes = max($0.receivedBytes, size)
                    $0.expectedBytes = max($0.expectedBytes ?? 0, size)
                    $0.state = .complete
                    $0.completedAt = Date()
                    $0.errorMessage = nil
                }
            }
        } catch {
            Task { @MainActor [weak self] in
                self?.update(id) { $0.state = .failed; $0.errorMessage = error.localizedDescription }
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        guard let error, let text = task.taskDescription, let id = UUID(uuidString: text) else { return }
        Task { @MainActor [weak self] in
            self?.taskByDownloadID.removeValue(forKey: id)
            self?.update(id) { $0.state = .failed; $0.errorMessage = error.localizedDescription }
        }
    }

    private func update(_ id: UUID, mutation: (inout OfflineDownload) -> Void) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        mutation(&downloads[index])
        persist()
    }

    private func removeFile(for record: OfflineDownload) {
        if let localURL = record.localURL { try? FileManager.default.removeItem(at: localURL) }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(downloads) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    nonisolated private static func destinationURL(id: UUID, sourceURL: URL) throws -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first!
        let folder = support.appendingPathComponent("OfflineMedia", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = sourceURL.pathExtension.isEmpty ? "media" : sourceURL.pathExtension
        return folder.appendingPathComponent(id.uuidString).appendingPathExtension(ext)
    }
}
