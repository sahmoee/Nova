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

    // MARK: - Dynamic Type (accessibility text sizes)
    //
    // The whole app sizes text through `appFont`. To honor the user's accessibility
    // text-size setting, iOS routes those sizes through UIFontMetrics so they grow and
    // shrink with the system Larger Text control (and any in-app boost). tvOS has no
    // Dynamic Type, so it keeps its fixed 10-foot sizing untouched.

    #if os(iOS)
    /// When false, text stays at the app's designed size regardless of the system
    /// setting. When true (default), text scales with Dynamic Type. Set from
    /// SettingsStore at launch and whenever the user changes it.
    nonisolated(unsafe) static var respectSystemTextSize = true
    /// An additional multiplier the user can apply in-app (1.0 = none). Lets people
    /// enlarge FrameTV's text without changing their whole phone.
    nonisolated(unsafe) static var textSizeBoost: CGFloat = 1.0
    /// A ceiling so very large accessibility sizes don't shatter dense layouts.
    private static let maxDynamicScale: CGFloat = 1.6
    #endif

    // MARK: - Component style (app-wide look)

    /// The app-wide component look. `.refined` (default) gives buttons, cards, and rows
    /// softer fills, cleaner hairline borders, and gentle gradients; `.classic` keeps
    /// the original flatter look. Read by the shared ButtonStyles, which can't observe
    /// objects, so it lives here as a static set from SettingsStore at launch. Applies
    /// on both iOS and tvOS.
    nonisolated(unsafe) static var uiStyle: UIComponentStyle = .refined

    /// Returns a body-relative font metric-scaled point size on iOS (respecting the
    /// user's text-size preferences), or the raw platform-scaled size on tvOS.
    static func dynamicFontSize(_ base: CGFloat) -> CGFloat {
        let scaled = scaledFont(base)
        #if os(iOS)
        var value = scaled
        if respectSystemTextSize {
            // Grow/shrink with the system Dynamic Type setting, capped so extreme
            // accessibility sizes stay within the layout.
            let metric = UIFontMetrics(forTextStyle: .body).scaledValue(for: scaled)
            let ratio = Swift.min(metric / scaled, maxDynamicScale)
            value = scaled * ratio
        }
        value *= textSizeBoost
        return value
        #else
        return scaled
        #endif
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
        static let appBackground: LinearGradient = {
            #if os(tvOS)
            // Apple TV app style: a near-black, uniform canvas so artwork carries
            // all the color and focused elements pop with light, not hue.
            return LinearGradient(
                stops: [
                    .init(color: Color(red: 0.03, green: 0.03, blue: 0.04), location: 0.0),
                    .init(color: Color(red: 0.05, green: 0.05, blue: 0.06), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            #else
            return LinearGradient(
                stops: [
                    .init(color: background, location: 0.0),
                    .init(color: Color(red: 0.06, green: 0.06, blue: 0.09), location: 0.55),
                    .init(color: backgroundElevated, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            #endif
        }()

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
        static var focusScale: CGFloat {
            #if os(tvOS)
            return 1.05
            #else
            return Theme.isCompact ? 1.0 : 1.08
            #endif
        }
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
            // Adaptive columns sized to the card's real width, so the grid fits as
            // many posters as the orientation allows (about 4 in portrait, 5 to 6 in
            // landscape) while always keeping proper spacing. Fixed column counts
            // crowded the fixed-width cards together in portrait.
            return [GridItem(.adaptive(minimum: CardSize.posterWidth), spacing: Spacing.lg)]
        } else {
            return [GridItem(.adaptive(minimum: CardSize.posterWidth), spacing: Spacing.lg)]
        }
        #endif
    }

    // MARK: - Typography helpers

    enum Font {
        static func sectionTitle() -> SwiftUI.Font {
            #if os(tvOS)
            return .system(size: Theme.dynamicFontSize(29), weight: .semibold)
            #else
            return .system(size: Theme.dynamicFontSize(30), weight: .bold)
            #endif
        }
        static func cardTitle() -> SwiftUI.Font { .system(size: Theme.dynamicFontSize(22), weight: .semibold) }
        static func cardSubtitle() -> SwiftUI.Font { .system(size: Theme.dynamicFontSize(18), weight: .regular) }
        static func screenTitle() -> SwiftUI.Font {
            #if os(tvOS)
            return .system(size: Theme.dynamicFontSize(52), weight: .bold)
            #else
            return .system(size: Theme.dynamicFontSize(56), weight: .heavy)
            #endif
        }
    }
}

// MARK: - Responsive font convenience

extension SwiftUI.Font {
    /// A platform-scaled system font. Use in place of `.system(size:weight:)` so
    /// inline type shrinks on iPhone the same way the design tokens do.
    static func appFont(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular,
                    design: SwiftUI.Font.Design = .default) -> SwiftUI.Font {
        .system(size: Theme.dynamicFontSize(size), weight: weight, design: design)
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

// MARK: - Wrapping flow layout

/// A simple wrapping HStack: lays children left-to-right and wraps to the next line
/// when they don't fit. Used for chip/badge rows (rating badges, source links) so they
/// never overflow a narrow column or wrap mid-word inside a single chip. Available on
/// iOS 16+/tvOS 16+ via the Layout protocol; the app targets 26.0 so this is safe.
struct WrapFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    /// Horizontal alignment of each row within the available width. Defaults to
    /// leading so existing callers are unaffected; pass .center to center rows.
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalWidth = Swift.max(totalWidth, rowWidth)
                totalHeight += rowHeight + lineSpacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = Swift.max(rowHeight, size.height)
            }
        }
        totalWidth = Swift.max(totalWidth, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width

        // Group subviews into rows first, so each row can be centered if requested.
        var rows: [[Int]] = []
        var current: [Int] = []
        var rowWidth: CGFloat = 0
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if !current.isEmpty, rowWidth + spacing + size.width > maxWidth {
                rows.append(current)
                current = [i]
                rowWidth = size.width
            } else {
                rowWidth += (current.isEmpty ? 0 : spacing) + size.width
                current.append(i)
            }
        }
        if !current.isEmpty { rows.append(current) }

        var y = bounds.minY
        for row in rows {
            let sizes = row.map { subviews[$0].sizeThatFits(.unspecified) }
            let rowW = sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(row.count - 1, 0))
            let rowHeight = sizes.map(\.height).max() ?? 0
            var x = bounds.minX + (alignment == .center ? max(0, (maxWidth - rowW) / 2) : 0)
            for (idx, subviewIndex) in row.enumerated() {
                let size = sizes[idx]
                subviews[subviewIndex].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                             proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + lineSpacing
        }
    }
}

// MARK: - Paste affordance

#if os(iOS)
/// A small pill Paste button that writes the clipboard's text into a binding. Placed
/// beside URL/token fields so users don't have to long-press to paste. Trims
/// surrounding whitespace/newlines that often ride along with a copied link.
struct PasteButton: View {
    @Binding var text: String
    var onPaste: ((String) -> Void)? = nil

    var body: some View {
        Button {
            if let s = UIPasteboard.general.string {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                text = trimmed
                onPaste?(trimmed)
            }
        } label: {
            Label("Paste", systemImage: "doc.on.clipboard")
                .font(.appFont(16, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Colors.card, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Paste from clipboard")
    }
}
#endif

// MARK: - Component style enum

/// The app-wide component look, applied across every shared button, card, and row.
enum UIComponentStyle: String, CaseIterable, Identifiable {
    /// Softer fills, hairline borders, gentle gradients on filled buttons (default).
    case refined
    /// The original flatter look.
    case classic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .refined: return "Refined"
        case .classic: return "Classic"
        }
    }
}

// MARK: - Refined card background

extension View {
    /// A drop-in replacement for `.background(Theme.Colors.card, in: RoundedRectangle(...))`
    /// that honors the app style: a subtle surface gradient with a hairline edge in
    /// Refined, or the original flat fill in Classic. Keeps the same footprint so it
    /// doesn't shift any layout.
    func refinedCardBackground(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if os(tvOS)
        return self
            .background(Color.white.opacity(0.08), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        #else
        return self
            .background(
                Theme.uiStyle == .refined
                    ? AnyShapeStyle(Theme.Colors.cardGradient)
                    : AnyShapeStyle(Theme.Colors.card),
                in: shape
            )
            .overlay(
                shape.strokeBorder(Color.white.opacity(Theme.uiStyle == .refined ? 0.07 : 0.0),
                                   lineWidth: 1)
            )
        #endif
    }
}
