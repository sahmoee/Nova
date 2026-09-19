// QARunLog.swift
// ─────────────────────────────────────────────────────────────────────────────
// Shared QACore — named test-run tracking.
//
// A "run" is a named QA session (e.g. "Sprint 42 regression"). Runs are stored
// in UserDefaults and capped at 40 entries. All access is nonisolated and
// safe to call from background tasks.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

// MARK: - QARun

nonisolated struct QARun: Identifiable, Codable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var startedAt: Date = Date()
    var endedAt: Date?
    var buildNumber: Int = 0
    var buildVersion: String = ""
    var checkTitles: [String: String] = [:]   // checkID → check text at run time

    var isActive: Bool { endedAt == nil }
    var duration: String {
        let end = endedAt ?? Date()
        let secs = Int(end.timeIntervalSince(startedAt))
        let h = secs / 3600, m = (secs % 3600) / 60, s = secs % 60
        if h > 0 { return String(format: "%dh %dm", h, m) }
        if m > 0 { return String(format: "%dm %ds", m, s) }
        return "\(s)s"
    }
}

// MARK: - QARunLog

/// Stores and manages the list of named QA test runs. All public methods are
/// nonisolated — safe to call from any actor context.
nonisolated enum QARunLog {

    private static let key = "qa.runs.v1"
    private static let cap = 40

    // MARK: Persistence

    static func load() -> [QARun] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let runs = try? JSONDecoder().decode([QARun].self, from: data)
        else { return [] }
        return runs
    }

    private static func save(_ runs: [QARun]) {
        guard let data = try? JSONEncoder().encode(runs) else { return }
        UserDefaults.standard.set(data, forKey: key)
        Task {
            let text = runs.map { r in
                let status = r.isActive ? "active" : "ended \(r.endedAt!.formatted())"
                return "\(r.name) — \(r.buildVersion) (\(r.buildNumber)) — \(status)"
            }.joined(separator: "\n")
            await QAFolderMirror.shared.writeStableLog(text, name: "qa-runs.txt")
        }
    }

    // MARK: Queries

    /// Resolve the run name for a given ID — safe to call from any thread.
    static func name(forID id: String) -> String? {
        load().first(where: { $0.id == id })?.name
    }

    static var activeRun: QARun? { load().first(where: { $0.isActive }) }
    static var activeRunID: String? { activeRun?.id }

    // MARK: Mutations

    /// Start a new named run, ending any currently active run first.
    @discardableResult
    static func start(name: String) -> QARun {
        var runs = load()
        // End any open run
        for i in runs.indices where runs[i].isActive {
            runs[i].endedAt = Date()
        }
        var run = QARun(
            name: name,
            buildNumber: QA.config.buildNumber,
            buildVersion: QA.config.buildVersion
        )
        run.checkTitles = checkTitles()
        runs.insert(run, at: 0)
        if runs.count > cap { runs = Array(runs.prefix(cap)) }
        save(runs)
        return run
    }

    /// End the active run, if any.
    static func end() {
        var runs = load()
        var changed = false
        for i in runs.indices where runs[i].isActive {
            runs[i].endedAt = Date()
            changed = true
        }
        if changed { save(runs) }
    }

    /// Delete a run by ID.
    static func delete(id: String) {
        var runs = load()
        runs.removeAll { $0.id == id }
        save(runs)
    }

    /// Clear all runs.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: Check titles snapshot

    /// Returns a snapshot of the app's checklist (checkID → text). The shared
    /// QACore always returns empty — per-app modules override this by calling
    /// `QARunLog.checkTitlesProvider = { ... }` at startup.
    static var checkTitlesProvider: (() -> [String: String])?

    private static func checkTitles() -> [String: String] {
        checkTitlesProvider?() ?? [:]
    }
}
