//
//  CollectionPickerSheet.swift
//  FrameTV
//
//  Collections are no longer a separate destination: this sheet lets the user turn
//  individual collections on or off as Library filter pills, and links to the full
//  manager for creating, renaming, or deleting collections.
//

import SwiftUI

struct CollectionPickerSheet: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if library.collections.isEmpty {
                    Section {
                        Text("No collections yet. Create one below, then flip it on to pin it as a Library tab.")
                            .font(.appFont(15))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                } else {
                    Section("Show as Library tabs") {
                        ForEach(library.collections) { collection in
                            Toggle(isOn: binding(for: collection)) {
                                Label {
                                    HStack {
                                        Text(collection.name)
                                        Spacer()
                                        Text("\(collection.count)")
                                            .foregroundStyle(Theme.Colors.textTertiary)
                                    }
                                } icon: {
                                    Image(systemName: collection.systemImage)
                                }
                            }
                        }
                    }
                }
                Section {
                    NavigationLink {
                        CollectionsView()
                    } label: {
                        Label("Manage Collections", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .navigationTitle("Collections")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func binding(for collection: MediaCollection) -> Binding<Bool> {
        Binding(
            get: { settings.pinnedCollections.contains(collection.id.uuidString) },
            set: { on in
                var pinned = settings.pinnedCollections
                let key = collection.id.uuidString
                if on {
                    if !pinned.contains(key) { pinned.append(key) }
                } else {
                    pinned.removeAll { $0 == key }
                }
                settings.pinnedCollections = pinned
            }
        )
    }
}
