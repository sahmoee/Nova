//
//  AddonManagementComponents.swift
//  Nova
//
//  Focused management components extracted from AddonsView.
//

import SwiftUI

struct AddonMetadataEditor: View {
    let addon: InstalledAddon
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var category: String
    @State private var tagsText: String

    init(addon: InstalledAddon) {
        self.addon = addon
        _category = State(initialValue: addon.category ?? "")
        _tagsText = State(initialValue: addon.tags.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Organization") {
                    TextField("Category", text: $category)
                    TextField("Tags, separated by commas", text: $tagsText)
                }
                Section {
                    Text("Categories group add-ons. Tags are searchable and can describe providers, regions, or content types.")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .navigationTitle(addon.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        env.addonStore.setCategory(category, for: addon)
                        let tags = tagsText.split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        env.addonStore.setTags(Array(Set(tags)).sorted(), for: addon)
                        dismiss()
                    }
                }
            }
        }
    }
}
