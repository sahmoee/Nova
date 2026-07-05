//
//  MediaRow.swift
//  Astra
//
//  A titled horizontal row of MediaCards, the building block of the Home screen.
//

import SwiftUI

struct MediaRow: View {
    let title: String
    let items: [MediaItem]
    var wide: Bool = false
    let onSelect: (MediaItem) -> Void

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(title)
                    .font(Theme.Font.sectionTitle())
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.leading, Theme.Spacing.edge)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Theme.Spacing.md) {
                        ForEach(items) { item in
                            MediaCard(item: item, wide: wide) {
                                onSelect(item)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.edge)
                    .padding(.vertical, Theme.Spacing.md) // room for focus scale
                }
            }
        }
    }
}
