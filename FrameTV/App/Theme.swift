//
//  Theme.swift
//  FrameTV
//
//  Centralized design tokens: colors, corner radii, spacing, card sizes, and
//  typography. Values are tuned for a dark, cinematic Apple TV look and scale
//  down responsively on iPhone/iPad so the same screens read well on a handheld.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

enum Theme {

    // MARK: - Platform scaling
    //
    // tvOS is a 10-foot interface: large type, generous spacing, big cards.
    // On iOS/iPadOS we render the same layouts at a handheld scale. A single
    // multiplier here drives fonts, spacing, edge padding, and card sizes so the
    // whole UI adapts from one place instead of per-screen tweaks.

    #if os(tvOS)
    /// On tvOS, keep the full living-room scale.
    static let isCompact = false
    static let uiScale: CGFloat = 1.0
    #elseif os(iOS)
    /// On iPad we render a roomier, "regular" layout closer to the tvOS scale so the
    /// large screen isn't wasted on iPhone-sized cards; on iPhone we keep the compact
    /// handheld scale. Determined once at launch from the device idiom.
    static let isPad: Bool = UIDevice.current.userInterfaceIdiom == .pad
    /// iPad is treated as "regular" width (false) so the many `isCompact ? a : b`
    /// branches across the app give iPad the wider treatment automatically.
    static let isCompact: Bool = !isPad
    /// iPhone stays at a tight 0.52; iPad uses a larger 0.72 so posters, type, and
    /// spacing scale up for the bigger canvas without reaching full tvOS size.
    static let uiScale: CGFloat = isPad ? 0.72 : 0.52
    #else
    static let isCompact = true
    static let uiScale: CGFloat = 0.52
    #endif

    /// Scales a tvOS dimension to the current platform, with a floor so values
    /// never collapse to something unreadable.
    static func scaled(_ value: CGFloat, min floor: CGFloat = 0) -> CGFloat {
        Swift.max(value * uiScale, floor)
    }

    /// Scales a font point size, keeping a sensible minimum.
    static func scaledFont(_ size: CGFloat, min floor: CGFloat = 11) -> CGFloat {
        Swift.max(size * uiScale, floor)
    }

    /// A responsive max content width for reading columns / forms. On iPhone there
    /// is no cap (content fills the screen); on iPad/tvOS a generous cap keeps very
    /// wide layouts comfortable without wasting space.
    static func contentMaxWidth(_ tvOSWidth: CGFloat) -> CGFloat {
        isCompact ? .infinity : tvOSWidth
    }

    /// Whether the user has Reduce Motion enabled, so animations can be skipped.
    static var isReduceMotion: Bool {
        #if canImport(UIKit)
        return UIAccessibility.isReduceMotionEnabled
        #else
        return false
        #endif
    }

    // MARK: - Colors

    enum Colors {
        /// Deep, near-black base. Slightly warmer and softer than pure black for a
        /// more refined, less harsh dark look.
        static let background = Color(red: 0.05, green: 0.05, blue: 0.07)
        /// A second, marginally lighter tone used as the far end of the app gradient.
        static let backgroundElevated = Color(red: 0.09, green: 0.09, blue: 0.13)

        /// Slightly lifted surface for cards (paired with .ultraThinMaterial overlay).
        static let card = Color(red: 0.12, green: 0.12, blue: 0.16)
        /// A touch lighter, for the top of a soft card gradient.
        static let cardElevated = Color(red: 0.16, green: 0.16, blue: 0.21)

        /// Accent — a confident violet-blue.
        static let accent = Color(red: 0.52, green: 0.43, blue: 0.96)
        static let accentSecondary = Color(red: 0.35, green: 0.58, blue: 0.98)

        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.64)
        static let textTertiary = Color.white.opacity(0.40)

        static let success = Color(red: 0.34, green: 0.80, blue: 0.48)
        static let warning = Color(red: 0.97, green: 0.74, blue: 0.28)
        static let error = Color(red: 0.96, green: 0.40, blue: 0.40)

        static let separator = Color.white.opacity(0.08)

        /// The app-wide background: a soft, slow vertical gradient from the deep base
        /// up to a slightly elevated tone, with a faint cool cast. Sits behind every
        /// screen so the whole app feels like one continuous, gently-lit surface.
        static let appBackground = LinearGradient(
            stops: [
                .init(color: background, location: 0.0),
                .init(color: Color(red: 0.06, green: 0.06, blue: 0.09), location: 0.55),
                .init(color: backgroundElevated, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        /// A soft surface gradient for cards/sheets — subtle top-light, so panels read
        /// as gently raised rather than flat blocks.
        static let cardGradient = LinearGradient(
            colors: [cardElevated, card],
            startPoint: .top,
            endPoint: .bottom
        )

        /// Gradient used behind hero areas — gentler than before, easing the accent
        /// into the background without a hard edge.
        static let heroGradient = LinearGradient(
            stops: [
                .init(color: accent.opacity(0.28), location: 0.0),
                .init(color: accent.opacity(0.06), location: 0.45),
                .init(color: background.opacity(0.0), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// A soft accent wash for selected/active states.
        static let accentWash = LinearGradient(
            colors: [accent.opacity(0.85), accentSecondary.opacity(0.85)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Radii

    enum Radius {
        static var card: CGFloat { Theme.scaled(18, min: 12) }
        static var largeCard: CGFloat { Theme.scaled(24, min: 16) }
        static var button: CGFloat { Theme.scaled(14, min: 10) }
        static let pill: CGFloat = 999
    }

    // MARK: - Soft depth

    /// A soft, diffuse shadow for raised surfaces — low opacity and a wide blur so
    /// panels feel gently lifted rather than hard-edged. Apple-style restraint.
    enum Shadow {
        static let color = Color.black.opacity(0.35)
        static var radius: CGFloat { Theme.scaled(24, min: 12) }
        static var y: CGFloat { Theme.scaled(10, min: 5) }
    }

    // MARK: - Spacing

    enum Spacing {
        static var xs: CGFloat { Theme.scaled(6, min: 4) }
        static var sm: CGFloat { Theme.scaled(12, min: 8) }
        static var md: CGFloat { Theme.scaled(20, min: 12) }
        static var lg: CGFloat { Theme.scaled(32, min: 18) }
        static var xl: CGFloat { Theme.scaled(48, min: 24) }
        static var rowGap: CGFloat { Theme.scaled(44, min: 22) }
        /// Safe screen edge padding (60 on tvOS, ~20 on iPhone).
        static var edge: CGFloat { Theme.scaled(60, min: 20) }
    }

    // MARK: - Card sizes

    enum CardSize {
        /// Standard poster card (2:3-ish).
        static var posterWidth: CGFloat { Theme.scaled(240, min: 120) }
        static var posterHeight: CGFloat { Theme.scaled(360, min: 180) }

        /// Wide "continue watching" card (16:9-ish).
        static var wideWidth: CGFloat { Theme.scaled(420, min: 280) }
        static var wideHeight: CGFloat { Theme.scaled(236, min: 158) }

        /// Source card.
        static var sourceWidth: CGFloat { Theme.scaled(300, min: 150) }
        static var sourceHeight: CGFloat { Theme.scaled(200, min: 120) }

        /// Focus scale applied on highlight (tvOS only; subtle on iOS).
        static var focusScale: CGFloat { Theme.isCompact ? 1.0 : 1.08 }
    }

    // MARK: - Adaptive grids

    /// Poster-grid columns tuned per device. iPad gets a fixed, comfortable multi-column
    /// layout instead of an adaptive count that can look sparse; iPhone stays adaptive
    /// so it fills narrow widths; tvOS uses a wide adaptive grid.
    static var posterGridColumns: [GridItem] {
        #if os(tvOS)
        return [GridItem(.adaptive(minimum: CardSize.posterWidth), spacing: Spacing.lg)]
        #else
        if isPad {
            return Array(repeating: GridItem(.flexible(), spacing: Spacing.lg), count: 4)
        } else {
            return [GridItem(.adaptive(minimum: CardSize.posterWidth), spacing: Spacing.lg)]
        }
        #endif
    }

    // MARK: - Typography helpers

    enum Font {
        static func sectionTitle() -> SwiftUI.Font { .system(size: Theme.scaledFont(30), weight: .bold) }
        static func cardTitle() -> SwiftUI.Font { .system(size: Theme.scaledFont(22), weight: .semibold) }
        static func cardSubtitle() -> SwiftUI.Font { .system(size: Theme.scaledFont(18), weight: .regular) }
        static func screenTitle() -> SwiftUI.Font { .system(size: Theme.scaledFont(56), weight: .heavy) }
    }
}

// MARK: - Responsive font convenience

extension SwiftUI.Font {
    /// A platform-scaled system font. Use in place of `.system(size:weight:)` so
    /// inline type shrinks on iPhone the same way the design tokens do.
    static func appFont(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular,
                    design: SwiftUI.Font.Design = .default) -> SwiftUI.Font {
        .system(size: Theme.scaledFont(size), weight: weight, design: design)
    }
}

// MARK: - Title styling

extension View {
    /// Ensures a large screen title never wraps to one character per line on a
    /// narrow screen: caps to a single line and scales down to fit.
    func screenTitleStyle() -> some View {
        self.lineLimit(1)
            .minimumScaleFactor(0.5)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Surface styling

extension View {
    /// Places the soft app-wide gradient behind a screen so every view shares one
    /// continuous, gently-lit backdrop instead of a flat fill.
    func appBackground() -> some View {
        self.background(Theme.Colors.appBackground.ignoresSafeArea())
    }

    /// Wraps content in an elegant raised card: soft surface gradient, rounded
    /// corners, a hairline edge for definition, and a diffuse shadow.
    func softCard(cornerRadius: CGFloat? = nil, padding: CGFloat? = nil) -> some View {
        let radius = cornerRadius ?? Theme.Radius.card
        return self
            .padding(padding ?? Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.Colors.cardGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: Theme.Shadow.color, radius: Theme.Shadow.radius, x: 0, y: Theme.Shadow.y)
    }
}
