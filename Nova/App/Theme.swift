//
//  Theme.swift
//  Nova
//
//  Shared Apple platform design tokens. Nova uses system typography, neutral
//  Apple TV surfaces, standard semantic colors, and native focus behavior.
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
    // `UIDevice` is main-actor-isolated under Swift 6, but the idiom is a fixed
    // device trait. These design tokens are first read during SwiftUI rendering on
    // the main actor, so assume main isolation to read it for this constant.
    static let isPad: Bool = MainActor.assumeIsolated {
        UIDevice.current.userInterfaceIdiom == .pad
    }
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

    /// Scales typography independently from artwork and spacing. Body copy must not
    /// shrink by the same ratio as a 240-point television poster: doing so made many
    /// perfectly ordinary 15–20 point labels render at the old 11-point floor on an
    /// iPhone. Small values are already authored as readable body sizes; only display
    /// type needs substantial reduction on handheld devices.
    static func scaledFont(_ size: CGFloat, min floor: CGFloat = 13) -> CGFloat {
        #if os(tvOS)
        let factor: CGFloat = 1
        #elseif os(iOS)
        let factor: CGFloat
        if size <= 24 {
            factor = 1
        } else if size <= 40 {
            factor = isPad ? 0.86 : 0.72
        } else {
            factor = isPad ? 0.72 : 0.58
        }
        #else
        let factor: CGFloat = 1
        #endif
        return Swift.max(size * factor, floor)
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
    /// enlarge Nova's text without changing their whole phone.
    nonisolated(unsafe) static var textSizeBoost: CGFloat = 1.0
    /// Dense streaming layouts need progressively tighter caps as the designed
    /// font gets larger. Body copy can still grow substantially, while display
    /// titles no longer expand until they consume most of an iPhone screen.
    private static func maxDynamicScale(for designedSize: CGFloat) -> CGFloat {
        switch designedSize {
        case ..<18: return 1.50
        case ..<24: return 1.38
        case ..<32: return 1.26
        case ..<42: return 1.18
        default:    return 1.10
        }
    }
    #endif

    // MARK: - Component style (app-wide look)

    /// Retained for preference-file compatibility. Both stored values now render
    /// with the same system appearance.
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
            let ratio = Swift.min(metric / scaled, maxDynamicScale(for: scaled))
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
        // Read live (the setting can change at runtime). `UIAccessibility` is
        // main-actor-isolated; this is only read from SwiftUI style bodies on main.
        return MainActor.assumeIsolated { UIAccessibility.isReduceMotionEnabled }
        #else
        return false
        #endif
    }

    // MARK: - Colors

    enum Colors {
        static let background = Color.black
        static let backgroundElevated = Color(white: 0.075)

        static let card = Color.white.opacity(0.08)
        static let cardElevated = Color(white: 0.12)

        #if os(tvOS)
        static let accent = Color.white
        static let accentSecondary = Color.white
        #else
        static let accent = Color.blue
        static let accentSecondary = Color.blue
        #endif
        static let iconRed = Color.red
        static let iconGraphite = Color.secondary
        static let iconSilver = Color.secondary

        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color.secondary.opacity(0.78)
        static let textQuaternary = Color.secondary.opacity(0.58)

        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red

        static let separator = Color.white.opacity(0.12)
        static let hairlineStrong = Color.white.opacity(0.22)
        static let focusRing = Color.white

        // Quiet quality-mark accents (Vision / HDR / Atmos chips) + progress + watched.
        static let recommended = Color.secondary
        static let markNeutral = Color.secondary
        static let markVision = Color.purple
        static let markHDR = Color.orange
        static let markAudio = Color.blue
        static let progressTrack = Color.white.opacity(0.22)
        static let progressFill = Color.white
        static let watched = Color.green

        #if os(tvOS)
        static let appBackground = TVReferenceStyle.canvas
        #else
        static let appBackground = LinearGradient(colors: [Color.black, Color.black],
                                                  startPoint: .top, endPoint: .bottom)

        #endif

        static let cardGradient = LinearGradient(
            colors: [Color.white.opacity(0.10), Color.white.opacity(0.10)],
            startPoint: .top,
            endPoint: .bottom
        )

        static let heroGradient = LinearGradient(
            stops: [
                .init(color: Color.black.opacity(0.02), location: 0.0),
                .init(color: Color.black.opacity(0.30), location: 0.55),
                .init(color: Color.black.opacity(0.86), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        static let accentWash = LinearGradient(
            colors: [accent, accent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let controlGlass = LinearGradient(
            colors: [Color.white.opacity(0.12), Color.white.opacity(0.12)],
            startPoint: .top,
            endPoint: .bottom
        )

        static let focusedControl = LinearGradient(
            colors: [accent, accent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Radii

    enum Radius {
        static var card: CGFloat { Theme.scaled(16, min: 12) }
        static var largeCard: CGFloat { Theme.scaled(22, min: 16) }
        static var button: CGFloat { Theme.scaled(14, min: 10) }
        static let pill: CGFloat = 999
        static let poster: CGFloat = 10
        static let thumb: CGFloat = 9
    }

    // MARK: - Soft depth

    /// A soft, diffuse shadow for raised surfaces — low opacity and a wide blur so
    /// panels feel gently lifted rather than hard-edged. Apple-style restraint.
    enum Shadow {
        static let color = Color.black.opacity(0.35)
        static var radius: CGFloat { Theme.scaled(24, min: 12) }
        static var y: CGFloat { Theme.scaled(10, min: 5) }
    }

    // MARK: - Motion

    /// Shared animation constants so entrances/exits feel consistent app-wide.
    /// Additive only — existing per-site animations are unchanged.
    enum Motion {
        /// Standard springy show/hide for panels, prompts, and the mini player bar.
        static let spring = SwiftUI.Animation.spring(response: 0.38, dampingFraction: 0.82)
        // Calm, quick easing for chrome and artwork crossfades.
        static let quick = SwiftUI.Animation.easeOut(duration: 0.18)
        static let standard = SwiftUI.Animation.easeOut(duration: 0.28)
        static let crossfade = SwiftUI.Animation.easeInOut(duration: 0.40)
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

    /// Minimum interactive sizes. 44pt is Apple's recommended minimum tap target;
    /// scaled up a little on tvOS. minButtonWidth keeps short-labelled secondary
    /// buttons from collapsing to a cramped chip width.
    static var minTouchTarget: CGFloat { Theme.scaled(52, min: 44) }
    static var minButtonWidth: CGFloat { Theme.scaled(160, min: 96) }

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
            // Slightly tighter minimum than the card width so the grid fits one more
            // column per orientation (about 4 to 5 in portrait, 5 to 6 in landscape)
            // while cards still render at their full width inside each column.
            return [GridItem(.adaptive(minimum: CardSize.posterWidth * 0.85), spacing: Spacing.lg)]
        } else {
            return [GridItem(.adaptive(minimum: CardSize.posterWidth), spacing: Spacing.lg)]
        }
        #endif
    }

    // MARK: - Typography helpers

    enum Font {
        static func heroTitle() -> SwiftUI.Font { .system(size: Theme.dynamicFontSize(60), weight: .bold) }
        static func sectionTitle() -> SwiftUI.Font { .system(size: Theme.dynamicFontSize(30), weight: .bold) }
        static func cardTitle() -> SwiftUI.Font { .system(size: Theme.dynamicFontSize(22), weight: .semibold) }
        static func cardSubtitle() -> SwiftUI.Font { .system(size: Theme.dynamicFontSize(18), weight: .regular) }
        static func screenTitle() -> SwiftUI.Font { .system(size: Theme.dynamicFontSize(56), weight: .bold) }
        static func eyebrow() -> SwiftUI.Font { .system(size: Theme.dynamicFontSize(13), weight: .semibold) }
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
        self
            .foregroundStyle(Theme.Colors.textPrimary)
            .tint(Theme.Colors.accent)
            .background(Theme.Colors.appBackground.ignoresSafeArea())
            .presentationBackground(.regularMaterial)
    }

    /// Applies Nova's theme at a scene or presentation boundary. This catches
    /// system-owned navigation, menus, alerts and sheets that do not draw a custom
    /// `appBackground`, preventing the default gray/white flash during presentation.
    func novaThemeBoundary() -> some View {
        self
            .foregroundStyle(Theme.Colors.textPrimary)
            .tint(Theme.Colors.accent)
            .preferredColorScheme(.dark)
            .background(Theme.Colors.background.ignoresSafeArea())
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

    // REGRESSION GUARD — read before changing `wrapWidth`.
    //
    // A VStack sizes itself from its children's *ideal* widths, which it discovers by
    // probing them with an unspecified (nil) proposal. If this layout answers that
    // probe with "every chip on one line", that single-line total becomes the parent
    // column's width, and the whole block around it (description, year, the chip row
    // itself) is laid out wider than the screen and clipped on both edges. That is the
    // off-screen symptom this rail kept regressing to, and why fixing it at the call
    // site never held — the cause is here, in the layout, not at the call site.
    //
    // So: only wrap at the proposed width when that width is real and finite. For an
    // unspecified or infinite proposal, report the widest *single* subview — a width
    // that always fits on any screen. The real layout pass gets a concrete width in
    // `placeSubviews` and fills it normally, so nothing looks narrow in practice.

    /// The width rows should wrap at, given a (possibly absent) proposed width.
    private static func wrapWidth(_ proposed: CGFloat?, sizes: [CGSize]) -> CGFloat {
        if let proposed, proposed > 0, proposed.isFinite { return proposed }
        return sizes.map(\.width).max() ?? 0
    }

    /// Groups subviews into rows that each fit within `maxWidth`.
    private func rows(for sizes: [CGSize], maxWidth: CGFloat) -> [[Int]] {
        var rows: [[Int]] = []
        var current: [Int] = []
        var rowWidth: CGFloat = 0
        for (i, size) in sizes.enumerated() {
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
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        guard !sizes.isEmpty else { return .zero }
        let maxWidth = Self.wrapWidth(proposal.width, sizes: sizes)

        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        for (index, row) in rows(for: sizes, maxWidth: maxWidth).enumerated() {
            let rowSizes = row.map { sizes[$0] }
            let rowW = rowSizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(Swift.max(row.count - 1, 0))
            totalWidth = Swift.max(totalWidth, rowW)
            totalHeight += (rowSizes.map(\.height).max() ?? 0) + (index > 0 ? lineSpacing : 0)
        }
        // Never report more than we were allowed to use.
        return CGSize(width: Swift.min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        guard !sizes.isEmpty else { return }
        // Use the real laid-out width; fall back the same way `sizeThatFits` does if
        // we are somehow handed a degenerate (zero/infinite) bounds width.
        let maxWidth = Self.wrapWidth(bounds.width, sizes: sizes)

        var y = bounds.minY
        for row in rows(for: sizes, maxWidth: maxWidth) {
            let rowSizes = row.map { sizes[$0] }
            let rowW = rowSizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(Swift.max(row.count - 1, 0))
            let rowHeight = rowSizes.map(\.height).max() ?? 0
            var x = bounds.minX + (alignment == .center ? Swift.max(0, (maxWidth - rowW) / 2) : 0)
            for (idx, subviewIndex) in row.enumerated() {
                let size = rowSizes[idx]
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

/// Legacy preference values kept so older backups continue to decode. Nova now
/// renders a single system appearance regardless of the stored value.
enum UIComponentStyle: String, CaseIterable, Identifiable {
    /// Softer fills, hairline borders, gentle gradients on filled buttons (default).
    case refined
    /// The original flatter look.
    case classic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .refined, .classic: return "System"
        }
    }
}

// MARK: - Refined card background

extension View {
    /// Standard neutral grouped surface used across Apple platforms.
    func refinedCardBackground(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(
                AnyShapeStyle(Theme.Colors.cardGradient),
                in: shape
            )
            .overlay(
                shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            )
    }
}


// MARK: - Surface & header polish (merged from Components/Polish.swift)


// MARK: - Card surface

struct CardSurface: ViewModifier {
    var padding: CGFloat? = nil

    func body(content: Content) -> some View {
        content
            .padding(padding ?? Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Colors.card)
            )
    }
}

extension View {
    /// Standard card background + padding used across rows and tiles.
    func cardSurface(padding: CGFloat? = nil) -> some View {
        modifier(CardSurface(padding: padding))
    }
}

// MARK: - Section header

/// A consistent section header (title with optional trailing accessory), used to
/// break long screens into labelled groups.
struct SectionHeader<Accessory: View>: View {
    let title: String
    var systemImage: String? = nil
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.appFont(20, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
            Text(title)
                .font(.appFont(24, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: 0)
            accessory()
        }
        .padding(.bottom, Theme.Spacing.xs)
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(_ title: String, systemImage: String? = nil) {
        self.init(title: title, systemImage: systemImage, accessory: { EmptyView() })
    }
}

// MARK: - Press state (iOS)

/// Adds a subtle scale + opacity change while pressed on iOS, matching the tvOS
/// focus animation. No-op styling on tvOS where focus handles this.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !Theme.isReduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}


// MARK: - Destructive confirmation

/// One reusable delete-confirmation pattern: presents an alert naming the thing
/// being deleted, with a destructive Delete and a Cancel.
struct ConfirmDeleteModifier: ViewModifier {
    let title: String
    let itemName: String
    let message: String
    @Binding var isPresented: Bool
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            Button("Delete \u{201C}\(itemName)\u{201D}", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(message)
        }
    }
}

extension View {
    /// Attaches the app-standard destructive confirmation alert.
    func confirmDelete(_ title: String = "Delete?",
                       itemName: String,
                       message: String,
                       isPresented: Binding<Bool>,
                       onDelete: @escaping () -> Void) -> some View {
        modifier(ConfirmDeleteModifier(title: title, itemName: itemName,
                                       message: message, isPresented: isPresented,
                                       onDelete: onDelete))
    }
}
