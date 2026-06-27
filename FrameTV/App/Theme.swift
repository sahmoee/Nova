//
//  Theme.swift
//  FrameTV
//
//  Centralized design tokens: colors, corner radii, spacing, card sizes, and
//  typography. Values are tuned for a dark, cinematic Apple TV look and scale
//  down responsively on iPhone/iPad so the same screens read well on a handheld.
//

import SwiftUI

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
    #else
    /// On iOS/iPadOS, shrink to a comfortable handheld scale.
    static let isCompact = true
    static let uiScale: CGFloat = 0.62
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
        /// Near-black app background.
        static let background = Color(red: 0.04, green: 0.04, blue: 0.06)

        /// Slightly lifted surface for cards (paired with .ultraThinMaterial overlay).
        static let card = Color(red: 0.11, green: 0.11, blue: 0.14)

        /// Accent — a confident violet-blue.
        static let accent = Color(red: 0.49, green: 0.40, blue: 0.95)
        static let accentSecondary = Color(red: 0.30, green: 0.55, blue: 0.98)

        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.62)
        static let textTertiary = Color.white.opacity(0.38)

        static let success = Color(red: 0.30, green: 0.78, blue: 0.45)
        static let warning = Color(red: 0.96, green: 0.72, blue: 0.25)
        static let error = Color(red: 0.95, green: 0.36, blue: 0.36)

        static let separator = Color.white.opacity(0.10)

        /// Gradient used behind hero areas.
        static let heroGradient = LinearGradient(
            colors: [accent.opacity(0.35), background],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Radii

    enum Radius {
        static var card: CGFloat { Theme.scaled(16, min: 10) }
        static var largeCard: CGFloat { Theme.scaled(20, min: 12) }
        static var button: CGFloat { Theme.scaled(12, min: 8) }
        static let pill: CGFloat = 999
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
