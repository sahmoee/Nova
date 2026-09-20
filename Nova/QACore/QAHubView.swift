// QAHubView.swift
// ─────────────────────────────────────────────────────────────────────────────
// Shared QACore — the full QA hub (formerly QAModeView in Stocked).
//
// No app-specific dependencies. Uses system colors and system fonts throughout.
// Per-app checklist sections are injected via QAHubView.checklistProvider.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

// MARK: - QAHubView

struct QAHubView: View {

    let dismiss: () -> Void

    @State private var tab: QAHubTab = .triage
    @State private var showRunSheet = false
    @State private var showTicketSheet = false
    @State private var newTicketTitle = ""

    var body: some View {
        NavigationStack {
            TabView(selection: $tab) {
                triageTab.tabItem { Label("Triage", systemImage: "waveform.path.ecg") }.tag(QAHubTab.triage)
                ticketsTab.tabItem { Label("Tickets", systemImage: "list.bullet.clipboard") }.tag(QAHubTab.tickets)
                checklistTab.tabItem { Label("Checklist", systemImage: "checklist") }.tag(QAHubTab.checklist)
                runsTab.tabItem { Label("Runs", systemImage: "play.rectangle.on.rectangle") }.tag(QAHubTab.runs)
                exportTab.tabItem { Label("Export", systemImage: "square.and.arrow.up") }.tag(QAHubTab.export)
            }
            .navigationTitle(QA.config.appName + " QA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showTicketSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .onAppear { QATriage.shared.refresh() }
        .sheet(isPresented: $showRunSheet) { QANewRunSheet() }
        .sheet(isPresented: $showTicketSheet) { QANewTicketSheet() }
        .onReceive(NotificationCenter.default.publisher(for: .qaOpenQuickTicket)) { _ in
            showTicketSheet = true
        }
    }

    // MARK: Tabs

    private var triageTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Verdict header
                HStack(spacing: 12) {
                    Image(systemName: QATriage.shared.verdictSymbol)
                        .font(.system(size: 32))
                        .foregroundStyle(QATriage.shared.verdictTint)
                    VStack(alignment: .leading) {
                        Text(QATriage.shared.verdict)
                            .font(.system(size: 22, weight: .bold))
                        Text("\(QATriage.shared.blockers.count) blockers · \(QATriage.shared.warnings.count) warnings")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { QATriage.shared.refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .padding()
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                // Runtime snapshot
                QARuntimeSnapshotView()

                // Findings list
                if QATriage.shared.findings.isEmpty {
                    ContentUnavailableView("No findings", systemImage: "checkmark.circle", description: Text("All checks passing."))
                } else {
                    QAFindingListView(findings: QATriage.shared.findings)
                }
            }
            .padding()
        }
    }

    private var ticketsTab: some View {
        QATicketListView()
    }

    private var checklistTab: some View {
        QAChecklistView()
    }

    private var runsTab: some View {
        QARunsView(showSheet: $showRunSheet)
    }

    private var exportTab: some View {
        QAExportView()
    }
}

// MARK: - Tab enum

private enum QAHubTab: Hashable {
    case triage, tickets, checklist, runs, export
}

// MARK: - QAFindingListView

struct QAFindingListView: View {
    let findings: [QAFinding]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(findings) { f in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: f.symbol)
                        .foregroundStyle(f.level.tint)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.title)
                            .font(.system(size: 14, weight: .medium))
                        if !f.detail.isEmpty {
                            Text(f.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(f.level.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(f.level.tint)
                }
                .padding(.vertical, 8)
                Divider()
            }
        }
        .padding(.horizontal)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - QARuntimeSnapshotView

struct QARuntimeSnapshotView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Runtime", systemImage: "memorychip")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                statPill(String(format: "%.0f MB", QARuntimeMonitor.shared.currentFootprintMB), icon: "memorychip")
                statPill(QARuntimeMonitor.shared.thermalName.capitalized, icon: "thermometer.medium")
                if QARuntimeMonitor.shared.worstHitchMs > 0 {
                    statPill(String(format: "%.0f ms", QARuntimeMonitor.shared.worstHitchMs), icon: "chart.line.downtrend.xyaxis")
                }
                if QARuntimeMonitor.shared.lowPower {
                    statPill("Low Power", icon: "battery.25")
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func statPill(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(uiColor: .tertiarySystemBackground), in: Capsule())
    }
}

// MARK: - QATicketListView

struct QATicketListView: View {
    @State private var filter: QATicketStatus? = nil

    var tickets: [QATicket] {
        let all = QATicketStore.shared.tickets
        guard let f = filter else { return all }
        return all.filter { $0.status == f }
    }

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $filter) {
                    Text("All").tag(Optional<QATicketStatus>.none)
                    ForEach(QATicketStatus.allCases) { s in
                        Text(s.title).tag(Optional(s))
                    }
                }
                .pickerStyle(.segmented)
            }

            ForEach(tickets) { ticket in
                NavigationLink {
                    QATicketDetailView(ticket: ticket)
                } label: {
                    QATicketRowView(ticket: ticket)
                }
            }
            .onDelete { idx in
                let ids = idx.map { tickets[$0].id }
                ids.forEach { QATicketStore.shared.delete($0) }
            }
        }
    }
}

// MARK: - QATicketRowView

struct QATicketRowView: View {
    let ticket: QATicket

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: ticket.severity.symbol)
                    .foregroundStyle(severityColor)
                Text(ticket.number)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: ticket.status.symbol)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
            }
            Text(ticket.title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2)
            Text(ticket.context.screen)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var severityColor: Color {
        switch ticket.severity {
        case .blocker: return .red
        case .major:   return .orange
        case .minor:   return .yellow
        case .note:    return .secondary
        }
    }
}

// MARK: - QATicketDetailView

struct QATicketDetailView: View {
    let ticket: QATicket
    @State private var showEdit = false

    var body: some View {
        ScrollView {
            Text(ticket.exportText)
                .font(.system(size: 13, design: .monospaced))
                .padding()
        }
        .navigationTitle(ticket.number)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            QATicketEditSheet(ticket: ticket)
        }
    }
}

// MARK: - QATicketEditSheet

struct QATicketEditSheet: View {
    let ticket: QATicket
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var body_: String
    @State private var severity: QATicketSeverity
    @State private var status: QATicketStatus
    @State private var resolution: String

    init(ticket: QATicket) {
        self.ticket = ticket
        _title = State(initialValue: ticket.title)
        _body_ = State(initialValue: ticket.body)
        _severity = State(initialValue: ticket.severity)
        _status = State(initialValue: ticket.status)
        _resolution = State(initialValue: ticket.resolution ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                }
                Section("Body") {
                    TextEditor(text: $body_)
                        .frame(minHeight: 100)
                }
                Section("Severity") {
                    Picker("Severity", selection: $severity) {
                        ForEach(QATicketSeverity.allCases) { s in
                            Text(s.title).tag(s)
                        }
                    }
                }
                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach(QATicketStatus.allCases) { s in
                            Text(s.title).tag(s)
                        }
                    }
                }
                Section("Resolution") {
                    TextField("Resolution note", text: $resolution)
                }
            }
            .navigationTitle("Edit Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        QATicketStore.shared.update(
                            ticket.id,
                            title: title,
                            body: body_,
                            severity: severity,
                            status: status,
                            resolution: resolution.isEmpty ? nil : resolution
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - QANewTicketSheet

struct QANewTicketSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var body_ = ""
    @State private var severity: QATicketSeverity = .major

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Brief description", text: $title)
                }
                Section("Body") {
                    TextEditor(text: $body_)
                        .frame(minHeight: 80)
                }
                Section("Severity") {
                    Picker("Severity", selection: $severity) {
                        ForEach(QATicketSeverity.allCases) { s in
                            Text(s.title).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("New Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("File") {
                        guard !title.isEmpty else { return }
                        _ = QATicketStore.shared.open(
                            title: title,
                            body: body_,
                            severity: severity,
                            requiresManualReview: false,
                            context: QAContextCapture.current(),
                            origin: .tester,
                            automaticCheckID: nil,
                            screenshot: nil
                        )
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}

// MARK: - QAChecklistView

struct QAChecklistView: View {
    /// Injected per-app. Call QAHubView.checklistProvider = { MyApp.qaChecklist } at startup.
    nonisolated(unsafe) static var checklistProvider: (() -> [QAChecklistSection])?

    @State private var states: [String: QACheckItemState] = [:]
    private static let statesKey = "qa.checklist.states.v1"

    private var sections: [QAChecklistSection] { Self.checklistProvider?() ?? [] }

    var body: some View {
        List {
            ForEach(sections) { section in
                Section(header: Text(section.title)) {
                    if !section.note.isEmpty {
                        Text(section.note)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(section.items) { item in
                        checkRow(item)
                    }
                }
            }
        }
        .onAppear(perform: loadStates)
    }

    private func checkRow(_ item: QACheckItem) -> some View {
        let state = states[item.ticket] ?? QACheckItemState()
        return HStack(spacing: 12) {
            Button {
                var s = states[item.ticket] ?? QACheckItemState()
                s.verdict = s.verdict.next
                if s.definition == nil { s.definition = item.text }
                states[item.ticket] = s
                saveStates()
            } label: {
                Image(systemName: state.verdict.symbol)
                    .foregroundStyle(state.verdict.color)
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(.system(size: 14))
                if item.blocker {
                    Text("Blocker")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func loadStates() {
        guard let data = UserDefaults.standard.data(forKey: Self.statesKey),
              let decoded = try? JSONDecoder().decode([String: QACheckItemState].self, from: data)
        else { return }
        states = decoded
    }

    private func saveStates() {
        guard let data = try? JSONEncoder().encode(states) else { return }
        UserDefaults.standard.set(data, forKey: Self.statesKey)
    }
}

// MARK: - QARunsView

struct QARunsView: View {
    @Binding var showSheet: Bool
    @State private var runs: [QARun] = []

    var body: some View {
        List {
            Section {
                Button { showSheet = true } label: {
                    Label("Start New Run", systemImage: "play.fill")
                }
                if QARunLog.activeRun != nil {
                    Button(role: .destructive) { QARunLog.end(); reload() } label: {
                        Label("End Active Run", systemImage: "stop.fill")
                    }
                }
            }

            ForEach(runs) { run in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(run.name)
                            .font(.system(size: 14, weight: .medium))
                        if run.isActive {
                            Text("Active")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.green, in: Capsule())
                        }
                    }
                    Text("\(run.buildVersion) (\(run.buildNumber)) · \(run.startedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if !run.isActive {
                        Text("Duration: \(run.duration)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { idx in
                idx.map { runs[$0].id }.forEach { QARunLog.delete(id: $0) }
                reload()
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() { runs = QARunLog.load() }
}

// MARK: - QANewRunSheet

struct QANewRunSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Run Name") {
                    TextField("e.g. Sprint 42 regression", text: $name)
                }
            }
            .navigationTitle("New Test Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        guard !name.isEmpty else { return }
                        QARunLog.start(name: name)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

// MARK: - QAExportView

struct QAExportView: View {
    @State private var text = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Triage export
                exportBlock(title: "Triage", content: QATriage.shared.exportText)
                // Tickets export
                exportBlock(title: "Tickets", content: QATicketStore.shared.exportText)
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: fullExport)
            }
        }
        .onAppear { QATriage.shared.refresh() }
    }

    private var fullExport: String {
        [QATriage.shared.exportText, "", QATicketStore.shared.exportText]
            .joined(separator: "\n")
    }

    private func exportBlock(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(content)
                .font(.system(size: 12, design: .monospaced))
                .padding(10)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - QATextReportView

/// A plain full-text report — used in share sheet and iCloud mirror.
public struct QATextReportView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            Text(QATicketStore.shared.exportText)
                .font(.system(size: 12, design: .monospaced))
                .padding()
        }
    }
}
