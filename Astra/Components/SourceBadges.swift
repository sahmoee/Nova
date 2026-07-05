//
//  SourceBadges.swift
//  Astra
//
//  Small colored chips that summarize a stream's health and quality at a glance:
//  Cached, Fast, 4K, HDR, Dolby Vision, Dolby Atmos, Low Seed Risk, Local SMB, Cloud.
//  Rendered in a wrapping flow so a long set wraps cleanly on narrow screens.
//

import SwiftUI

struct BadgeChip: View {
    let badge: SourceBadge

    private var color: Color {
        switch badge.tone {
        case .good:    return Theme.Colors.success
        case .info:    return Theme.Colors.accentSecondary
        case .warn:    return Theme.Colors.warning
        case .premium: return Theme.Colors.accent
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: badge.systemImage)
            Text(badge.label)
        }
        .font(.appFont(13, weight: .semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(color)
        .background(color.opacity(0.16), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1))
    }
}

/// Lays out badges left-to-right, wrapping to the next line when they run out of
/// horizontal room. Uses SwiftUI's native Layout so it adapts to any width.
struct FlowBadges: View {
    let badges: [SourceBadge]
    var spacing: CGFloat = 6

    var body: some View {
        FlowLayout(spacing: spacing) {
            ForEach(badges) { BadgeChip(badge: $0) }
        }
    }
}

/// A minimal flow layout: places subviews in rows, wrapping as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth - spacing)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth - spacing)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                      proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
