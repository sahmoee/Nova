//
//  OmniStyle.swift
//  Nova
//
//  Geometry and layout preferences for the Omni-style shell: a persistent sidebar,
//  a logo-first hero that yields to content rows, and per-shelf poster or landscape
//  rows. See docs/OMNI_STYLE_REDESIGN.md. Colors stay in Theme so every screen picks
//  up the same neutral canvas.
//

import SwiftUI

enum OmniStyle {
    // MARK: Sidebar (tvOS)

    /// Collapsed icon rail. Content is laid out to the right of this width.
    static let sidebarRailWidth: CGFloat = 112
    /// Expanded sidebar while it holds focus.
    static let sidebarExpandedWidth: CGFloat = 340
    static let sidebarItemHeight: CGFloat = 64

    // MARK: Page geometry

    #if os(tvOS)
    static let edge: CGFloat = 64
    static let rowSpacing: CGFloat = 46
    static let cardSpacing: CGFloat = 34
    static let rowTitleSize: CGFloat = 30
    #else
    static var edge: CGFloat { Theme.isPad ? 32 : 18 }
    static var rowSpacing: CGFloat { Theme.isPad ? 30 : 24 }
    static var cardSpacing: CGFloat { Theme.isPad ? 16 : 12 }
    static var rowTitleSize: CGFloat { Theme.isPad ? 22 : 19 }
    #endif

    static let cardRadius: CGFloat = 12

    /// Hero height as a share of the visible page height.
    static let heroHeightFraction: CGFloat = 0.82
    /// Hero height once focus moves into the rows below it.
    static let heroCollapsedFraction: CGFloat = 0.42

    // MARK: Card sizes

    static func posterWidth(_ size: OmniPosterSize) -> CGFloat {
        #if os(tvOS)
        switch size { case .small: 200; case .medium: 240; case .large: 290 }
        #else
        let base: CGFloat = Theme.isPad ? 150 : 112
        switch size { case .small: return base * 0.85; case .medium: return base; case .large: return base * 1.2 }
        #endif
    }

    static func landscapeWidth(_ size: OmniPosterSize) -> CGFloat {
        #if os(tvOS)
        switch size { case .small: 360; case .medium: 420; case .large: 500 }
        #else
        let base: CGFloat = Theme.isPad ? 280 : 220
        switch size { case .small: return base * 0.85; case .medium: return base; case .large: return base * 1.18 }
        #endif
    }
}

/// Global card size, like Omni's poster size setting.
enum OmniPosterSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// How shelves draw their cards. Per-shelf overrides live on `ShelfConfig.layout`.
enum OmniShelfLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case poster, landscape
    var id: String { rawValue }
    var title: String { self == .poster ? "Poster" : "Landscape" }
}

/// Sidebar presentation on tvOS. Rail keeps icons visible; hidden slides fully away.
enum OmniSidebarStyle: String, CaseIterable, Identifiable {
    case rail, hidden
    var id: String { rawValue }
    var title: String { self == .rail ? "Icon Rail" : "Hidden Until Opened" }
}

/// `@AppStorage` keys for the layout settings. Kept in one place so Settings,
/// Home and the sidebar read the same values.
enum OmniLayoutKey {
    static let posterSize = "omni.posterSize"
    static let alwaysShowTitles = "omni.alwaysShowTitles"
    static let smallContinueWatching = "omni.smallContinueWatching"
    static let highContrastFocus = "omni.highContrastFocus"
    static let sidebarStyle = "omni.sidebarStyle"
    static let heroAutoAdvance = "omni.heroAutoAdvance"
    static let showHeroLogo = "omni.showHeroLogo"
}

// MARK: - Focus treatment

/// Card button style shared by every Omni-style row: tvOS lift with an optional
/// high-contrast stroke, and a gentle press on touch platforms.
struct OmniCardButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = OmniStyle.cardRadius
    @AppStorage(OmniLayoutKey.highContrastFocus) private var highContrast = false

    func makeBody(configuration: Configuration) -> some View {
        OmniCardBody(configuration: configuration, cornerRadius: cornerRadius, highContrast: highContrast)
    }

    private struct OmniCardBody: View {
        let configuration: Configuration
        let cornerRadius: CGFloat
        let highContrast: Bool
        @Environment(\.isFocused) private var focused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .overlay {
                    if highContrast && focused {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(.white, lineWidth: 4)
                            .allowsHitTesting(false)
                    }
                }
                .scaleEffect(scale, anchor: .center)
                .shadow(color: .black.opacity(focused ? 0.55 : 0), radius: focused ? 22 : 0, y: focused ? 14 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: focused)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
        }

        private var scale: CGFloat {
            if configuration.isPressed { return 0.97 }
            #if os(tvOS)
            return focused && !reduceMotion ? 1.08 : 1
            #else
            return 1
            #endif
        }
    }
}

extension View {
    /// `focusSection()` on tvOS; a no-op on iOS and Mac Catalyst, which lack it.
    @ViewBuilder
    func omniFocusSection() -> some View {
        #if os(tvOS)
        focusSection()
        #else
        self
        #endif
    }
}
