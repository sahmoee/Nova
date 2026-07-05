//
//  SkeletonGrid.swift
//  FrameTV
//
//  A shimmering placeholder grid shown while real poster content loads, so screens
//  fade from a structured skeleton into content instead of a blank spinner.
//

import SwiftUI

struct SkeletonGrid: View {
    var count: Int = 12
    var columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.lg), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.Colors.card)
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                        .shimmering()
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.Colors.card)
                        .frame(height: 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, Theme.Spacing.xl)
                        .shimmering()
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.edge)
        .accessibilityHidden(true)
    }
}

struct SkeletonRow: View {
    var count: Int = 6

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Theme.Spacing.md) {
                ForEach(0..<count, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.Colors.card)
                        .frame(width: Theme.CardSize.posterWidth,
                               height: Theme.CardSize.posterHeight)
                        .shimmering()
                }
            }
            .padding(.horizontal, Theme.Spacing.edge)
        }
        .accessibilityHidden(true)
    }
}
