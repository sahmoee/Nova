import SwiftUI
import UIKit
import Combine
import Darwin

enum UnifiedQASettings {
    static let enabledKey = "nova.qa.enabled"
    static let longPressKey = "nova.qa.longPress.enabled"
    static let autoMonitorKey = "nova.qa.monitor.enabled"
}

struct NovaQADiagnostics: Codable, Sendable {
    var libraryItems = 0
    var offlineDownloads = 0
    var activeDownloads = 0
    var failedDownloads = 0
    var smbFolders = 0
    var installedAddons = 0
    var network = "unknown"
    var networkFlags = "none"
}

struct NovaQAEvent: Codable, Identifiable, Sendable {
    var id = UUID()
    var at = Date()
    var kind: String
    var detail: String
}

struct NovaQAHitch: Codable, Identifiable, Sendable {
    var id = UUID()
    var at = Date()
    var milliseconds: Double
}

@MainActor
final class NovaQARuntime: ObservableObject {
    static let shared = NovaQARuntime()

    @Published private(set) var events: [NovaQAEvent] = []
    @Published private(set) var hitches: [NovaQAHitch] = []
    @Published private(set) var peakMemoryMB: Double = 0
    @Published private(set) var currentMemoryMB: Double = 0
    @Published private(set) var thermalState = "Nominal"
    @Published private(set) var freeDiskMB: Double = 0
    @Published private(set) var isRunning = false

    private var displayLink: CADisplayLink?
    private var linkTarget: NovaQADisplayLinkTarget?
    private var lastFrame: CFTimeInterval = 0
    private var sampleTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true
        record("lifecycle", "Nova QA monitoring enabled")
        let target = NovaQADisplayLinkTarget { [weak self] timestamp in self?.frame(timestamp) }
        let link = CADisplayLink(target: target, selector: #selector(NovaQADisplayLinkTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        linkTarget = target
        sample()
        sampleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                self?.sample()
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        record("lifecycle", "Nova QA monitoring disabled")
        isRunning = false
        displayLink?.invalidate()
        displayLink = nil
        linkTarget = nil
        sampleTask?.cancel()
        sampleTask = nil
        lastFrame = 0
    }

    func record(_ kind: String, _ detail: String) {
        events.insert(NovaQAEvent(kind: kind, detail: detail), at: 0)
        if events.count > 80 { events.removeLast(events.count - 80) }
    }

    func clearSession() {
        events = []
        hitches = []
        peakMemoryMB = currentMemoryMB
    }

    func contextText(diagnostics: NovaQADiagnostics) -> String {
        let recent = events.prefix(20).map { "\($0.kind): \($0.detail)" }.joined(separator: " | ")
        let worst = hitches.map(\.milliseconds).max() ?? 0
        let memory = Int(currentMemoryMB.rounded())
        let peak = Int(peakMemoryMB.rounded())
        let hitch = Int(worst.rounded())
        let disk = Int(freeDiskMB.rounded())
        return "Library \(diagnostics.libraryItems); downloads \(diagnostics.offlineDownloads) (\(diagnostics.activeDownloads) active, \(diagnostics.failedDownloads) failed); SMB folders \(diagnostics.smbFolders); add-ons \(diagnostics.installedAddons); network \(diagnostics.network) \(diagnostics.networkFlags); memory \(memory) MB (peak \(peak)); worst hitch \(hitch) ms; thermal \(thermalState); disk \(disk) MB; recent events [\(recent)]"
    }

    private func frame(_ timestamp: CFTimeInterval) {
        defer { lastFrame = timestamp }
        guard lastFrame > 0, UIApplication.shared.applicationState == .active else { return }
        let gap = (timestamp - lastFrame) * 1_000
        guard gap >= 120, gap < 10_000 else { return }
        hitches.insert(NovaQAHitch(milliseconds: gap), at: 0)
        if hitches.count > 100 { hitches.removeLast(hitches.count - 100) }
    }

    private func sample() {
        currentMemoryMB = Self.memoryMB()
        peakMemoryMB = max(peakMemoryMB, currentMemoryMB)
        thermalState = Self.thermalName(ProcessInfo.processInfo.thermalState)
        let home = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        if let values = try? home?.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let bytes = values.volumeAvailableCapacityForImportantUsage {
            freeDiskMB = Double(bytes) / 1_048_576
        }
    }

    private static func memoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    private static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state { case .nominal: "Nominal"; case .fair: "Fair"; case .serious: "Serious"; case .critical: "Critical"; @unknown default: "Unknown" }
    }
}

private final class NovaQADisplayLinkTarget: NSObject {
    let action: (CFTimeInterval) -> Void
    init(action: @escaping (CFTimeInterval) -> Void) { self.action = action }
    @objc func tick(_ link: CADisplayLink) { action(link.timestamp) }
}

struct UnifiedQATicket: Codable, Identifiable {
    var id = UUID()
    var number: String
    var title: String
    var body: String
    var severity: String
    var status = "open"
    var createdAt = Date()
    var updatedAt = Date()
    var screen: String
    var hasScreenshot: Bool
    var environment: [String: String]
    var resolution: String?
    var verifiedAt: Date?
    var refileCount: Int?
    var requiresManualReview: Bool?
    var syncState: String?
    var lastSyncError: String?
    var history: [String]?
}

struct NovaQAReportDraft: Identifiable {
    let id = UUID()
    var screenshot: UIImage?
    var screen: String
    var context: String
}

@MainActor
final class UnifiedQAStore: ObservableObject {
    static let shared = UnifiedQAStore()
    @Published private(set) var tickets: [UnifiedQATicket] = []
    @Published var syncMessage = ""
    @Published private(set) var isSyncing = false
    private let base = URL(string: "https://api.sowensstudios.com/_unified/qa")!
    private init() { load() }

    var openCount: Int { tickets.filter { $0.status != "verified" }.count }
    var unsyncedCount: Int { tickets.filter { $0.syncState != "synced" }.count }

    func save(app: String, source: String, prefix: String, ticket: UnifiedQATicket?, title: String,
              details: String, severity: String, screen: String, category: String, status: String,
              resolution: String, requiresManualReview: Bool, screenshot: UIImage?, diagnosticContext: String) {
        let shot = screenshot ?? (ticket == nil ? Self.capture() : nil)
        var value = ticket ?? UnifiedQATicket(number: nextNumber(prefix: prefix), title: title,
            body: details, severity: severity, screen: screen, hasScreenshot: shot != nil,
            environment: Self.environment(app: app), resolution: nil, verifiedAt: nil,
            refileCount: nil, syncState: "pending", lastSyncError: nil, history: [])
        value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.body = details.trimmingCharacters(in: .whitespacesAndNewlines)
        value.severity = severity
        value.screen = screen
        value.status = status
        value.requiresManualReview = requiresManualReview
        value.environment["novaCategory"] = category
        if !diagnosticContext.isEmpty { value.environment["novaDiagnostics"] = diagnosticContext }
        value.resolution = resolution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : resolution
        value.updatedAt = Date()
        value.hasScreenshot = value.hasScreenshot || shot != nil
        value.syncState = "pending"
        value.history = (value.history ?? []) + ["\(Date().formatted()): \(ticket == nil ? "filed" : "edited") as \(status)"]
        replace(value)
        persist(ticket: value, screenshot: shot)
        NovaQARuntime.shared.record("ticket", "Saved \(value.number): \(value.title)")
        Task { await sync(value.id, source: source) }
    }

    func retryAll(source: String) {
        Task {
            isSyncing = true
            defer { isSyncing = false }
            for ticket in tickets where ticket.syncState != "synced" { await sync(ticket.id, source: source) }
        }
    }

    func verify(_ ticket: UnifiedQATicket, source: String) {
        var value = ticket
        value.status = "verified"; value.verifiedAt = Date(); value.updatedAt = Date(); value.syncState = "pending"
        value.history = (value.history ?? []) + ["\(Date().formatted()): fix verified on device"]
        replace(value); persist(ticket: value, screenshot: nil); Task { await sync(value.id, source: source) }
    }

    func refile(_ ticket: UnifiedQATicket, source: String) {
        var value = ticket
        value.status = "open"; value.verifiedAt = nil; value.refileCount = (value.refileCount ?? 0) + 1
        value.updatedAt = Date(); value.syncState = "pending"
        value.history = (value.history ?? []) + ["\(Date().formatted()): refiled after failed verification"]
        replace(value); persist(ticket: value, screenshot: Self.capture()); Task { await sync(value.id, source: source) }
    }

    private func replace(_ ticket: UnifiedQATicket) {
        if let index = tickets.firstIndex(where: { $0.id == ticket.id }) { tickets[index] = ticket }
        else { tickets.insert(ticket, at: 0) }
    }

    private func nextNumber(prefix: String) -> String {
        let key = "unifiedQA.counter.\(prefix)"
        let next = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(next, forKey: key)
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(prefix)-\(build)-\(String(format: "%04d", next))"
    }

    private var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QAReports", isDirectory: true)
    }

    private func persist(ticket: UnifiedQATicket, screenshot: UIImage?) {
        let folder = root.appendingPathComponent(ticket.number, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(ticket) { try? data.write(to: folder.appendingPathComponent("ticket.json"), options: .atomic) }
        let fixed = ticket.resolution.map { "\n## What was fixed\n\n\($0)\n" } ?? ""
        let diagnostics = ticket.environment["novaDiagnostics"].map { "\n## Nova diagnostics\n\n\($0)\n" } ?? ""
        let history = (ticket.history ?? []).map { "- \($0)" }.joined(separator: "\n")
        let review = ticket.requiresManualReview == true ? "\n> **REQUIRES MANUAL REVIEW:** Ask the tester for specific expected behavior or design intent before changing code.\n" : ""
        let report = "# \(ticket.number) — \(ticket.title)\n\n**\(ticket.severity)** · \(ticket.status) · \(ticket.environment["novaCategory"] ?? "General")\n\(review)\n## Report\n\n\(ticket.body)\n\(fixed)\(diagnostics)\n## Context\n\n- Screen: \(ticket.screen)\n- Nova: \(ticket.environment["appVersion"] ?? "?") build \(ticket.environment["build"] ?? "?")\n- Device: \(ticket.environment["device"] ?? "?") · \(ticket.environment["os"] ?? "?")\n\n## History\n\n\(history)\n"
        try? Data(report.utf8).write(to: folder.appendingPathComponent("report.md"), options: .atomic)
        if let data = screenshot?.jpegData(compressionQuality: 0.72) { try? data.write(to: folder.appendingPathComponent("screenshot.jpg"), options: .atomic) }
        saveIndex()
    }

    private func saveIndex() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(tickets) { try? data.write(to: root.appendingPathComponent("tickets.json"), options: .atomic) }
    }

    private func load() {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: root.appendingPathComponent("tickets.json")),
           let values = try? decoder.decode([UnifiedQATicket].self, from: data) {
            tickets = values
            applyShippedResolutions()
        }
    }

    private func applyShippedResolutions() {
        let resolutions = [
            "NVA-23-0001": "Removed nested disabled buttons from every Sources card. Each card is now a non-interactive NavigationLink label, so Real-Debrid, Addons, SMB, Trakt, SIMKL, TMDB, Direct URL, and Magnet Link all receive taps and open their destination."
        ]
        var changed = false
        for index in tickets.indices where tickets[index].status == "open" {
            guard let resolution = resolutions[tickets[index].number] else { continue }
            tickets[index].status = "fixed"
            tickets[index].resolution = resolution
            tickets[index].updatedAt = Date()
            tickets[index].syncState = "pending"
            tickets[index].history = (tickets[index].history ?? []) + ["\(Date().formatted()): fixed in shipped source; awaiting device verification"]
            changed = true
        }
        if changed { saveIndex() }
    }

    private func sync(_ id: UUID, source: String) async {
        guard let ticket = tickets.first(where: { $0.id == id }) else { return }
        do {
            let shotURL = root.appendingPathComponent(ticket.number).appendingPathComponent("screenshot.jpg")
            if ticket.hasScreenshot, let data = try? Data(contentsOf: shotURL) {
                var request = URLRequest(url: base.appendingPathComponent("shots").appending(queryItems: [URLQueryItem(name: "ticket", value: ticket.number), URLQueryItem(name: "kind", value: "screenshot")]))
                request.httpMethod = "POST"; request.httpBody = data; request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
                let (_, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode ?? 500 < 300 else { throw URLError(.badServerResponse) }
            }
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let ticketObject = try JSONSerialization.jsonObject(with: encoder.encode(ticket))
            let envelope: [String: Any] = ["schema": "stocked-qa-report/v1", "source": source, "kind": "tickets", "generatedAt": ISO8601DateFormatter().string(from: Date()), "tickets": [ticketObject]]
            var request = URLRequest(url: base.appendingPathComponent("reports")); request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: envelope); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (_, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode ?? 500 < 300 else { throw URLError(.badServerResponse) }
            updateSync(id, state: "synced", error: nil); syncMessage = "\(ticket.number) synced"
        } catch {
            updateSync(id, state: "pending", error: error.localizedDescription)
            syncMessage = "Saved locally · \(unsyncedCount) waiting to sync"
        }
    }

    private func updateSync(_ id: UUID, state: String, error: String?) {
        guard let index = tickets.firstIndex(where: { $0.id == id }) else { return }
        tickets[index].syncState = state; tickets[index].lastSyncError = error
        persist(ticket: tickets[index], screenshot: nil)
    }

    private static func environment(app: String) -> [String: String] {
        ["app": app, "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
         "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
         "device": UIDevice.current.model, "os": "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"]
    }

    static func capture() -> UIImage? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }.flatMap(\.windows)
            .filter { !$0.isHidden && $0.alpha > 0 && $0.windowLevel <= .alert }.sorted { $0.windowLevel.rawValue < $1.windowLevel.rawValue }
        guard let first = windows.first else { return nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(bounds: first.bounds, format: format).image { _ in
            windows.forEach { $0.drawHierarchy(in: $0.bounds, afterScreenUpdates: false) }
        }
    }
}

struct UnifiedQAReporter: View {
    let app: String; let source: String; let prefix: String
    var diagnostics: () -> NovaQADiagnostics = { NovaQADiagnostics() }
    @StateObject private var store = UnifiedQAStore.shared
    @StateObject private var runtime = NovaQARuntime.shared
    @AppStorage(UnifiedQASettings.longPressKey) private var longPressEnabled = true
    @AppStorage(UnifiedQASettings.autoMonitorKey) private var monitorEnabled = true
    @State private var presented = false
    @State private var draft: NovaQAReportDraft?

    var body: some View {
        ZStack {
            if longPressEnabled {
                NovaQALongPressCatcher {
                    let snapshot = diagnostics()
                    draft = NovaQAReportDraft(screenshot: UnifiedQAStore.capture(), screen: Self.currentScreen(),
                                              context: runtime.contextText(diagnostics: snapshot))
                }
                .frame(width: 0, height: 0)
            }
            Button { presented = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "ladybug.fill").padding(12).background(.ultraThinMaterial).clipShape(Circle())
                    if store.openCount > 0 { Text("\(store.openCount)").font(.caption2.bold()).padding(4).background(.red, in: Circle()).offset(x: 4, y: -4) }
                }
            }
            .accessibilityLabel("Open Nova QA")
        }
        .sheet(isPresented: $presented) { NovaQAHub(app: app, source: source, prefix: prefix, diagnostics: diagnostics).environmentObject(store).environmentObject(runtime) }
        .sheet(item: $draft) { draft in NovaQATicketEditor(app: app, source: source, prefix: prefix, ticket: nil, draft: draft).environmentObject(store) }
        .onAppear { if monitorEnabled { runtime.start() }; store.retryAll(source: source) }
        .onChange(of: monitorEnabled) { _, enabled in enabled ? runtime.start() : runtime.stop() }
    }

    static func currentScreen() -> String {
        let root = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: { $0.isKeyWindow })?.rootViewController
        var current = root
        while let next = current?.presentedViewController { current = next }
        return current?.navigationItem.title ?? String(describing: type(of: current ?? UIViewController()))
    }
}

private struct NovaQALongPressCatcher: UIViewRepresentable {
    let onFire: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onFire: onFire) }
    func makeUIView(context: Context) -> UIView { let view = ObserverView(); view.coordinator = context.coordinator; view.isUserInteractionEnabled = false; return view }
    func updateUIView(_ view: UIView, context: Context) { context.coordinator.onFire = onFire }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.detach() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onFire: () -> Void; weak var window: UIWindow?; var recognizer: UILongPressGestureRecognizer?
        init(onFire: @escaping () -> Void) { self.onFire = onFire }
        func attach(_ window: UIWindow) {
            guard self.window !== window else { return }; detach()
            let press = UILongPressGestureRecognizer(target: self, action: #selector(fired(_:)))
            press.minimumPressDuration = 0.7; press.allowableMovement = 24; press.cancelsTouchesInView = false; press.delegate = self
            window.addGestureRecognizer(press); self.window = window; recognizer = press
        }
        func detach() { if let recognizer { window?.removeGestureRecognizer(recognizer) }; recognizer = nil; window = nil }
        @objc func fired(_ gesture: UILongPressGestureRecognizer) { if gesture.state == .began { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); onFire() } }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }

    final class ObserverView: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() { super.didMoveToWindow(); if let window { coordinator?.attach(window) } else { coordinator?.detach() } }
    }
}

struct UnifiedQASettingsView: View {
    @AppStorage(UnifiedQASettings.enabledKey) private var enabled = false
    @AppStorage(UnifiedQASettings.longPressKey) private var longPress = true
    @AppStorage(UnifiedQASettings.autoMonitorKey) private var monitor = true
    var body: some View {
        Form {
            Section("Nova QA") {
                Toggle("Enable QA tools", isOn: $enabled)
                Toggle("Press and hold to report", isOn: $longPress).disabled(!enabled)
                Toggle("Monitor performance and resources", isOn: $monitor).disabled(!enabled)
            }
            Section { Text("Nova QA captures playback/source state, library and download counts, SMB configuration, network conditions, memory, thermal state, frame hitches, recent QA activity, and a screenshot. Tickets sync automatically and retain edit, fix, verification, and refile history.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Quality Assurance")
    }
}

private struct NovaQAHub: View {
    let app: String; let source: String; let prefix: String; let diagnostics: () -> NovaQADiagnostics
    @EnvironmentObject var store: UnifiedQAStore
    @EnvironmentObject var runtime: NovaQARuntime
    @Environment(\.dismiss) var dismiss
    @State private var editing: UnifiedQATicket?
    @State private var draft: NovaQAReportDraft?

    var body: some View {
        NavigationStack {
            List {
                Section("Nova status") {
                    let snapshot = diagnostics()
                    LabeledContent("Library", value: "\(snapshot.libraryItems) items")
                    LabeledContent("Downloads", value: "\(snapshot.offlineDownloads) total · \(snapshot.activeDownloads) active")
                    LabeledContent("SMB folders", value: "\(snapshot.smbFolders)")
                    LabeledContent("Network", value: snapshot.network)
                    LabeledContent("Memory", value: "\(Int(runtime.currentMemoryMB)) MB · peak \(Int(runtime.peakMemoryMB))")
                    LabeledContent("Worst hitch", value: "\(Int(runtime.hitches.map(\.milliseconds).max() ?? 0)) ms")
                }
                Section("Deep QA") {
                    NavigationLink("Open Nova QA Lab") {
                        UnifiedQADeepView(app: app, tickets: store.tickets,
                                          unsyncedCount: store.unsyncedCount,
                                          memoryMB: Int(runtime.currentMemoryMB),
                                          hitchMS: Int(runtime.hitches.map(\.milliseconds).max() ?? 0))
                    }
                    Text("App-specific checklists, autonomous findings, tracked processes, run history, recurring-ticket detection, search, and full diagnostics.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Tickets") {
                    HStack { Label("\(store.openCount) open", systemImage: "exclamationmark.bubble"); Spacer(); Label("\(store.unsyncedCount) pending", systemImage: "arrow.triangle.2.circlepath") }
                    if !store.syncMessage.isEmpty { Text(store.syncMessage).font(.caption).foregroundStyle(.secondary) }
                    Button("File Nova Ticket") { draft = NovaQAReportDraft(screenshot: UnifiedQAStore.capture(), screen: UnifiedQAReporter.currentScreen(), context: runtime.contextText(diagnostics: diagnostics())) }
                    Button(store.isSyncing ? "Syncing…" : "Retry Pending Sync") { store.retryAll(source: source) }.disabled(store.isSyncing || store.unsyncedCount == 0)
                    ForEach(store.tickets) { ticket in
                        Button { editing = ticket } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(ticket.number).font(.caption.monospaced()); Spacer(); Image(systemName: ticket.syncState == "synced" ? "checkmark.icloud" : "icloud.slash") }
                                Text(ticket.title).font(.headline)
                                Text("\(ticket.status.capitalized) · \(ticket.severity.capitalized) · \(ticket.environment["novaCategory"] ?? "General")").font(.caption).foregroundStyle(.secondary)
                                if ticket.requiresManualReview == true { Label("Requires manual review", systemImage: "person.crop.circle.badge.questionmark").font(.caption).foregroundStyle(.orange) }
                                if let resolution = ticket.resolution { Text("Fixed: \(resolution)").font(.caption).foregroundStyle(.green).lineLimit(3) }
                            }
                        }
                    }
                }
                Section("Recent QA activity") {
                    if runtime.events.isEmpty { Text("No activity recorded this session.").foregroundStyle(.secondary) }
                    ForEach(runtime.events.prefix(20)) { event in VStack(alignment: .leading) { Text(event.detail); Text(event.at.formatted(date: .omitted, time: .standard) + " · " + event.kind).font(.caption).foregroundStyle(.secondary) } }
                    Button("Clear Session Log", role: .destructive) { runtime.clearSession() }
                }
            }
            .navigationTitle("Nova QA")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $draft) { NovaQATicketEditor(app: app, source: source, prefix: prefix, ticket: nil, draft: $0).environmentObject(store) }
            .sheet(item: $editing) { NovaQATicketEditor(app: app, source: source, prefix: prefix, ticket: $0, draft: nil).environmentObject(store) }
        }
    }
}

private struct NovaQATicketEditor: View {
    let app: String; let source: String; let prefix: String; let ticket: UnifiedQATicket?; let draft: NovaQAReportDraft?
    @EnvironmentObject var store: UnifiedQAStore
    @Environment(\.dismiss) var dismiss
    @State private var title: String; @State private var details: String; @State private var severity: String
    @State private var screen: String; @State private var category: String; @State private var status: String; @State private var resolution: String
    @State private var requiresManualReview: Bool
    private let categories = ["Playback", "Streams & Sources", "SMB", "Library & Metadata", "Downloads", "Calendar & Episodes", "Notifications", "Tracking & Accounts", "Search & Browse", "Subtitles", "UI & Accessibility", "Performance", "Other"]

    init(app: String, source: String, prefix: String, ticket: UnifiedQATicket?, draft: NovaQAReportDraft?) {
        self.app=app; self.source=source; self.prefix=prefix; self.ticket=ticket; self.draft=draft
        _title=State(initialValue: ticket?.title ?? ""); _details=State(initialValue: ticket?.body ?? "")
        _severity=State(initialValue: ticket?.severity ?? "major"); _screen=State(initialValue: ticket?.screen ?? draft?.screen ?? "Current screen")
        _category=State(initialValue: ticket?.environment["novaCategory"] ?? "Other"); _status=State(initialValue: ticket?.status ?? "open"); _resolution=State(initialValue: ticket?.resolution ?? "")
        _requiresManualReview=State(initialValue: ticket?.requiresManualReview ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What went wrong?") { TextField("Short title", text: $title); TextField("Expected behavior and what happened", text: $details, axis: .vertical).lineLimit(4...10) }
                Section("Nova context") { Picker("Area", selection: $category) { ForEach(categories, id: \.self) { Text($0) } }; Picker("Severity", selection: $severity) { Text("Blocker").tag("blocker"); Text("Major").tag("major"); Text("Minor").tag("minor") }; Toggle("Requires manual review", isOn: $requiresManualReview); Text("Turn this on when your wording or design intent needs human interpretation. AI will ask for specifics instead of guessing.").font(.caption).foregroundStyle(.secondary); TextField("Screen", text: $screen); if draft?.screenshot != nil || ticket?.hasScreenshot == true { Label("Screenshot attached", systemImage: "camera.fill").foregroundStyle(.green) } }
                if ticket != nil { Section("Fix lifecycle") { Picker("Status", selection: $status) { Text("Open").tag("open"); Text("Investigating").tag("investigating"); Text("Fixed — needs verification").tag("fixed"); Text("Verified").tag("verified") }; TextField("What was fixed", text: $resolution, axis: .vertical).lineLimit(3...8); if let ticket, ticket.status == "fixed" { Button("Verify Fix") { store.verify(ticket, source: source); dismiss() }; Button("Refile — still broken", role: .destructive) { store.refile(ticket, source: source); dismiss() } }; if let history = ticket?.history { ForEach(history, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) } } } }
                Section { Text("Saving writes JSON, Markdown, and screenshot evidence locally, then syncs automatically. Failed uploads remain pending and retry when Nova QA opens.").font(.caption).foregroundStyle(.secondary) }
            }
            .navigationTitle(ticket == nil ? "New Nova Ticket" : ticket!.number)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { store.save(app: app, source: source, prefix: prefix, ticket: ticket, title: title, details: details, severity: severity, screen: screen, category: category, status: status, resolution: resolution, requiresManualReview: requiresManualReview, screenshot: draft?.screenshot, diagnosticContext: draft?.context ?? ticket?.environment["novaDiagnostics"] ?? ""); dismiss() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || (status == "fixed" && resolution.trimmingCharacters(in: .whitespaces).isEmpty)) } }
        }
    }
}
struct UnifiedQACheck: Identifiable, Codable, Hashable {
    let id: String
    let area: String
    let title: String
    let expected: String
}

enum UnifiedQAVerdict: String, Codable, CaseIterable {
    case untested, pass, fail, blocked
    var symbol: String {
        switch self { case .untested: "circle"; case .pass: "checkmark.circle.fill"; case .fail: "xmark.octagon.fill"; case .blocked: "exclamationmark.triangle.fill" }
    }
    var color: Color {
        switch self { case .untested: .secondary; case .pass: .green; case .fail: .red; case .blocked: .orange }
    }
}

struct UnifiedQACheckState: Codable {
    var verdict: UnifiedQAVerdict = .untested
    var note = ""
    var updatedAt = Date()
}

struct UnifiedQAProcess: Identifiable, Codable {
    var id = UUID()
    var name: String
    var startedAt = Date()
    var endedAt: Date?
    var status = "running"
    var detail = ""
}

struct UnifiedQARun: Identifiable, Codable {
    var id = UUID()
    var startedAt = Date()
    var endedAt: Date?
    var passed = 0
    var failed = 0
    var blocked = 0
}

struct UnifiedQAFinding: Identifiable, Codable {
    var id = UUID()
    var severity: String
    var area: String
    var detail: String
    var createdAt = Date()
}

struct UnifiedQAProfile {
    let app: String
    let checks: [UnifiedQACheck]

    static func forApp(_ app: String) -> UnifiedQAProfile {
        switch app.lowercased() {
        case "nova": return .init(app: app, checks: nova)
        case "atlas": return .init(app: app, checks: atlas)
        default: return .init(app: app, checks: sesh)
        }
    }

    private static func item(_ id: String, _ area: String, _ title: String, _ expected: String) -> UnifiedQACheck {
        .init(id: id, area: area, title: title, expected: expected)
    }

    static let nova = [
        item("launch", "App", "Cold launch and resume", "Launches without a blank screen and restores the correct tab."),
        item("browse", "Browse", "Browse shelves", "Shelves load, scroll smoothly, and do not duplicate individual episodes."),
        item("search", "Browse", "Search and filters", "Movies and series resolve accurately and filters remain responsive."),
        item("detail", "Catalog", "Movie and series details", "Metadata, artwork, seasons, progress, and actions match the selected title."),
        item("episodes", "Catalog", "Episode grouping", "Episodes remain inside their series; only the most recently watched series entry appears elsewhere."),
        item("streams", "Playback", "Stream discovery", "Providers resolve, rank, retry, and explain unavailable sources."),
        item("player", "Playback", "Playback lifecycle", "Play, pause, seek, subtitles, progress, resume, and completion work."),
        item("external", "Playback", "External player return", "External playback launches safely and reconciles progress on return."),
        item("downloads", "Downloads", "Long-press download", "Long-pressing a movie or episode queues the correct item."),
        item("manager", "Downloads", "Download manager", "Pause, resume, retry, delete, storage, and offline playback remain consistent."),
        item("calendar", "Episodes", "Release calendar", "Only the newest available or release episode is surfaced."),
        item("notify", "Episodes", "Episode notifications", "Only the newest episode creates a notification and duplicates are suppressed."),
        item("library", "My Nova", "Library identity", "Watch progress and identity deduplicate across sources."),
        item("smb", "My Nova", "SMB folder browser", "Authentication, browsing, selection, reconnect, and library ingestion work."),
        item("trakt", "Tracking", "Trakt sync", "Authentication, expiry, watch state, ratings, and retries reconcile."),
        item("simkl", "Tracking", "SIMKL sync", "PIN login, token persistence, lists, watched state, and errors work."),
        item("tmdb", "Tracking", "TMDB account", "Account connection and list actions give visible success or failure."),
        item("addons", "Sources", "Addon management", "Install, configure, health, ordering, and removal work."),
        item("debrid", "Sources", "Real-Debrid", "Login, validation, expiry, resolution, and clear errors work."),
        item("direct", "Sources", "Direct URL and magnet", "Legal gate, validation, routing, and failures work."),
        item("accessibility", "UI", "Accessibility", "Labels, focus order, Dynamic Type, contrast, and 44-point targets pass."),
        item("network", "Reliability", "Offline and recovery", "Offline state is clear and pending work retries once."),
        item("memory", "Reliability", "Long-session resources", "Memory stays bounded and background/foreground does not leak playback."),
        item("privacy", "Security", "Credentials and reports", "Secrets stay in Keychain and QA evidence contains no secret values."),
        item("ticket", "QA", "Ticket lifecycle", "File, screenshot, edit, sync, fixed, verify, and refile preserve history.")
    ]

    static let atlas = [
        item("launch", "App", "Cold launch and resume", "Atlas launches, restores navigation, and preserves unfinished work."),
        item("browse", "Guides", "Browse map and categories", "All categories, shelves, filters, and recent guides route correctly."),
        item("search", "Guides", "Search ranking", "Titles, steps, tags, synonyms, and safety content rank predictably."),
        item("guide", "Guides", "Guide details", "Steps, tools, time, difficulty, tips, and safety notes remain complete."),
        item("progress", "Guides", "Step progress", "Step completion, undo, overall completion, and resume persist."),
        item("save", "Library", "Save, pin, and recent", "Saved, pinned, and recently viewed guides deduplicate and persist."),
        item("collections", "Library", "Collections", "Create, rename, add, remove, and delete preserve guide identity."),
        item("ask", "AI Guides", "Ask Atlas generation", "Requests validate, queue offline, generate complete guides, and explain errors."),
        item("policy", "AI Guides", "Safety and content policy", "Unsafe requests are refused while legitimate safety guidance remains useful."),
        item("documents", "Documents", "Create and edit documents", "Capture, OCR, generation, editing, history, and export work."),
        item("scanner", "Documents", "Camera and document scanning", "Permission, cancellation, multi-page scans, and failures recover."),
        item("export", "Documents", "Document export", "Share and export produce readable, complete artifacts."),
        item("history", "Account", "History and reset", "History displays accurately and reset removes only documented user data."),
        item("streak", "Progress", "Streak and freezes", "Day boundaries, freezes, longest streak, and timezone changes are correct."),
        item("milestones", "Progress", "Milestones", "Each milestone earns once, celebrates once, and remains visible."),
        item("profile", "Account", "Profile and appearance", "Profile, theme, text size, and identity persist."),
        item("backup", "Account", "iCloud backup and restore", "Merges do not lose or duplicate saves, progress, notes, or documents."),
        item("catalog", "Content", "Catalog integrity", "Every guide has unique identity, valid category, ordered steps, and safety metadata."),
        item("remote", "Content", "Remote catalog", "Signing, replacement, fallback, and bundled-content recovery work."),
        item("offline", "Reliability", "Offline request queue", "Queued requests remain visible and retry exactly once when online."),
        item("widgets", "Extensions", "Widgets and activities", "Widget and Live Activity state reflects the app and handles stale data."),
        item("accessibility", "UI", "Accessibility", "VoiceOver, focus, Dynamic Type, contrast, and touch targets pass."),
        item("performance", "Reliability", "Large library performance", "Browse, search, and document history stay responsive."),
        item("privacy", "Security", "Private content", "Documents, photos, notes, credentials, and QA evidence remain private."),
        item("ticket", "QA", "Ticket lifecycle", "File, screenshot, edit, sync, fixed, verify, and refile preserve history.")
    ]

    static let sesh = [
        item("launch", "App", "Cold launch and resume", "Sesh launches and restores the correct tab and active session."),
        item("onboarding", "Profile", "Onboarding and profile", "Profile, theme, consent, and account state persist correctly."),
        item("log", "Sessions", "Log a sesh", "Strain, method, mood, effects, duration, rating, price, photo, and notes save."),
        item("live", "Sessions", "Live session lifecycle", "Start, update, background, resume, end, and discard are consistent."),
        item("multi", "Sessions", "Multi-strain sessions", "Primary and additional strains remain unique and stats use the documented primary."),
        item("journal", "Journal", "Journal and thoughts", "Entries sort, filter, edit, delete, search, and retain photos."),
        item("strains", "Strains", "Strain library", "Search, aliases, type, effects, potency, family tree, and similar strains work."),
        item("custom", "Strains", "Custom strains", "Create, edit, photo, match, merge, and delete do not corrupt history."),
        item("favorites", "Strains", "Favorites and wishlist", "Favorite and wishlist states remain distinct and persistent."),
        item("insights", "Insights", "Personal strain insights", "Counts, averages, effects, recommendations, and recency use valid sessions."),
        item("stats", "Insights", "Stats and trends", "Week, streak, spend, rating, tolerance, and recap calculations are correct."),
        item("stash", "Stash", "Stash inventory", "Purchases, quantities, costs, consumption, goals, and forecast reconcile."),
        item("goals", "Stash", "Goals and tolerance", "Targets, progress, reminders, breaks, and edits remain consistent."),
        item("music", "Music", "Music and playlists", "Search, memory, playlist, Apple Music export, and strain association work."),
        item("community", "Community", "Lounge feed", "Posts, replies, reactions, reporting, pagination, and offline errors work."),
        item("cyph", "Community", "Cyphs and live chat", "Create, join, invite, message, presence, and exit work without duplicate rooms."),
        item("friends", "Community", "Friends and privacy", "Requests, block, visibility, identity, and private content rules work."),
        item("notifications", "System", "Notifications", "Permission, scheduling, deep links, deduplication, and cancellation work."),
        item("widget", "System", "Widget and Live Activity", "Streak, last strain, stash, and live state stay current."),
        item("icloud", "Sync", "iCloud backup and restore", "Sessions, thoughts, profile, and settings merge without loss or duplication."),
        item("worker", "Sync", "Unified Worker", "Authentication, outbox, retries, conflicts, and server errors are visible."),
        item("offline", "Reliability", "Offline and recovery", "Queued social operations retry once and local tracking remains usable."),
        item("accessibility", "UI", "Accessibility", "VoiceOver, Dynamic Type, contrast, reduced motion, and touch targets pass."),
        item("privacy", "Security", "Sensitive health and social data", "Exports, logs, tickets, photos, and credentials avoid unintended disclosure."),
        item("ticket", "QA", "Ticket lifecycle", "File, screenshot, edit, sync, fixed, verify, and refile preserve history.")
    ]
}

@MainActor
final class UnifiedQADeepStore: ObservableObject {
    @Published var states: [String: UnifiedQACheckState] = [:]
    @Published var processes: [UnifiedQAProcess] = []
    @Published var runs: [UnifiedQARun] = []
    @Published var findings: [UnifiedQAFinding] = []
    @Published var hudVisible = false

    private var app = ""
    private var timer: Timer?

    func configure(app: String) {
        guard self.app != app else { return }
        self.app = app
        load()
        startBackgroundChecks()
    }

    func state(for check: UnifiedQACheck) -> UnifiedQACheckState { states[check.id] ?? .init() }

    func set(_ check: UnifiedQACheck, verdict: UnifiedQAVerdict, note: String = "") {
        states[check.id] = .init(verdict: verdict, note: note, updatedAt: Date())
        persist()
    }

    func startRun() {
        runs.insert(.init(), at: 0)
        if runs.count > 50 { runs.removeLast(runs.count - 50) }
        persist()
    }

    func finishRun() {
        guard let index = runs.firstIndex(where: { $0.endedAt == nil }) else { return }
        let values = states.values
        runs[index].endedAt = Date()
        runs[index].passed = values.filter { $0.verdict == .pass }.count
        runs[index].failed = values.filter { $0.verdict == .fail }.count
        runs[index].blocked = values.filter { $0.verdict == .blocked }.count
        persist()
    }

    func startProcess(_ name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        processes.insert(.init(name: name), at: 0)
        trimAndPersist()
    }

    func finishProcess(_ id: UUID, failed: Bool) {
        guard let index = processes.firstIndex(where: { $0.id == id }) else { return }
        processes[index].endedAt = Date()
        processes[index].status = failed ? "failed" : "passed"
        trimAndPersist()
    }

    func runAutomaticChecks(ticketCount: Int, unsyncedCount: Int, memoryMB: Int, hitchMS: Int) {
        var next: [UnifiedQAFinding] = []
        if unsyncedCount > 0 { next.append(.init(severity: "major", area: "Sync", detail: "\(unsyncedCount) ticket(s) are waiting to sync.")) }
        if memoryMB >= 750 { next.append(.init(severity: "major", area: "Memory", detail: "Resident memory is \(memoryMB) MB.")) }
        if hitchMS >= 1_500 { next.append(.init(severity: "blocker", area: "Performance", detail: "Main thread stalled for \(hitchMS) ms.")) }
        if processes.contains(where: { $0.status == "running" && Date().timeIntervalSince($0.startedAt) > 120 }) {
            next.append(.init(severity: "major", area: "Process", detail: "A tracked process has remained unresolved for over two minutes."))
        }
        let failedChecks = states.values.filter { $0.verdict == .fail }.count
        if failedChecks > 0 { next.append(.init(severity: "major", area: "Checklist", detail: "\(failedChecks) app-specific check(s) are failing.")) }
        findings = next
        persist()
    }

    func resetChecklist() { states = [:]; persist() }

    private func startBackgroundChecks() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.runAutomaticChecks(ticketCount: 0, unsyncedCount: 0, memoryMB: 0, hitchMS: 0)
            }
        }
    }

    private var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UnifiedQADeep-\(app).json")
    }

    private struct Snapshot: Codable {
        var states: [String: UnifiedQACheckState]
        var processes: [UnifiedQAProcess]
        var runs: [UnifiedQARun]
        var findings: [UnifiedQAFinding]
    }

    private func load() {
        guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        states = value.states; processes = value.processes; runs = value.runs; findings = value.findings
    }

    private func trimAndPersist() {
        if processes.count > 100 { processes.removeLast(processes.count - 100) }
        persist()
    }

    private func persist() {
        let value = Snapshot(states: states, processes: processes, runs: runs, findings: findings)
        if let data = try? JSONEncoder().encode(value) { try? data.write(to: url, options: .atomic) }
    }
}

struct UnifiedQADeepView: View {
    let app: String
    let tickets: [UnifiedQATicket]
    let unsyncedCount: Int
    let memoryMB: Int
    let hitchMS: Int

    @StateObject private var store = UnifiedQADeepStore()
    @State private var search = ""
    @State private var processName = ""

    private var profile: UnifiedQAProfile { .forApp(app) }
    private var filteredChecks: [UnifiedQACheck] {
        guard !search.isEmpty else { return profile.checks }
        return profile.checks.filter { ($0.area + " " + $0.title + " " + $0.expected).localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            Section("Autonomous findings") {
                if store.findings.isEmpty { Label("No current automatic findings", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                ForEach(store.findings) { finding in
                    VStack(alignment: .leading) {
                        Text(finding.area + " · " + finding.severity.capitalized).font(.caption.bold()).foregroundStyle(finding.severity == "blocker" ? .red : .orange)
                        Text(finding.detail)
                    }
                }
                Button("Run all automatic checks") { store.runAutomaticChecks(ticketCount: tickets.count, unsyncedCount: unsyncedCount, memoryMB: memoryMB, hitchMS: hitchMS) }
            }

            Section("App-specific checklist") {
                TextField("Search checks and evidence", text: $search)
                ForEach(Dictionary(grouping: filteredChecks, by: \.area).keys.sorted(), id: \.self) { area in
                    DisclosureGroup(area) {
                        ForEach(filteredChecks.filter { $0.area == area }) { check in
                            NavigationLink { checkDetail(check) } label: {
                                Label(check.title, systemImage: store.state(for: check).verdict.symbol)
                                    .foregroundStyle(store.state(for: check).verdict.color)
                            }
                        }
                    }
                }
                Button("Reset checklist", role: .destructive) { store.resetChecklist() }
            }

            Section("Tracked processes") {
                HStack { TextField("Process or action", text: $processName); Button("Start") { store.startProcess(processName); processName = "" } }
                ForEach(store.processes.prefix(20)) { process in
                    VStack(alignment: .leading) {
                        HStack { Text(process.name); Spacer(); Text(process.status.capitalized).font(.caption) }
                        if process.status == "running" {
                            HStack { Button("Pass") { store.finishProcess(process.id, failed: false) }; Button("Fail", role: .destructive) { store.finishProcess(process.id, failed: true) } }
                        }
                    }
                }
            }

            Section("QA runs") {
                HStack { Button("Start run") { store.startRun() }; Button("Finish active run") { store.finishRun() } }
                ForEach(store.runs.prefix(12)) { run in
                    Text("\(run.startedAt.formatted()) · \(run.endedAt == nil ? "running" : "\(run.passed) pass, \(run.failed) fail, \(run.blocked) blocked")").font(.caption)
                }
            }

            Section("Duplicate and recurring tickets") {
                let groups = recurring
                if groups.isEmpty { Text("No likely recurring ticket titles.").foregroundStyle(.secondary) }
                ForEach(groups, id: \.key) { group in Text("\(group.value.count)× \(group.value.first?.title ?? group.key)") }
            }

            Section("Full environment") {
                LabeledContent("App", value: app)
                LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")
                LabeledContent("OS", value: UIDevice.current.systemVersion)
                LabeledContent("Device", value: UIDevice.current.model)
                LabeledContent("Memory", value: "\(memoryMB) MB")
                LabeledContent("Longest hang", value: "\(hitchMS) ms")
                LabeledContent("Pending ticket sync", value: "\(unsyncedCount)")
                LabeledContent("Low Power Mode", value: ProcessInfo.processInfo.isLowPowerModeEnabled ? "On" : "Off")
                LabeledContent("Thermal", value: String(describing: ProcessInfo.processInfo.thermalState))
                Button("Copy diagnostics") { UIPasteboard.general.string = diagnosticsText }
            }
        }
        .navigationTitle("\(app) QA Lab")
        .onAppear {
            store.configure(app: app)
            store.runAutomaticChecks(ticketCount: tickets.count, unsyncedCount: unsyncedCount, memoryMB: memoryMB, hitchMS: hitchMS)
        }
    }

    @ViewBuilder private func checkDetail(_ check: UnifiedQACheck) -> some View {
        Form {
            Section(check.title) { Text(check.expected) }
            Section("Verdict") {
                ForEach(UnifiedQAVerdict.allCases, id: \.self) { verdict in
                    Button { store.set(check, verdict: verdict) } label: {
                        Label(verdict.rawValue.capitalized, systemImage: verdict.symbol).foregroundStyle(verdict.color)
                    }
                }
            }
            if !store.state(for: check).note.isEmpty { Section("Evidence note") { Text(store.state(for: check).note) } }
        }.navigationTitle(check.area)
    }

    private var recurring: [(key: String, value: [UnifiedQATicket])] {
        let groups = Dictionary(grouping: tickets) { ticket in
            ticket.title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).prefix(5).joined(separator: " ")
        }
        return groups.filter { $0.value.count > 1 }.sorted { $0.value.count > $1.value.count }
    }

    private var diagnosticsText: String {
        """
        \(app) QA diagnostics
        Build: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")
        OS: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        Device: \(UIDevice.current.model)
        Memory: \(memoryMB) MB
        Longest hang: \(hitchMS) ms
        Tickets: \(tickets.count), pending sync: \(unsyncedCount)
        Checks: \(profile.checks.count)
        """
    }
}
