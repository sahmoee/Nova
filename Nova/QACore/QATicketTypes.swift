// QATicketTypes.swift
// ─────────────────────────────────────────────────────────────────────────────
// Shared QACore — ticket model types.
//
// All types are nonisolated + Sendable so they cross freely to sync paths off
// the main actor. Every field added since v1 is Optional — synthesised Codable
// throws on a missing key rather than using a default, so a non-Optional field
// would silently erase the saved list on upgrade.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

// MARK: - Severity

nonisolated enum QATicketSeverity: String, Codable, Sendable, CaseIterable, Identifiable {
    case blocker, major, minor, note
    var id: String { rawValue }

    var title: String {
        switch self {
        case .blocker: return "Blocker"
        case .major:   return "Major"
        case .minor:   return "Minor"
        case .note:    return "Note"
        }
    }
    var symbol: String {
        switch self {
        case .blocker: return "octagon.fill"
        case .major:   return "exclamationmark.triangle.fill"
        case .minor:   return "exclamationmark.circle"
        case .note:    return "text.bubble"
        }
    }
    var rank: Int {
        switch self {
        case .blocker: return 0
        case .major:   return 1
        case .minor:   return 2
        case .note:    return 3
        }
    }
}

// MARK: - Status

nonisolated enum QATicketStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case open, investigating, fixed, verified, wontFix
    var id: String { rawValue }

    var title: String {
        switch self {
        case .open:          return "Open"
        case .investigating: return "Investigating"
        case .fixed:         return "Completed"
        case .verified:      return "Verified"
        case .wontFix:       return "Won't fix"
        }
    }
    var symbol: String {
        switch self {
        case .open:          return "circle"
        case .investigating: return "magnifyingglass.circle.fill"
        case .fixed:         return "checkmark.circle.fill"
        case .verified:      return "checkmark.seal.fill"
        case .wontFix:       return "slash.circle"
        }
    }
    var isClosed: Bool { self == .fixed || self == .verified || self == .wontFix }
}

// MARK: - Context

/// Everything the app knew at the moment the ticket was raised.
/// Captured automatically — the tester types a sentence, this fills in the rest.
nonisolated struct QATicketContext: Codable, Sendable {
    var screen: String = "—"
    var breadcrumbs: [String] = []
    var runningProcesses: [String] = []
    var stalledProcesses: [String] = []
    var recentFailures: [String] = []
    var openViolations: [String] = []
    var appVersion: String = ""
    var build: Int = 0
    var device: String = ""
    var os: String = ""
    var memoryMB: Double = 0
    var thermal: String = ""
    var lowPower: Bool = false
    var online: Bool = true
    var freeDiskMB: Double = 0
    var sessionDuration: String = ""
    var tapsOnScreen: Int = 0
    var worstHitchMs: Double = 0
    /// Touch trail — Optional for backward Codable compat.
    var touchTrail: String?
    /// Rendering environment snapshot — Optional for backward Codable compat.
    var environment: [String]?
    var identity: QAReportIdentity?

    var summaryLines: [String] {
        var out: [String] = []
        out.append("screen: \(screen)")
        if let identity {
            out.append("tester/device: \(identity.label)")
            out.append("type: \(identity.deviceFamily) · hardware: \(identity.modelIdentifier.isEmpty ? "not recorded" : identity.modelIdentifier)")
            if !identity.installationID.isEmpty { out.append("QA device: \(identity.installationID)") }
        } else { out.append("tester: unassigned (legacy report)") }
        out.append("build: \(appVersion) (\(build)) · \(device) · \(os)")
        out.append(String(format: "memory: %.0f MB · thermal: %@%@ · %@",
                          memoryMB, thermal, lowPower ? " · low power" : "",
                          online ? "online" : "OFFLINE"))
        if freeDiskMB > 0 { out.append(String(format: "free disk: %.0f MB", freeDiskMB)) }
        out.append("session: \(sessionDuration) · taps on this screen: \(tapsOnScreen)")
        if worstHitchMs > 0 { out.append(String(format: "worst frame hitch: %.0f ms", worstHitchMs)) }
        if let t = touchTrail, !t.isEmpty { out.append(t) }
        if let env = environment, !env.isEmpty { out.append(contentsOf: env) }
        return out
    }
}

// MARK: - Origin

/// Who raised the ticket. Optional on ticket for backward Codable compat.
nonisolated enum QATicketOrigin: String, Codable, Sendable {
    case tester
    case automatic

    var phrase: String {
        switch self {
        case .tester:    return "reported by tester"
        case .automatic: return "raised automatically"
        }
    }
}

// MARK: - Ticket

nonisolated struct QATicket: Identifiable, Codable, Sendable {
    var id = UUID()
    var number: String
    var title: String
    var body: String = ""
    var origin: QATicketOrigin?                // Optional for Codable compat
    var regressionDetectedAt: Date?
    var automaticCheckID: String?
    var severity: QATicketSeverity = .major
    var status: QATicketStatus = .open
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var context = QATicketContext()
    /// Filename inside the QA screenshot directory (not a full path).
    var screenshotFile: String?
    var syncedAt: Date?
    var syncError: String = ""
    /// Mockup file — Optional for Codable compat.
    var mockupFile: String?
    var editedAt: Date?
    var editCount: Int?
    var shotSyncedAt: Date?
    var mirroredAt: Date?
    var cpanelSyncedAt: Date?
    var checkTicket: String?
    var duplicateOf: String?
    var seenAgain: Int?
    var seenAgainAt: Date?
    var runID: String?
    var resolution: String?
    var requiresManualReview: Bool?
    var verifiedAt: Date?
    var refileCount: Int?

    var isSynced: Bool { syncedAt != nil }
    var wasEdited: Bool { editedAt != nil }
    var hasMockup: Bool { mockupFile != nil }
    var isDuplicate: Bool { duplicateOf != nil }
    var recurrenceCount: Int { (seenAgain ?? 0) + 1 }
    var isRecurring: Bool { (seenAgain ?? 0) > 0 }
    var fromCheckbook: Bool { checkTicket != nil }

    var needsAttention: Bool {
        !status.isClosed || requiresManualReview == true
    }

    var statusLabel: String {
        status == .fixed && requiresManualReview == true ? "Fixed · review needed" : status.title
    }

    var originPhrase: String {
        let testerLabel = context.identity?.testerName.isEmpty == false
            ? context.identity!.testerName
            : "Unassigned tester"
        return (origin == .automatic ? "raised automatically" : "reported") + " · " + testerLabel
    }

    var line: String {
        "\(number) [\(severity.rawValue)/\(status.rawValue)] \(title) — \(context.screen)"
    }

    func summary(limit: Int = 140) -> String {
        let flat = body
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard flat.count > limit else { return flat }
        let clipped = flat.prefix(limit)
        let trim = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        if let cut = clipped.lastIndex(of: " ") {
            return String(clipped[clipped.startIndex..<cut]).trimmingCharacters(in: trim) + "…"
        }
        return String(clipped) + "…"
    }

    var summaryLine: String { summary() }

    var exportText: String {
        var out = ["── \(number) ──",
                   "\(severity.title) · \(statusLabel) · \(originPhrase) · \(createdAt.formatted())",
                   title]
        if requiresManualReview == true { out.append("⚠ REQUIRES MANUAL REVIEW — ask the tester for specifics before changing code") }
        if !body.isEmpty { out.append(""); out.append(body) }
        out.append("")
        out.append(contentsOf: context.summaryLines.map { "  " + $0 })
        if !context.breadcrumbs.isEmpty {
            out.append("")
            out.append("  steps before the report:")
            out.append(contentsOf: context.breadcrumbs.map { "    " + $0 })
        }
        if !context.stalledProcesses.isEmpty {
            out.append("  stalled at the time:")
            out.append(contentsOf: context.stalledProcesses.map { "    " + $0 })
        }
        if !context.runningProcesses.isEmpty {
            out.append("  in flight at the time:")
            out.append(contentsOf: context.runningProcesses.map { "    " + $0 })
        }
        if !context.recentFailures.isEmpty {
            out.append("  recent failures:")
            out.append(contentsOf: context.recentFailures.map { "    " + $0 })
        }
        if !context.openViolations.isEmpty {
            out.append("  invariants violating:")
            out.append(contentsOf: context.openViolations.map { "    " + $0 })
        }
        out.append("")
        if let check = checkTicket { out.append("  from checkbook row: \(check)") }
        if let dup = duplicateOf { out.append("  looks like a repeat of: \(dup)") }
        if let again = seenAgain, again > 0 {
            out.append("  reported \(again + 1) times" +
                       (seenAgainAt.map { ", most recently \($0.formatted())" } ?? ""))
        }
        if let run = runID, let name = QARunLog.name(forID: run) {
            out.append("  test run: \(name)")
        }
        out.append("  screenshot: \(screenshotFile == nil ? "none" : "attached")")
        out.append("  synced: \(syncedAt.map { $0.formatted() } ?? (syncError.isEmpty ? "not yet" : "failed — \(syncError)"))")
        return out.joined(separator: "\n")
    }
}

// MARK: - QAReportIdentity decode helper

extension QAReportIdentity {
    static func decode(_ value: Any?) -> QAReportIdentity? {
        guard let dict = value as? [String: Any],
              let json = try? JSONSerialization.data(withJSONObject: dict),
              let decoded = try? JSONDecoder().decode(QAReportIdentity.self, from: json)
        else { return nil }
        return decoded
    }

    var dictionary: [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return dict
    }

    /// Format: `APP-<build>-<seq>-<installSuffix>`.
    /// e.g. `APP-74-0012-AB3C`
    nonisolated static func ticketNumber(build: Int, sequence: Int, installationID: String) -> String {
        let suffix = installationID.replacingOccurrences(of: "-", with: "")
            .prefix(4).uppercased()
        return String(format: "APP-%d-%04d-%@", build, sequence, suffix)
    }
}
