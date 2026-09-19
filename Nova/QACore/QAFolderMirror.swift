// QAFolderMirror.swift
// ─────────────────────────────────────────────────────────────────────────────
// Shared QACore — mirrors QA data to iCloud Drive for Mac visibility.
//
// Writes to: iCloud Drive → <AppName> → QA → Logs / Tickets / Screenshots
// An actor because resolving the iCloud container can block for seconds on
// first use, and we must never block the main actor doing it.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

actor QAFolderMirror {
    static let shared = QAFolderMirror()
    private init() {}

    private var root: URL?

    // MARK: Root resolution

    private func resolveRoot() -> URL? {
        if let r = root { return r }
        guard let container = FileManager.default.url(
            forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
            .appendingPathComponent(QA.config.appName)
            .appendingPathComponent("QA")
        else { return nil }
        try? FileManager.default.createDirectory(at: container,
                                                  withIntermediateDirectories: true)
        root = container
        return container
    }

    // MARK: Writing

    /// Write a plain-text log file that overwrites on each call — the "latest"
    /// version of a report or session. Returns the URL on success.
    @discardableResult
    func writeStableLog(_ text: String, name: String) async -> URL? {
        guard let dir = resolveRoot()?.appendingPathComponent("Logs") else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Write a timestamped log file — archived, never overwritten.
    @discardableResult
    func writeLatestReport(_ text: String) async -> URL? {
        guard let dir = resolveRoot()?.appendingPathComponent("Logs") else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("qa-report-\(stamp).txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Write a ticket as Markdown in its own subfolder, mirroring Stocked's
    /// folder-per-ticket pattern. Safe to call repeatedly — overwrites in place.
    @discardableResult
    func writeTicket(number: String, markdown: String) async -> URL? {
        guard let dir = resolveRoot()?.appendingPathComponent("Tickets")
            .appendingPathComponent(number) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("report.md")
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Copy a screenshot into the ticket's folder. Skips if the source does not
    /// exist or if the destination is already current.
    @discardableResult
    func copyScreenshot(from source: URL, ticketNumber: String) async -> URL? {
        guard let dir = resolveRoot()?.appendingPathComponent("Tickets")
            .appendingPathComponent(ticketNumber) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("screenshot.jpg")
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        try? FileManager.default.copyItem(at: source, to: dest)
        return dest
    }
}
