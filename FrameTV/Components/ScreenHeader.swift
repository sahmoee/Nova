//
//  ScreenHeader.swift
//  FrameTV
//
//  Responsive screen title + optional trailing action. On tvOS the title and
//  action sit side by side at full scale. On iPhone the title shrinks to fit a
//  single line and, when an action is present, the action drops below the title
//  so neither gets squeezed into an unreadable sliver.
//

import SwiftUI

/// A large screen title that never wraps to one-character-per-line. It caps to a
/// single line and scales down to fit the available width.
struct ScreenTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Font.screenTitle())
            .foregroundStyle(Theme.Colors.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A header with a title and an optional trailing action button. Lays out
/// horizontally on tvOS / regular width and vertically on compact (iPhone) width.
struct ScreenHeader<Action: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var action: () -> Action

    var body: some View {
        if Theme.isCompact {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                titleBlock
                action()
            }
        } else {
            HStack(alignment: .center) {
                titleBlock
                Spacer()
                action()
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ScreenTitle(text: title)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Font.cardSubtitle())
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }
}

extension ScreenHeader where Action == EmptyView {
    /// Convenience for a title-only header.
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.action = { EmptyView() }
    }
}
