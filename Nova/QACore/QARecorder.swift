// QARecorder.swift
// ─────────────────────────────────────────────────────────────────────────────
// Shared QACore — extracted from Stocked QAMode.swift (Build 74/75).
//
// The runtime event journal: every screen visit, every attempt, every
// violation, every note. Ring buffer of 600 events. Breadcrumbs (coalesced
// last-40). Tap counts per screen. Dead screens. Dangling attempts.
// Auto-off timer. Crash-proof failure snapshot.
//
// CRITICAL (Build 75): NOTHING reached from QARecorder.init() may touch
// QARecorder.shared synchronously — swift_once deadlock.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import UIKit

// MARK: - Event kinds

nonisolated enum QAEventKind: String, Codable, Sendable, CaseIterable {
    case screen    = "screen"
    case attempt   = "attempt"
    case success   = "success"
    case failure   = "failure"
    case violation = "violation"
    case note      = "note"

    var symbol: String {
        switch self {
        case .screen:    return "rectangle.on.rectangle"
        case .attempt:   return "arrow.right.circle"
        case .success:   return "checkmark.circle.fill"
        case .failure:   return "xmark.octagon.fill"
        case .violation: return "exclamationmark.triangle.fill"
        case .note:      return "text.bubble"
        }
    }
}

// MARK: - Event

nonisolated struct QAEvent: Identifiable, Codable, Sendable {
    var id   = UUID()
    var at   = Date()
    var kind: QAEventKind
    var screen: String
    var label: String
    var detail: String

    static let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    var line: String {
        "[\(Self.formatter.string(from: at))] \(kind.rawValue.uppercased()) · \(label)" +
        (detail.isEmpty ? "" : " — \(detail)") +
        " (\(screen))"
    }

    var searchHaystack: String {
        "\(label) \(detail) \(screen) \(kind.rawValue)"
    }
}

// MARK: - Supporting types

nonisolated struct QAScreenCount: Identifiable, Sendable {
    var id: String { screen }
    var screen: String
    var count: Int
}

nonisolated struct QAAttempt: Sendable {
    let label: String
    let screen: String
    let startedAt: Date = Date()
}

// MARK: - Invariant result

nonisolated struct QAInvariantResult: Identifiable, Sendable {
    var id: String { name }
    var name: String
    var status: QAInvariantStatus
    var detail: String
    var critical: Bool = false
}

nonisolated enum QAInvariantStatus: String, Sendable, Codable {
    case ok        = "ok"
    case violation = "violation"
    case blocked   = "blocked"
    case untested  = "untested"
}

// MARK: - Recorder

@MainActor
@Observable
final class QARecorder {
    static let shared = QARecorder()

    // MARK: State
    private static let enabledKey     = "qa.mode.enabled"
    private static let autoOffKey     = "qa.autoOffMinutes"
    private static let snapshotKey    = "qa.failureSnapshot"

    private(set) var isEnabled: Bool = false
    var autoOffMinutes: Int {
        didSet { UserDefaults.standard.set(autoOffMinutes, forKey: Self.autoOffKey) }
    }

    static var isAvailable: Bool { true }

    private let ringCap = 600
    private(set) var events: [QAEvent] = []

    // Breadcrumbs: last 40 distinct labels, adjacent duplicates coalesced.
    private var rawCrumbs: [String] = []
    var breadcrumbs: [String] { rawCrumbs }

    // Tap tracking
    private(set) var tapCounts: [String: Int] = [:]
    var tapTotal: Int { tapCounts.values.reduce(0, +) }

    // Screen tracking
    private(set) var visitedScreens: [String] = []
    var currentScreen: String { visitedScreens.last ?? "—" }
    var screenCount: Int { visitedScreens.count }
    var deadScreens: [String] { visitedScreens.filter { ($0 != "—") && (tapCounts[$0] ?? 0) == 0 } }

    // Attempt tracking
    private var attemptRegistry: [UUID: (attempt: QAAttempt, id: UUID)] = [:]
    var unresolvedAttempts: [QAAttempt] { attemptRegistry.values.map(\.attempt) }
    var danglingAttempts: [QAAttempt] {
        unresolvedAttempts.filter { Date().timeIntervalSince($0.startedAt) > 10 }
    }
    var attemptCount: Int { attemptRegistry.count }

    // Counts
    var failureCount:   Int { events.filter { $0.kind == .failure   }.count }
    var violationCount: Int { events.filter { $0.kind == .violation }.count }

    // Invariants
    private(set) var invariantResults: [QAInvariantResult] = []
    private(set) var newViolations:   [QAInvariantResult] = []
    private(set) var fixedSinceLastRun: [QAInvariantResult] = []
    private var prevInvariantNames: Set<String> = []
    var openViolations: [String] {
        invariantResults.filter { $0.status == .violation }.map(\.name)
    }

    // Session
    private let sessionStart = Date()
    var sessionDurationText: String {
        let s = Int(Date().timeIntervalSince(sessionStart))
        let h = s / 3600; let m = (s % 3600) / 60; let sec = s % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
    }

    // Auto-off
    private var autoOffTask: Task<Void, Never>?
    private var lastBurstAt: Date?

    // MARK: Lifecycle

    private init() {
        autoOffMinutes = UserDefaults.standard.object(forKey: Self.autoOffKey).flatMap { $0 as? Int } ?? 0
        // isEnabled intentionally starts false — callers flip it after init.
        // Do NOT call QARecorder.shared here (swift_once deadlock, Build 75).
    }

    func enable() {
        guard Self.isAvailable else { return }
        isEnabled = true
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        scheduleAutoOff()
        QARuntimeMonitor.shared.start()
        QAProcessTracker.shared.start()
    }

    func disable() {
        isEnabled = false
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        autoOffTask?.cancel()
        autoOffTask = nil
        QARuntimeMonitor.shared.stop()
    }

    func toggle() {
        isEnabled ? disable() : enable()
    }

    private func scheduleAutoOff() {
        autoOffTask?.cancel()
        guard autoOffMinutes > 0 else { return }
        let mins = autoOffMinutes
        autoOffTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(mins) * 60))
            guard !Task.isCancelled else { return }
            self?.disable()
        }
    }

    // MARK: Recording

    @discardableResult
    func record(_ kind: QAEventKind,
                screen: String? = nil,
                label: String,
                detail: String = "") -> QAEvent {
        let ev = QAEvent(kind: kind,
                         screen: screen ?? currentScreen,
                         label: label,
                         detail: detail)
        events.append(ev)
        if events.count > ringCap { events.removeFirst(events.count - ringCap) }
        dropCrumb("\(kind == .screen ? "→" : "•") \(label)")
        return ev
    }

    func enteredScreen(_ name: String) {
        guard isEnabled else { return }
        if visitedScreens.last != name {
            visitedScreens.append(name)
            if visitedScreens.count > 400 { visitedScreens.removeFirst(visitedScreens.count - 400) }
        }
        record(.screen, screen: name, label: name)
        dropCrumb("→ \(name)")
    }

    func tapped() {
        guard isEnabled else { return }
        tapCounts[currentScreen, default: 0] += 1
    }

    // MARK: Attempts

    @discardableResult
    func attempt(_ label: String, detail: String = "") -> QAAttempt {
        let a = QAAttempt(label: label, screen: currentScreen)
        let key = UUID()
        attemptRegistry[key] = (a, key)
        record(.attempt, label: label, detail: detail)
        return a
    }

    func succeeded(_ attempt: QAAttempt) {
        removeAttempt(attempt)
        record(.success, screen: attempt.screen, label: attempt.label)
    }

    func failed(_ attempt: QAAttempt, detail: String = "") {
        removeAttempt(attempt)
        record(.failure, screen: attempt.screen, label: attempt.label, detail: detail)
    }

    func failed(_ attempt: QAAttempt, error: Error) {
        failed(attempt, detail: error.localizedDescription)
    }

    private func removeAttempt(_ a: QAAttempt) {
        attemptRegistry = attemptRegistry.filter { $0.value.attempt.label != a.label
            || $0.value.attempt.screen != a.screen }
    }

    // MARK: Breadcrumbs

    func crumb(_ text: String) { dropCrumb(text) }

    private func dropCrumb(_ text: String) {
        if rawCrumbs.last == text { return }
        rawCrumbs.append(text)
        if rawCrumbs.count > 40 { rawCrumbs.removeFirst(rawCrumbs.count - 40) }
    }

    // MARK: Invariants

    func setInvariantResults(_ results: [QAInvariantResult]) {
        let prevViolating = Set(invariantResults.filter { $0.status == .violation }.map(\.name))
        let newViolating  = Set(results.filter { $0.status == .violation }.map(\.name))
        newViolations     = results.filter { $0.status == .violation && !prevViolating.contains($0.name) }
        fixedSinceLastRun = invariantResults.filter { $0.status == .violation && !newViolating.contains($0.name) }
        invariantResults  = results
        for v in newViolations { record(.violation, label: v.name, detail: v.detail) }
    }

    // MARK: Failure snapshot

    private var lastSnapshotAt: Date?

    func scheduleFailureSnapshot(reason: String) {
        if let last = lastSnapshotAt, Date().timeIntervalSince(last) < 30 { return }
        lastSnapshotAt = Date()
        let text = fullExportText
        UserDefaults.standard.set(text, forKey: Self.snapshotKey)
        Task { await QAFolderMirror.shared.writeStableLog(text, name: "qa-failure-snapshot.txt") }
    }

    var previousSessionSnapshot: String? {
        UserDefaults.standard.string(forKey: Self.snapshotKey)
    }

    // MARK: Export

    var fullExportText: String {
        var out = [String]()
        out.append("── QA SESSION EXPORT ──")
        out.append("app: \(QA.config.appName) \(QA.config.version) (\(QA.config.buildNumber))")
        out.append("session: \(sessionDurationText)")
        out.append("screens visited: \(screenCount)")
        out.append("events: \(events.count)")
        out.append("failures: \(failureCount) · violations: \(violationCount)")
        out.append("")
        out.append("BREADCRUMBS")
        for crumb in rawCrumbs { out.append("  \(crumb)") }
        out.append("")
        out.append("INVARIANTS (\(invariantResults.count))")
        for r in invariantResults {
            out.append("  [\(r.status.rawValue.uppercased())] \(r.name) — \(r.detail)")
        }
        out.append("")
        out.append("EVENTS (last 100)")
        for ev in events.suffix(100) { out.append("  \(ev.line)") }
        out.append("")
        out.append(QARuntimeMonitor.shared.exportText)
        out.append("")
        out.append(QAProcessTracker.shared.exportText)
        out.append("")
        out.append(QATriage.shared.exportText)
        return out.joined(separator: "\n")
    }
}

// MARK: - .qaScreen modifier

private struct QAScreenModifier: ViewModifier {
    let name: String
    func body(content: Content) -> some View {
        content
            .onAppear { QARecorder.shared.enteredScreen(name) }
            .simultaneousGesture(
                TapGesture().onEnded { QARecorder.shared.tapped() }
            )
    }
}

extension View {
    /// Mark a screen with its QA name. Tracks visits, taps, and breadcrumbs.
    func qaScreen(_ name: String) -> some View {
        modifier(QAScreenModifier(name: name))
    }
}
