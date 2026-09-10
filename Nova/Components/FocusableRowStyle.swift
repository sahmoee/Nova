//
//  FocusableRowStyle.swift
//  Nova
//
//  On tvOS, wrapping content in a Button or NavigationLink applies the system's
//  default Apple TV focus lift. These shared styles keep that neutral system
//  language consistent for custom rows and controls.
//

import SwiftUI

/// The current dynamic accent, injected at the root from AccentManager so even
/// ButtonStyles (which can't observe objects directly) can use it.
private struct DynamicAccentKey: EnvironmentKey {
    static let defaultValue: Color = AccentManager.fallback
}
extension EnvironmentValues {
    var dynamicAccent: Color {
        get { self[DynamicAccentKey.self] }
        set { self[DynamicAccentKey.self] = newValue }
    }
}

/// A button style that renders its label inside a rounded card and reacts to focus
/// (tvOS) or press (iOS) with an accent highlight and a gentle scale — never the
/// default white focus card.
struct NovaRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        #if os(tvOS)
        TVReferenceButtonStyle(cornerRadius: 14, horizontalPadding: 16, verticalPadding: 12).makeBody(configuration: configuration)
        #else
        NovaRowBody(configuration: configuration)
        #endif
    }

    private struct NovaRowBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled

        private var active: Bool {
            guard isEnabled else { return false }
            #if os(tvOS)
            return isFocused
            #else
            return configuration.isPressed
            #endif
        }

        var body: some View {
            return configuration.label
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(active ? AnyShapeStyle(Color.white)
                                     : AnyShapeStyle(Theme.Colors.controlGlass))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Color.white.opacity(active ? 0.9 : 0.15), lineWidth: 0.8)
                )
                .foregroundStyle(active ? Color.black : Theme.Colors.textPrimary)
                .scaleEffect(active && !Theme.isReduceMotion ? 1.06 : 1.0)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(Theme.isReduceMotion ? nil : .easeOut(duration: 0.2), value: active)
        }
    }
}

extension View {
    /// Applies the Nova row style to a Button/NavigationLink label, replacing the
    /// default tvOS white focus card with an accent highlight.
    func novaRowStyle() -> some View {
        buttonStyle(NovaRowButtonStyle())
    }
}

/// A focus style for small capsule chips (e.g. season selectors, filter pills) that
/// already provide their own background. Adds only an accent ring + lift on focus and,
/// because it's a custom ButtonStyle, fully suppresses the tvOS default white card.
struct NovaChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        #if os(tvOS)
        TVReferenceButtonStyle(cornerRadius: 10).makeBody(configuration: configuration)
        #else
        NovaChipBody(configuration: configuration)
        #endif
    }

    private struct NovaChipBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled

        private var active: Bool {
            guard isEnabled else { return false }
            #if os(tvOS)
            return isFocused
            #else
            return configuration.isPressed
            #endif
        }

        var body: some View {
            configuration.label
                .background(
                    Capsule().fill(active ? AnyShapeStyle(Color.white)
                                          : AnyShapeStyle(Theme.Colors.controlGlass))
                )
                .overlay(Capsule().strokeBorder(Color.white.opacity(active ? 0.9 : 0.14), lineWidth: 0.75))
                .foregroundStyle(active ? Color.black : Theme.Colors.textPrimary)
                .scaleEffect(active && !Theme.isReduceMotion ? 1.08 : 1.0)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(Theme.isReduceMotion ? nil : .easeOut(duration: 0.18), value: active)
        }
    }
}

/// A focus-reactive container for non-button rows (e.g. cards in a grid). Mirrors the
/// button style's highlight so the whole app shares one focus language.
struct FocusHighlight: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.card
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        let active = isFocused && isEnabled
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(active ? Theme.Colors.focusRing : .clear, lineWidth: 3)
            )
            .scaleEffect(active && !Theme.isReduceMotion ? 1.075 : 1.0)
            .animation(Theme.isReduceMotion ? nil : .easeOut(duration: 0.2), value: active)
    }
}

extension View {
    func focusHighlight(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        modifier(FocusHighlight(cornerRadius: cornerRadius))
    }
}

/// A focus style for small inline icon buttons (search clear, AI, etc.). It keeps the
/// icon compact and reacts to focus with an accent tint and a circular highlight,
/// instead of the default tvOS white focus card.
struct NovaIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        #if os(tvOS)
        TVReferenceButtonStyle(cornerRadius: 28, horizontalPadding: 8, verticalPadding: 8).makeBody(configuration: configuration)
        #else
        NovaIconBody(configuration: configuration)
        #endif
    }

    private struct NovaIconBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled

        private var active: Bool {
            guard isEnabled else { return false }
            #if os(tvOS)
            return isFocused
            #else
            return configuration.isPressed
            #endif
        }

        var body: some View {
            configuration.label
                .padding(Theme.Spacing.xs)
                .background(
                    Circle().fill(active ? AnyShapeStyle(Color.white)
                                         : AnyShapeStyle(Theme.Colors.controlGlass))
                )
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(active ? 0.9 : 0.14), lineWidth: 0.75)
                )
                .foregroundStyle(active ? Color.black : Theme.Colors.textPrimary)
                .scaleEffect(active && !Theme.isReduceMotion ? 1.12 : 1.0)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(Theme.isReduceMotion ? nil : .easeOut(duration: 0.18), value: active)
        }
    }
}

extension View {
    /// Applies the compact icon-button focus style (no white focus card).
    func novaIconStyle() -> some View {
        buttonStyle(NovaIconButtonStyle())
    }
}

/// A focus style for full-width rows that already sit inside a card/list container
/// (e.g. search suggestions). It highlights on focus with an accent tint and rounded
/// fill, without adding its own outer card, and never shows the tvOS white focus card.
struct NovaListRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        #if os(tvOS)
        TVReferenceButtonStyle(cornerRadius: 10).makeBody(configuration: configuration)
        #else
        NovaListRowBody(configuration: configuration)
        #endif
    }

    private struct NovaListRowBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled

        private var active: Bool {
            guard isEnabled else { return false }
            #if os(tvOS)
            return isFocused
            #else
            return configuration.isPressed
            #endif
        }

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .fill(active ? AnyShapeStyle(Color.white)
                                     : AnyShapeStyle(Color.white.opacity(0.045)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .strokeBorder(Color.white.opacity(active ? 0.9 : 0.10), lineWidth: 0.75)
                )
                .foregroundStyle(active ? Color.black : Theme.Colors.textPrimary)
                .scaleEffect(active && !Theme.isReduceMotion ? 1.01 : 1.0)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(Theme.isReduceMotion ? nil : .easeOut(duration: 0.18), value: active)
        }
    }
}
