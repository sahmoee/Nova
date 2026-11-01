//
//  StreamRulesView.swift
//  Nova
//
//  Settings › Streaming › Stream Rules. Users add text or regex rules that tag,
//  prefer, avoid, hide, or mark streams for auto-play. A live test field shows
//  which rules match a sample title before saving. iPhone, iPad and Mac can import
//  a pasted rules file (previewed first) and share an export; Apple TV edits rules
//  directly because tvOS has no pasteboard.
//

import SwiftUI

extension StreamRule.TagColor {
    var color: Color {
        switch self {
        case .violet: return Color(red: 0.62, green: 0.56, blue: 1.0)
        case .blue:   return Color(red: 0.36, green: 0.62, blue: 1.0)
        case .teal:   return Color(red: 0.25, green: 0.78, blue: 0.80)
        case .green:  return Color(red: 0.36, green: 0.80, blue: 0.45)
        case .yellow: return Color(red: 0.98, green: 0.82, blue: 0.30)
        case .orange: return Color(red: 1.0, green: 0.60, blue: 0.25)
        case .red:    return Color(red: 1.0, green: 0.40, blue: 0.40)
        case .gray:   return Color(white: 0.62)
        }
    }

    var title: String { rawValue.capitalized }
}

/// Colored tag shown on stream rows for each matching rule.
struct StreamRuleTagChip: View {
    let rule: StreamRule

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(rule.color.color).frame(width: 8, height: 8)
            Text(rule.name.isEmpty ? rule.pattern : rule.name)
                .lineLimit(1)
        }
        .font(.appFont(13, weight: .bold))
        .foregroundStyle(rule.color.color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(rule.color.color.opacity(0.16), in: Capsule())
        .accessibilityLabel("Rule: \(rule.name.isEmpty ? rule.pattern : rule.name)")
    }
}

/// Details shown on each stream row, in the user's order (Omni's stream button
/// elements). Stored as a comma-separated list of the enabled details.
enum StreamRowDetail: String, CaseIterable, Identifiable {
    case addon, size, seeders, codec, audio, language
    var id: String { rawValue }
    var title: String {
        switch self {
        case .addon: return "Addon"
        case .size: return "File Size"
        case .seeders: return "Seeders"
        case .codec: return "Video Codec"
        case .audio: return "Audio Channels"
        case .language: return "Language"
        }
    }

    static let storageKey = "omni.streamRowDetails"
    static let defaultValue = allCases.map(\.rawValue).joined(separator: ",")

    static func decode(_ raw: String) -> [StreamRowDetail] {
        var seen = Set<StreamRowDetail>()
        return raw.split(separator: ",").compactMap { StreamRowDetail(rawValue: String($0)) }
            .filter { seen.insert($0).inserted }
    }

    static func encode(_ details: [StreamRowDetail]) -> String {
        details.map(\.rawValue).joined(separator: ",")
    }
}

struct StreamRulesView: View {
    @ObservedObject private var store = StreamRuleStore.shared
    @AppStorage(StreamRowDetail.storageKey) private var rowDetailsRaw = StreamRowDetail.defaultValue
    @State private var editing: StreamRule?
    #if os(iOS)
    @State private var importText = ""
    @State private var showImport = false
    @State private var importPreview: [StreamRule] = []
    @State private var importError: String?
    #endif

    var body: some View {
        List {
            Section {
                if store.rules.isEmpty {
                    Text("No rules yet. Add one to tag streams like \u{201C}REMUX\u{201D} or hide ones like \u{201C}CAM\u{201D}.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.rules) { rule in
                    Button { editing = rule } label: { row(rule) }
                        .contextMenu {
                            Button { store.move(id: rule.id, offset: -1) } label: { Label("Move Up", systemImage: "arrow.up") }
                            Button { store.move(id: rule.id, offset: 1) } label: { Label("Move Down", systemImage: "arrow.down") }
                            Button(role: .destructive) { store.delete(rule.id) } label: { Label("Delete", systemImage: "trash") }
                        }
                }
                #if os(iOS)
                .onDelete { offsets in
                    offsets.map { store.rules[$0].id }.forEach(store.delete)
                }
                .onMove { store.rules.move(fromOffsets: $0, toOffset: $1) }
                #endif
            } footer: {
                Text("Rules run in order. Prefer and Avoid shift ranking; Hide removes a stream from the list unless nothing else is left. Auto-Play rules decide what Auto-Select picks first.")
            }

            rowDetailsSection

            Section {
                Button {
                    editing = StreamRule(name: "", pattern: "")
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .disabled(store.rules.count >= StreamRule.maxRules)
                #if os(iOS)
                Button { showImport = true } label: { Label("Import Rules", systemImage: "square.and.arrow.down") }
                if !store.rules.isEmpty {
                    ShareLink(item: store.exportJSON(), preview: SharePreview("Nova Stream Rules")) {
                        Label("Export Rules", systemImage: "square.and.arrow.up")
                    }
                }
                #endif
            }
        }
        .navigationTitle("Stream Rules")
        .sheet(item: $editing) { rule in
            NavigationStack {
                StreamRuleEditor(rule: rule) { saved in
                    store.upsert(saved)
                    editing = nil
                } onDelete: {
                    store.delete(rule.id)
                    editing = nil
                } onCancel: {
                    editing = nil
                }
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showImport) { importSheet }
        #endif
    }

    private var rowDetails: [StreamRowDetail] { StreamRowDetail.decode(rowDetailsRaw) }

    /// Enabled details first in their order, then the hidden ones.
    private var rowDetailsSection: some View {
        Section {
            ForEach(rowDetails + StreamRowDetail.allCases.filter { !rowDetails.contains($0) }) { detail in
                let enabled = rowDetails.contains(detail)
                HStack {
                    Toggle(detail.title, isOn: Binding(
                        get: { enabled },
                        set: { on in
                            var list = rowDetails
                            if on { list.append(detail) } else { list.removeAll { $0 == detail } }
                            rowDetailsRaw = StreamRowDetail.encode(list)
                        }
                    ))
                    if enabled {
                        Button { moveDetail(detail, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(rowDetails.first == detail)
                            .accessibilityLabel("Move \(detail.title) earlier")
                        Button { moveDetail(detail, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(rowDetails.last == detail)
                            .accessibilityLabel("Move \(detail.title) later")
                    }
                }
                .buttonStyle(.borderless)
            }
        } header: {
            Text("Row Details")
        } footer: {
            Text("Choose which details each stream row shows, and their order.")
        }
    }

    private func moveDetail(_ detail: StreamRowDetail, by offset: Int) {
        var list = rowDetails
        guard let index = list.firstIndex(of: detail), list.indices.contains(index + offset) else { return }
        list.swapAt(index, index + offset)
        rowDetailsRaw = StreamRowDetail.encode(list)
    }

    private func row(_ rule: StreamRule) -> some View {
        HStack(spacing: 12) {
            Circle().fill(rule.color.color).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name.isEmpty ? rule.pattern : rule.name)
                    .font(.appFont(17, weight: .semibold))
                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                Text([rule.effect.title, rule.isRegex ? "Regex" : "Text", rule.autoPlay ? "Auto-Play" : nil]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.appFont(13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !rule.isEnabled {
                Text("Off").font(.appFont(13, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    #if os(iOS)
    private var importSheet: some View {
        NavigationStack {
            Form {
                Section("Paste a rules file") {
                    TextEditor(text: $importText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 160)
                        .onChange(of: importText) { _, text in
                            do {
                                importPreview = try StreamRuleStore.parseImport(text)
                                importError = nil
                            } catch {
                                importPreview = []
                                importError = text.isEmpty ? nil : error.localizedDescription
                            }
                        }
                }
                if let importError {
                    Section { Text(importError).foregroundStyle(.red) }
                }
                if !importPreview.isEmpty {
                    Section("\(importPreview.count) rules found") {
                        ForEach(importPreview) { row($0) }
                    }
                }
            }
            .navigationTitle("Import Rules")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showImport = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Rules") {
                        importPreview.forEach(store.upsert)
                        ToastCenter.shared.show("Imported \(importPreview.count) rules")
                        importText = ""
                        showImport = false
                    }
                    .disabled(importPreview.isEmpty)
                }
            }
        }
    }
    #endif
}

private struct StreamRuleEditor: View {
    @State var rule: StreamRule
    var onSave: (StreamRule) -> Void
    var onDelete: () -> Void
    var onCancel: () -> Void

    @ObservedObject private var store = StreamRuleStore.shared
    @State private var sample = "Movie.2024.2160p.UHD.BluRay.REMUX.DV.TrueHD.Atmos.7.1"

    private var error: String? { StreamRuleEngine.validationError(for: rule) }
    private var isExisting: Bool { store.rules.contains { $0.id == rule.id } }
    private var sampleMatches: Bool {
        var probe = rule
        probe.isEnabled = true
        return !StreamRuleEngine(rules: [probe]).matches(text: sample).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Name (shown on the tag)", text: $rule.name)
                TextField(rule.isRegex ? "Regular expression" : "Text to match", text: $rule.pattern)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                Toggle("Regular Expression", isOn: $rule.isRegex)
                if let error, !rule.pattern.isEmpty {
                    Text(error).foregroundStyle(.red)
                }
            } footer: {
                Text("Matches the stream name, title, filename and addon, ignoring case.")
            }

            Section("Effect") {
                Picker("Effect", selection: $rule.effect) {
                    ForEach(StreamRule.Effect.allCases) { Text($0.title).tag($0) }
                }
                Picker("Tag Color", selection: $rule.color) {
                    ForEach(StreamRule.TagColor.allCases) { color in
                        Text(color.title).tag(color)
                    }
                }
                Toggle("Use for Auto-Play", isOn: $rule.autoPlay)
                    .disabled(rule.effect == .hide || rule.effect == .avoid)
                Toggle("Enabled", isOn: $rule.isEnabled)
            }

            Section("Test") {
                TextField("Sample stream title", text: $sample)
                Label(sampleMatches ? "Matches this title" : "Doesn't match this title",
                      systemImage: sampleMatches ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(sampleMatches ? rule.color.color : .secondary)
            }

            if isExisting {
                Section {
                    Button("Delete Rule", role: .destructive, action: onDelete)
                }
            }
        }
        .navigationTitle(isExisting ? "Edit Rule" : "New Rule")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var saved = rule
                    saved.name = String(saved.name.trimmingCharacters(in: .whitespaces).prefix(60))
                    if saved.effect == .hide || saved.effect == .avoid { saved.autoPlay = false }
                    onSave(saved)
                }
                .disabled(error != nil)
            }
        }
    }
}
