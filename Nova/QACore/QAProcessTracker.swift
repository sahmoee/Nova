// QAProcessTracker.swift
// ─────────────────────────────────────────────────────────────────────────────
// Shared QACore — tracks named in-flight operations so a ticket knows what was
// running at the time.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import Observation

nonisolated struct QAProcess: Identifiable, Sendable {
    var id     = UUID()
    var label: String
    var detail: String
    var startedAt: Date = Date()
    var isStalled: Bool { Date().timeIntervalSince(startedAt) > 30 }
    var line: String {
        let elapsed = Int(Date().timeIntervalSince(startedAt))
        return "\(label)\(detail.isEmpty ? "" : " · \(detail)") (\(elapsed)s)"
    }
}

@MainActor
@Observable
final class QAProcessTracker {
    static let shared = QAProcessTracker()
    private init() {}

    private(set) var processes: [QAProcess] = []
    private let cap = 40

    var running: [QAProcess] { processes.filter { !$0.isStalled } }
    var stalled: [QAProcess] { processes.filter(\.isStalled) }

    func start() {
        processes.removeAll()
    }

    @discardableResult
    func mark(_ label: String, detail: String = "") -> UUID {
        let p = QAProcess(label: label, detail: detail)
        processes.append(p)
        if processes.count > cap { processes.removeFirst(processes.count - cap) }
        return p.id
    }

    func finish(_ id: UUID) {
        processes.removeAll { $0.id == id }
    }

    func clear() {
        processes.removeAll()
    }

    var exportText: String {
        var out = ["PROCESSES"]
        if processes.isEmpty {
            out.append("  none tracked")
        } else {
            for p in running  { out.append("  [running] \(p.line)") }
            for p in stalled  { out.append("  [stalled] \(p.line)") }
        }
        return out.joined(separator: "\n")
    }
}
