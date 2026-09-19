// QARuntimeMonitor.swift
// ─────────────────────────────────────────────────────────────────────────────
// Shared QACore — verbatim from Stocked Build 74, ConnectivityMonitor
// abstracted to QA.config.isOnline, BuildConfig abstracted to QA.config.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import UIKit
import Observation
import Darwin

// MARK: - Samples

nonisolated struct QAHitch: Identifiable, Sendable {
    var id          = UUID()
    var at: Date    = Date()
    var milliseconds: Double
    var screen: String
    var isSevere: Bool { milliseconds >= 1000 }
    var line: String {
        String(format: "%@  %.0f ms on %@", QAHitch.formatter.string(from: at), milliseconds, screen)
    }
    private static let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()
}

nonisolated struct QAMemorySample: Sendable {
    var at: Date = Date()
    var footprintMB: Double
    var screen: String
}

nonisolated struct QANetworkStat: Identifiable, Sendable {
    var id: String { name }
    var name: String
    var count: Int
    var failures: Int
    var totalSeconds: TimeInterval
    var worstSeconds: TimeInterval
    var averageMs: Double { count == 0 ? 0 : totalSeconds / Double(count) * 1000 }
    var line: String {
        String(format: "%@ — %d call%@, %d failed, avg %.0f ms, worst %.0f ms",
               name, count, count == 1 ? "" : "s", failures, averageMs, worstSeconds * 1000)
    }
}

// MARK: - Monitor

@MainActor
@Observable
final class QARuntimeMonitor {
    static let shared = QARuntimeMonitor()
    private init() {}

    private(set) var isRunning          = false
    private(set) var hitches:           [QAHitch] = []
    private(set) var memorySamples:     [QAMemorySample] = []
    private(set) var peakFootprintMB:   Double = 0
    private(set) var startFootprintMB:  Double = 0
    private(set) var currentFootprintMB:Double = 0
    private(set) var thermal:           ProcessInfo.ThermalState = .nominal
    private(set) var lowPower           = false
    private(set) var freeDiskMB:        Double = 0
    private(set) var online             = true
    @ObservationIgnored private(set) var frameCount = 0
    private(set) var discardedGaps      = 0

    private let hitchCap         = 120
    private let memoryCap        = 240
    private let hitchThresholdMs = 120.0
    private let implausibleGapMs = 10_000.0

    private var link:            CADisplayLink?
    private var linkTarget:      DisplayLinkTarget?
    private var lastFrameAt:     CFTimeInterval = 0
    private var measureAfter:    CFTimeInterval = 0
    private var sampler:         Task<Void, Never>?
    private var lastAutoTicketAt: Date?
    private var lastMemoryAlertAt: Date?
    private var lastMemoryAlertBand = 0
    private var isForeground     = true
    private var frameClockDirty  = true
    private var lifecycleObservers: [NSObjectProtocol] = []

    @ObservationIgnored private var worstHitchCache:   Double = 0
    @ObservationIgnored private var severeHitchCache:  Int    = 0
    @ObservationIgnored private var hitchScreenCounts: [String: Int] = [:]
    private var network: [String: QANetworkStat] = [:]

    // MARK: Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startFootprintMB  = Self.footprintMB()
        currentFootprintMB = startFootprintMB
        peakFootprintMB   = startFootprintMB
        sampleEnvironment()

        let target = DisplayLinkTarget()
        let l = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        l.add(to: .main, forMode: .common)
        link = l; linkTarget = target
        lastFrameAt = 0; measureAfter = CACurrentMediaTime() + 5
        isForeground = UIApplication.shared.applicationState == .active
        frameClockDirty = true
        observeLifecycle()

        sampler = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { return }
                self?.sampleMemory(); self?.sampleEnvironment()
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        link?.invalidate(); link = nil; linkTarget = nil
        sampler?.cancel(); sampler = nil
        for o in lifecycleObservers { NotificationCenter.default.removeObserver(o) }
        lifecycleObservers = []
    }

    // MARK: Lifecycle awareness

    private func observeLifecycle() {
        guard lifecycleObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let sleep = center.addObserver(forName: UIApplication.willResignActiveNotification,
                                       object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { QARuntimeMonitor.shared.enterSleep() }
        }
        let wake = center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                      object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { QARuntimeMonitor.shared.enterWake() }
        }
        lifecycleObservers = [sleep, wake]
    }

    private func enterSleep() { isForeground = false; frameClockDirty = true }
    private func enterWake() {
        isForeground = true; frameClockDirty = true; lastFrameAt = 0
        measureAfter = CACurrentMediaTime() + 3
        sampleMemory(); sampleEnvironment()
    }

    func clear() {
        hitches = []; memorySamples = []; network = [:]
        frameCount = 0; discardedGaps = 0
        peakFootprintMB = currentFootprintMB; startFootprintMB = currentFootprintMB
        lastMemoryAlertAt = nil; lastMemoryAlertBand = 0
    }

    // MARK: Frames

    fileprivate func frame(at timestamp: CFTimeInterval) {
        guard isRunning else { return }
        frameCount += 1
        defer { lastFrameAt = timestamp }
        guard isForeground else { return }
        if frameClockDirty { frameClockDirty = false; return }
        guard lastFrameAt > 0, timestamp >= measureAfter else { return }

        let deltaMs = (timestamp - lastFrameAt) * 1000
        guard deltaMs >= hitchThresholdMs else { return }

        if deltaMs >= implausibleGapMs {
            discardedGaps += 1
            QARecorder.shared.record(.note, screen: QARecorder.shared.currentScreen,
                                     label: "Frame clock jumped",
                                     detail: String(format: "%.0f ms — app was suspended", deltaMs))
            return
        }

        let screen = QARecorder.shared.currentScreen
        let hitch = QAHitch(milliseconds: deltaMs, screen: screen)
        hitches.append(hitch)
        worstHitchCache = max(worstHitchCache, hitch.milliseconds)
        if hitch.isSevere { severeHitchCache += 1 }
        hitchScreenCounts[screen, default: 0] += 1
        if hitches.count > hitchCap { hitches.removeFirst(hitches.count - hitchCap) }

        QARecorder.shared.record(hitch.isSevere ? .failure : .violation, screen: screen,
                                 label: hitch.isSevere ? "Main thread froze" : "Frame hitch",
                                 detail: String(format: "%.0f ms blocked", deltaMs))
        if hitch.isSevere { raiseFreezeTicket(hitch) }
    }

    private func raiseFreezeTicket(_ hitch: QAHitch) {
        if let last = lastAutoTicketAt, Date().timeIntervalSince(last) < 60 { return }
        lastAutoTicketAt = Date()
        let ctx = QAContextCapture.current()
        QATicketStore.shared.open(
            title: String(format: "Main thread blocked %.1fs on %@",
                          hitch.milliseconds / 1000, hitch.screen),
            body: """
            Raised automatically by the runtime monitor — no one typed this.

            The main thread did not produce a frame for \(Int(hitch.milliseconds)) ms on \
            \(hitch.screen). A block over 1s is inside the range where iOS may terminate \
            the app (signal 9).
            """,
            severity: hitch.milliseconds >= 2000 ? .blocker : .major,
            context: ctx, origin: .automatic)
    }

    var worstHitchMs:   Double { worstHitchCache }
    var severeHitchCount: Int  { severeHitchCache }
    var hitchesByScreen: [QAScreenCount] {
        hitchScreenCounts.map { QAScreenCount(screen: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    // MARK: Memory

    private func sampleMemory() {
        guard isRunning else { return }
        let mb = Self.footprintMB()
        currentFootprintMB = mb; peakFootprintMB = max(peakFootprintMB, mb)
        memorySamples.append(QAMemorySample(footprintMB: mb, screen: QARecorder.shared.currentScreen))
        if memorySamples.count > memoryCap { memorySamples.removeFirst(memorySamples.count - memoryCap) }

        let band = mb > 900 ? 2 : (mb > 600 && mb > startFootprintMB * 2.5 ? 1 : 0)
        let shouldAlert = band > 0 && (band > lastMemoryAlertBand ||
            lastMemoryAlertAt.map { Date().timeIntervalSince($0) >= 300 } != false)
        if shouldAlert && band == 2 {
            QARecorder.shared.record(.failure, label: "Memory very high",
                                     detail: String(format: "%.0f MB — jetsam range", mb))
        } else if shouldAlert && band == 1 {
            QARecorder.shared.record(.violation, label: "Memory climbing",
                                     detail: String(format: "%.0f MB, started %.0f MB", mb, startFootprintMB))
        }
        if shouldAlert { lastMemoryAlertAt = Date() }
        lastMemoryAlertBand = band
    }

    nonisolated static func footprintMB() -> Double {
        var info  = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
    }

    var memoryGrowthMB: Double { currentFootprintMB - startFootprintMB }

    // MARK: Environment

    private func sampleEnvironment() {
        let previousThermal = thermal
        thermal   = ProcessInfo.processInfo.thermalState
        lowPower  = ProcessInfo.processInfo.isLowPowerModeEnabled
        online    = QA.config.isOnline()
        freeDiskMB = Self.freeDiskMB()
        if thermal != previousThermal && (thermal == .serious || thermal == .critical) {
            QARecorder.shared.record(.violation,
                                     label: "Device thermal state \(Self.thermalName(thermal))",
                                     detail: "OS is throttling — timings not representative")
        }
        if freeDiskMB > 0 && freeDiskMB < 250 {
            QARecorder.shared.record(.violation, label: "Very low disk",
                                     detail: String(format: "%.0f MB free — writes may fail", freeDiskMB))
        }
    }

    nonisolated static func freeDiskMB() -> Double {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let bytes  = values.volumeAvailableCapacityForImportantUsage else { return 0 }
        return Double(bytes) / 1_048_576
    }

    nonisolated static func thermalName(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    var thermalName: String { Self.thermalName(thermal) }
    var isThrottled: Bool   { thermal == .serious || thermal == .critical || lowPower }

    // MARK: Network rollup

    func recordRequest(_ name: String, seconds: TimeInterval, failed: Bool) {
        guard QARecorder.shared.isEnabled else { return }
        var stat = network[name] ?? QANetworkStat(name: name, count: 0, failures: 0,
                                                  totalSeconds: 0, worstSeconds: 0)
        stat.count += 1; stat.failures += failed ? 1 : 0
        stat.totalSeconds += seconds; stat.worstSeconds = max(stat.worstSeconds, seconds)
        network[name] = stat
    }

    var networkStats:       [QANetworkStat] { network.values.sorted { $0.totalSeconds > $1.totalSeconds } }
    var networkCallCount:   Int { network.values.reduce(0) { $0 + $1.count } }
    var networkFailureCount:Int { network.values.reduce(0) { $0 + $1.failures } }

    // MARK: Export

    var headline: String {
        var parts = [String(format: "%.0f MB", currentFootprintMB)]
        if worstHitchMs > 0 { parts.append(String(format: "worst hitch %.0f ms", worstHitchMs)) }
        if isThrottled { parts.append(thermalName + (lowPower ? " · low power" : "")) }
        if !online { parts.append("offline") }
        return parts.joined(separator: " · ")
    }

    var exportText: String {
        var out = ["RUNTIME"]
        out.append(String(format: "  memory: %.0f MB now · %.0f MB peak · %+.0f MB since start",
                          currentFootprintMB, peakFootprintMB, memoryGrowthMB))
        out.append("  thermal: \(thermalName)\(lowPower ? " · low power mode" : "")")
        out.append(String(format: "  free disk: %.0f MB · %@", freeDiskMB, online ? "online" : "OFFLINE"))
        out.append("  frames observed: \(frameCount)")
        if hitches.isEmpty {
            out.append("  no frame hitches over \(Int(hitchThresholdMs)) ms")
        } else {
            out.append(String(format: "  hitches: %d (%d severe) · worst %.0f ms",
                              hitches.count, severeHitchCount, worstHitchMs))
            for h in hitches.suffix(15) { out.append("    \(h.line)") }
        }
        if !network.isEmpty {
            out.append("  network: \(networkCallCount) calls, \(networkFailureCount) failed")
            for s in networkStats.prefix(10) { out.append("    \(s.line)") }
        }
        return out.joined(separator: "\n")
    }
}

// MARK: - Display link target

private final class DisplayLinkTarget: NSObject {
    @objc func tick(_ link: CADisplayLink) {
        MainActor.assumeIsolated { QARuntimeMonitor.shared.frame(at: link.timestamp) }
    }
}

// MARK: - Context capture

@MainActor
enum QAContextCapture {
    static func current() -> QATicketContext {
        let recorder = QARecorder.shared
        let tracker  = QAProcessTracker.shared
        let runtime  = QARuntimeMonitor.shared

        var c = QATicketContext()
        c.screen           = recorder.currentScreen
        c.breadcrumbs      = Array(recorder.breadcrumbs.suffix(40))
        c.runningProcesses = tracker.running.prefix(10).map(\.line)
        c.stalledProcesses = tracker.stalled.prefix(10).map(\.line)
        c.recentFailures   = recorder.events.filter { $0.kind == .failure }.suffix(8).map(\.line)
        c.openViolations   = recorder.invariantResults
            .filter { $0.status == .violation }
            .map { "\($0.name) — \($0.detail)" }
        c.appVersion       = QA.config.version
        c.build            = QA.config.buildNumber
        c.identity         = QAIdentityStore.shared.capture()
        c.device           = c.identity?.modelName ?? UIDevice.current.model
        c.os               = (c.identity?.deviceFamily == "iPad" ? "iPadOS " : "iOS ")
                           + UIDevice.current.systemVersion
        c.memoryMB         = runtime.isRunning ? runtime.currentFootprintMB : QARuntimeMonitor.footprintMB()
        c.thermal          = QARuntimeMonitor.thermalName(ProcessInfo.processInfo.thermalState)
        c.lowPower         = ProcessInfo.processInfo.isLowPowerModeEnabled
        c.online           = QA.config.isOnline()
        c.freeDiskMB       = runtime.freeDiskMB > 0 ? runtime.freeDiskMB : QARuntimeMonitor.freeDiskMB()
        c.sessionDuration  = recorder.sessionDurationText
        c.tapsOnScreen     = recorder.tapCounts[recorder.currentScreen] ?? 0
        c.worstHitchMs     = runtime.worstHitchMs
        c.environment      = QAEnvironmentSnapshot.lines()
        return c
    }
}
