//
//  DuplicatesView.swift
//  Astra
//
//  Reviews likely-duplicate library items (the same title saved from different
//  sources) and lets the user merge them. Merging keeps the most complete record,
//  unions favorite status and the furthest watch progress, and repoints collections.
//

import SwiftUI

struct DuplicatesView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var groups: [LibraryStore.DuplicateGroup] = []
    @State private var didScan = false

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Duplicate Cleanup")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(.horizontal, Theme.Spacing.edge)
                        .padding(.top, Theme.Spacing.lg)

                    if groups.isEmpty {
                        emptyState
                    } else {
                        Text("These titles appear more than once from different sources. Merging keeps your progress and favorites under a single entry.")
                            .font(.appFont(18))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(.horizontal, Theme.Spacing.edge)

                        FocusableButton(title: "Merge All", systemImage: "arrow.triangle.merge", prominent: true) {
                            withAnimation { library.mergeAllDuplicates(); rescan() }
                        }
                        .frame(maxWidth: 320)
                        .padding(.horizontal, Theme.Spacing.edge)

                        ForEach(groups) { group in
                            groupCard(group)
                        }
                    }
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .navigationTitle("Duplicates")
        .onAppear { rescan() }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: didScan ? "checkmark.circle" : "magnifyingglass")
                .font(.appFont(56))
                .foregroundStyle(didScan ? Theme.Colors.success : Theme.Colors.textTertiary)
            Text(didScan ? "No duplicates found" : "Scanning…")
                .font(.appFont(24, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            if didScan {
                Text("Your library looks clean.")
                    .font(.appFont(18))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xl)
    }

    private func groupCard(_ group: LibraryStore.DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(group.title)
                    .font(.appFont(22, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text("\(group.items.count) copies")
                    .font(.appFont(15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            ForEach(group.items) { item in
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: item.sourceType.systemImage)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.sourceType.displayName)
                            .font(.appFont(16))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        if item.progressFraction > 0 {
                            Text("\(Int(item.progressFraction * 100))% watched")
                                .font(.appFont(13))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                    Spacer()
                    if item.isFavorite {
                        Image(systemName: "star.fill").foregroundStyle(Theme.Colors.warning)
                    }
                }
            }
            FocusableButton(title: "Merge These", systemImage: "arrow.triangle.merge") {
                withAnimation { library.mergeDuplicates(group); rescan() }
            }
            .frame(maxWidth: 280)
            .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.md)
        .refinedCardBackground()
        .padding(.horizontal, Theme.Spacing.edge)
    }

    private func rescan() {
        groups = library.duplicateGroups()
        didScan = true
    }
}
