// QAVerdict.swift
// ─────────────────────────────────────────────────────────────────────────────
// Shared QACore — checklist verdict enum + check item types.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

// MARK: - QAVerdict

nonisolated enum QAVerdict: String, Codable, Sendable, CaseIterable, Identifiable {
    case untested
    case pass
    case fail
    case blocked
    case resolved

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .untested:  return "circle.dashed"
        case .pass:      return "checkmark.circle.fill"
        case .fail:      return "xmark.circle.fill"
        case .blocked:   return "minus.circle.fill"
        case .resolved:  return "checkmark.seal.fill"
        }
    }

    var color: Color {
        switch self {
        case .untested:  return .secondary
        case .pass:      return .green
        case .fail:      return .red
        case .blocked:   return .orange
        case .resolved:  return .blue
        }
    }

    /// What the tester should set next. Cycles through the natural flow.
    var next: QAVerdict {
        switch self {
        case .untested:  return .pass
        case .pass:      return .fail
        case .fail:      return .blocked
        case .blocked:   return .resolved
        case .resolved:  return .untested
        }
    }

    var isTerminal: Bool { self == .pass || self == .resolved }
}

// MARK: - Check item state

nonisolated struct QACheckItemState: Codable, Sendable {
    var verdict: QAVerdict = .untested
    var note: String = ""
    var ticketNumber: String?
    /// A snapshot of the check's text at the time the verdict was set — so a
    /// renamed check does not make old results ambiguous.
    var definition: String?
}

// MARK: - Check item

struct QACheckItem: Identifiable, Sendable {
    /// Stable per-app key, e.g. "QA-01-03". Used as the dictionary key in
    /// `QACheckItemState` storage.
    var ticket: String
    var text: String
    var blocker: Bool = false

    var id: String { ticket }
}

// MARK: - Checklist section

struct QAChecklistSection: Identifiable, Sendable {
    var number: Int
    var title: String
    var note: String = ""
    var items: [QACheckItem]

    var id: Int { number }
}
