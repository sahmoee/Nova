//
//  ScreenHeader.swift
//  Nova
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

/// Compact, artwork-first title treatment shared by Nova's primary destinations.
struct CinematicPageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.appFont(19, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    Text(title)
                        .font(.appFont(Theme.isCompact ? 32 : 48, weight: .semibold, design: .serif))
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.appFont(14))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Theme.Spacing.sm)
            trailing()
        }
    }
}

extension CinematicPageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, systemImage: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.trailing = { EmptyView() }
    }
}

struct CinematicGlassSurface: ViewModifier {
    var radius: CGFloat = Theme.Radius.card
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(Theme.Colors.card.opacity(reduceTransparency ? 1 : 0.96),
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(contrast == .increased ? 0.55 : 0.14), lineWidth: contrast == .increased ? 1.5 : 0.75)
            }
            .shadow(color: Theme.Shadow.color, radius: 16, y: 6)
    }
}

extension View {
    func cinematicGlass(radius: CGFloat = Theme.Radius.card) -> some View {
        modifier(CinematicGlassSurface(radius: radius))
    }
}
