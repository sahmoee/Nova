//
//  DownloadManager.swift
//  FrameTV
//
//  Downloads a playable file (SMB, direct URL) to local storage so it can be watched
//  offline. Progress is published for UI. Downloaded files live in the app's Documents
//  /Downloads folder, keyed by the item's id.
//

import Foundation

@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var progress: [UUID: Double] = [:]
    @Published private(set) var completed: [UUID: URL] = [:]
    @Published var lastError: String?

    private var tasks: [UUID: URLSessionDownloadTask] = [:]
    private var sessions: [UUID: URLSession] = [:]
    private let fileManager = FileManager.default

    private var downloadsDir: URL {
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Downloads", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    init() { indexExisting() }

    private func indexExisting() {
        guard let files = try? fileManager.contentsOfDirectory(at: downloadsDir,
                                                               includingPropertiesForKeys: nil) else { return }
        for file in files {
            let base = file.deletingPathExtension().lastPathComponent
            if let id = UUID(uuidString: base) { completed[id] = file }
        }
    }

    func isDownloaded(_ item: MediaItem) -> Bool { completed[item.id] != nil }
    func localURL(for item: MediaItem) -> URL? { completed[item.id] }
    func isDownloading(_ item: MediaItem) -> Bool { progress[item.id] != nil }

    func download(_ item: MediaItem) {
        guard completed[item.id] == nil, tasks[item.id] == nil else { return }
        let ext = item.playbackURL.pathExtension.isEmpty ? "mp4" : item.playbackURL.pathExtension
        let dest = downloadsDir.appendingPathComponent("\(item.id.uuidString).\(ext)")

        progress[item.id] = 0
        let delegate = DownloadDelegate(
            onProgress: { [weak self] fraction in
                Task { @MainActor in self?.progress[item.id] = fraction }
            },
            onFinish: { [weak self] tempURL in
                Task { @MainActor in
                    guard let self else { return }
                    self.tasks[item.id] = nil
                    self.progress[item.id] = nil
                    self.sessions[item.id]?.finishTasksAndInvalidate()
                    self.sessions[item.id] = nil
                    do {
                        if self.fileManager.fileExists(atPath: dest.path) {
                            try self.fileManager.removeItem(at: dest)
                        }
                        try self.fileManager.moveItem(at: tempURL, to: dest)
                        self.completed[item.id] = dest
                    } catch {
                        self.lastError = "Couldn't save download: \(error.localizedDescription)"
                    }
                }
            },
            onError: { [weak self] message in
                Task { @MainActor in
                    self?.tasks[item.id] = nil
                    self?.progress[item.id] = nil
                    self?.sessions[item.id]?.finishTasksAndInvalidate()
                    self?.sessions[item.id] = nil
                    self?.lastError = message
                }
            }
        )
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        sessions[item.id] = session
        let task = session.downloadTask(with: item.playbackURL)
        tasks[item.id] = task
        task.resume()
    }

    func cancel(_ item: MediaItem) {
        tasks[item.id]?.cancel()
        tasks[item.id] = nil
        sessions[item.id]?.invalidateAndCancel()
        sessions[item.id] = nil
        progress[item.id] = nil
    }

    func deleteDownload(_ item: MediaItem) {
        if let url = completed[item.id] {
            try? fileManager.removeItem(at: url)
            completed[item.id] = nil
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void
    let onFinish: (URL) -> Void
    let onError: (String) -> Void

    init(onProgress: @escaping (Double) -> Void,
         onFinish: @escaping (URL) -> Void,
         onError: @escaping (String) -> Void) {
        self.onProgress = onProgress
        self.onFinish = onFinish
        self.onError = onError
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: tmp)
            onFinish(tmp)
        } catch {
            onError("Download failed to save: \(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as NSError?, error.code != NSURLErrorCancelled {
            onError("Download failed: \(error.localizedDescription)")
        }
    }
}
