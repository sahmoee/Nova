//
//  TitleCleanupRulesView.swift
//  Astra
//
//  Edit the regular-expression rules that clean up messy filenames into display
//  titles. Each rule shows its plain-language description, can be toggled, edited,
//  reordered, or deleted, and there's a live preview so you can see a rule's effect
//  before saving.
//

import SwiftUI

struct TitleCleanupRulesView: View {
    @ObservedObject private var store = TitleCleanupRulesStore.shared
    @State private var editing: TitleCleanupRule?
    @State private var showingNew = false
    @State private var preview = "The.Matrix.1999.1080p.BluRay.x264-GROUP"

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Live preview")
                        .font(.appFont(13, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    TextField("Sample filename", text: $preview)
                        .font(.appFont(15))
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        #endif
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down")
                            .font(.appFont(12))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Text(store.clean(MetadataParser.cleanTitle(from: preview)))
                            .font(.appFont(16, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
            } footer: {
                Text("Rules run top to bottom after Astra's built-in normalization. Drag to reorder.")
            }

            Section("Rules") {
                ForEach($store.rules) { $rule in
                    Button {
                        editing = rule
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Toggle("", isOn: $rule.isEnabled).labelsHidden()
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.ruleDescription)
                                    .font(.appFont(15, weight: .medium))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text(rule.pattern)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(rule.isValid ? Theme.Colors.textSecondary : Theme.Colors.error)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if !rule.isValid {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.Colors.error)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { store.rules.remove(atOffsets: $0) }
                .onMove { store.move(from: $0, to: $1) }
            }

            Section {
                Button {
                    showingNew = true
                } label: {
                    Label("Add Rule", systemImage: "plus.circle.fill")
                }
                Button(role: .destructive) {
                    store.resetToDefaults()
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Cleanup Rules")
        #if os(iOS)
        .toolbar { EditButton() }
        #endif
        .sheet(item: $editing) { rule in
            RuleEditor(rule: rule) { updated in
                if let idx = store.rules.firstIndex(where: { $0.id == updated.id }) {
                    store.rules[idx] = updated
                }
            }
        }
        .sheet(isPresented: $showingNew) {
            RuleEditor(rule: TitleCleanupRule(ruleDescription: "", pattern: "", replacement: "")) { newRule in
                store.add(newRule)
            }
        }
    }
}

private struct RuleEditor: View {
    @State var rule: TitleCleanupRule
    var onSave: (TitleCleanupRule) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var testInput = "Show.Name.S01E02.720p.WEB-DL"

    var body: some View {
        NavigationStack {
            Form {
                Section("Description") {
                    TextField("What this rule does", text: $rule.ruleDescription, axis: .vertical)
                }
                Section("Pattern") {
                    TextField("Regular expression", text: $rule.pattern)
                        .font(.system(.body, design: .monospaced))
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        #endif
                    TextField("Replacement (optional, supports $1)", text: $rule.replacement)
                        .font(.system(.body, design: .monospaced))
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        #endif
                    Toggle("Ignore case", isOn: $rule.caseInsensitive)
                    if !rule.isValid {
                        Label("This pattern doesn't compile", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Colors.error)
                            .font(.appFont(14))
                    }
                }
                Section("Try it") {
                    TextField("Test input", text: $testInput)
                        .font(.system(.body, design: .monospaced))
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        #endif
                    HStack {
                        Text("Result")
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer()
                        Text(rule.apply(to: testInput))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
            }
            .navigationTitle(rule.ruleDescription.isEmpty ? "New Rule" : "Edit Rule")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(rule); dismiss() }
                        .disabled(rule.pattern.isEmpty || !rule.isValid || rule.ruleDescription.isEmpty)
                }
            }
        }
    }
}
