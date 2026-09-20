// QATriage.swift
// ─────────────────────────────────────────────────────────────────────────────
// Shared QACore — verdict + findings synthesis.
//
// QATriage is a @MainActor @Observable singleton that synthesises the overall
// QA verdict and the ranked finding list from four sources:
//   1. QARecorder   — invariant violations, dead screens, stalled processes
//   2. QATicketStore — open/major tickets
//   3. QARuntimeMonitor — memory, thermal, hitch, disk, power
//   4. Per-app extras  — injected via `QATriage.shared.extraFindings`
//
// Call `QATriage.shared.refresh()` whenever any input changes.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

// MARK: - Finding level

nonisolated enum QAFindingLevel: Int, Comparable, Sendable {
    case blocker = 0
    case warning = 1
    case note    = 2

    static func < (lhs: QAFindingLevel, rhs: QAFindingLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .blocker: return "Blocker"
        case .warning: return "Warning"
        case .note:    return "Note"
        }
    }

    var tint: Color {
        switch self {
        case .blocker: return .red
        case .warning: return .orange
        case .note:    return .secondary
        }
    }

    var symbol: String {
        switch self {
        case .blocker: return "octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .note:    return "info.circle"
        }
    }
}

// MARK: - Finding

nonisolated struct QAFinding: Identifiable, Sendable {
    var id: String
    var level: QAFindingLevel
    var symbol: String
    var title: String
    var detail: String
    var source: String

    init(id: String = UUID().uuidString,
         level: QAFindingLevel,
         symbol: String? = nil,
         title: String,
         detail: String = "",
         source: String = "") {
        self.id = id
        self.level = level
        self.symbol = symbol ?? level.symbol
        self.title = title
        self.detail = detail
        self.source = source
    }
}

// MARK: - QATriage

@MainActor @Observable
final class QATriage {

    static let shared = QATriage()
    private init() {}

    // MARK: Published output

    private(set) var findings: [QAFinding] = []

    var blockers: [QAFinding] { findings.filter { $0.level == .blocker } }
    var warnings: [QAFinding] { findings.filter { $0.level == .warning } }
    var notes:    [QAFinding] { findings.filter { $0.level == .note    } }

    // MARK: Verdict

    var verdict: String {
        if blockers.isEmpty && warnings.isEmpty && findings.isEmpty { return "Pass" }
        if !blockers.isEmpty { return "Blocked" }
        if !warnings.isEmpty { return "Warnings" }
        return "Notes"
    }

    var verdictSymbol: String {
        if blockers.isEmpty && warnings.isEmpty && findings.isEmpty { return "checkmark.circle.fill" }
        if !blockers.isEmpty { return "octagon.fill" }
        if !warnings.isEmpty { return "exclamationmark.triangle.fill" }
        return "info.circle"
    }

    var verdictTint: Color {
        if blockers.isEmpty && warnings.isEmpty && findings.isEmpty { return .green }
        if !blockers.isEmpty { return .red }
        if !warnings.isEmpty { return .orange }
        return .secondary
    }

    // MARK: Extra findings injection

    /// Per-app modules append their own findings here before calling refresh().
    var extraFindings: [QAFinding] = []

    // MARK: Refresh

    func refresh() {
        var out: [QAFinding] = []

        // 1. Open invariant violations
        let violations = QARecorder.shared.openViolations
        for v in violations {
            out.append(QAFinding(
                id: "inv-\(v)",
                level: .blocker,
                symbol: "exclamationmark.shield.fill",
                title: v,
                source: "invariant"
            ))
        }

        // 2. Stalled processes
        let stalled = QAProcessTracker.shared.stalled.map(\.line)
        for s in stalled {
            out.append(QAFinding(
                id: "stall-\(s)",
                level: .blocker,
                symbol: "hourglass",
                title: "Stalled: \(s)",
                source: "process"
            ))
        }

        // 3. Dead screens
        let dead = QARecorder.shared.deadScreens
        for d in dead {
            out.append(QAFinding(
                id: "dead-\(d)",
                level: .warning,
                symbol: "rectangle.slash",
                title: d,
                source: "recorder"
            ))
        }

        // 4. Open blocker tickets
        let tickets = QATicketStore.shared.tickets
        let openBlockers = tickets.filter { $0.severity == .blocker && !$0.status.isClosed }
        if !openBlockers.isEmpty {
            out.append(QAFinding(
                id: "tickets-blockers",
                level: .blocker,
                symbol: QATicketSeverity.blocker.symbol,
                title: "\(openBlockers.count) open blocker ticket\(openBlockers.count == 1 ? "" : "s")",
                detail: openBlockers.map(\.title).joined(separator: "\n"),
                source: "tickets"
            ))
        }

        // 5. Open major tickets
        let openMajors = tickets.filter { $0.severity == .major && !$0.status.isClosed }
        if !openMajors.isEmpty {
            out.append(QAFinding(
                id: "tickets-major",
                level: .warning,
                symbol: QATicketSeverity.major.symbol,
                title: "\(openMajors.count) open major ticket\(openMajors.count == 1 ? "" : "s")",
                detail: openMajors.map(\.title).joined(separator: "\n"),
                source: "tickets"
            ))
        }

        // 6. Runtime: memory
        let mem = QARuntimeMonitor.shared.currentFootprintMB
        if mem > 800 {
            out.append(QAFinding(
                id: "memory",
                level: mem > 1200 ? .blocker : .warning,
                symbol: "memorychip",
                title: String(format: "Memory %.0f MB", mem),
                source: "runtime"
            ))
        }

        // 7. Runtime: thermal
        let thermal = QARuntimeMonitor.shared.thermalName
        if thermal == "serious" || thermal == "critical" {
            out.append(QAFinding(
                id: "thermal",
                level: thermal == "critical" ? .blocker : .warning,
                symbol: "thermometer.high",
                title: "Thermal state: \(thermal)",
                source: "runtime"
            ))
        }

        // 8. Runtime: worst hitch
        let hitch = QARuntimeMonitor.shared.worstHitchMs
        if hitch > 250 {
            out.append(QAFinding(
                id: "hitch",
                level: hitch > 500 ? .blocker : .warning,
                symbol: "chart.line.downtrend.xyaxis",
                title: String(format: "Frame hitch %.0f ms", hitch),
                source: "runtime"
            ))
        }

        // 9. Per-app extras
        out.append(contentsOf: extraFindings)

        // Sort: blocker → warning → note, stable
        findings = out.sorted { $0.level < $1.level }
    }

    // MARK: Export

    var exportText: String {
        var lines = ["── QA Triage — \(verdict) ──", ""]
        for f in findings {
            lines.append("[\(f.level.title)] \(f.title)")
            if !f.detail.isEmpty { lines.append("  \(f.detail)") }
        }
        if findings.isEmpty { lines.append("No findings.") }
        return lines.joined(separator: "\n")
    }
}
