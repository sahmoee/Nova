//
//  FocusableRowStyle.swift
//  FrameTV
//
//  On tvOS, wrapping content in a Button or NavigationLink applies the system's
//  default focus effect, which lifts the row onto a bright white card. That looks out
//  of place in a dark, cinematic UI. This file provides a single, reusable style that
//  gives rows an elegant accent-tinted highlight with a subtle lift instead, matching
//  the rest of FrameTV. On iOS it falls back to a simple pressed/selected state.
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
struct FrameRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FrameRowBody(configuration: configuration)
    }

    private struct FrameRowBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.dynamicAccent) private var accent

        private var active: Bool {
            #if os(tvOS)
            return isFocused
            #else
            return configuration.isPressed
            #endif
        }

        private var rowFill: AnyShapeStyle {
            #if os(tvOS)
            // Apple TV app style: focus brightens the row surface itself.
            if active { return AnyShapeStyle(Color.white.opacity(0.22)) }
            return AnyShapeStyle(Color.white.opacity(0.08))
            #else
            if active { return AnyShapeStyle(accent.opacity(0.22)) }
            let refined = Theme.uiStyle == .refined
            return refined ? AnyShapeStyle(Theme.Colors.cardGradient)
                           : AnyShapeStyle(Theme.Colors.card)
            #endif
        }

        private var rowStroke: Color {
            #if os(tvOS)
            return active ? Color.white : Color.white.opacity(0.08)
            #else
            let refined = Theme.uiStyle == .refined
            return active ? accent : Color.white.opacity(refined ? 0.08 : 0.06)
            #endif
        }

        private var rowShadow: Color {
            #if os(tvOS)
            return active ? Color.black.opacity(0.55) : .clear
            #else
            return active ? accent.opacity(0.4) : .clear
            #endif
        }

        var body: some View {
            return configuration.label
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(rowFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(rowStroke, lineWidth: active ? 2.5 : 1)
                )
                .shadow(color: rowShadow, radius: active ? 22 : 0, y: active ? 8 : 0)
                .scaleEffect(active ? 1.035 : 1.0)
                .animation(.easeOut(duration: 0.2), value: active)
        }
    }
}

extension View {
    /// Applies the FrameTV row style to a Button/NavigationLink label, replacing the
    /// default tvOS white focus card with an accent highlight.
    func frameRowStyle() -> some View {
        buttonStyle(FrameRowButtonStyle())
    }
}

/// A focus style for small capsule chips (e.g. season selectors, filter pills) that
/// already provide their own background. Adds only an accent ring + lift on focus and,
/// because it's a custom ButtonStyle, fully suppresses the tvOS default white card.
struct FrameChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FrameChipBody(configuration: configuration)
    }

    private struct FrameChipBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.dynamicAccent) private var accent

        private var active: Bool {
            #if os(tvOS)
            return isFocused
            #else
            return configuration.isPressed
            #endif
        }

        private var chipRing: Color {
            #if os(tvOS)
            return .white
            #else
            return accent
            #endif
        }

        private var chipShadow: Color {
            #if os(tvOS)
            return Color.black.opacity(0.5)
            #else
            return accent.opacity(0.45)
            #endif
        }

        var body: some View {
            configuration.label
                .overlay(
                    Capsule().strokeBorder(active ? chipRing : .clear, lineWidth: 3)
                )
                .shadow(color: active ? chipShadow : .clear,
                        radius: active ? 18 : 0, y: active ? 6 : 0)
                .scaleEffect(active ? 1.08 : 1.0)
                .animation(.easeOut(duration: 0.18), value: active)
        }
    }
}

/// A focus-reactive container for non-button rows (e.g. cards in a grid). Mirrors the
/// button style's highlight so the whole app shares one focus language.
struct FocusHighlight: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.card
    @Environment(\.isFocused) private var isFocused
    @Environment(\.dynamicAccent) private var accent

    private var ringColor: Color {
        #if os(tvOS)
        return .white
        #else
        return accent
        #endif
    }

    private var glowColor: Color {
        #if os(tvOS)
        return Color.black.opacity(0.55)
        #else
        return accent.opacity(0.45)
        #endif
    }

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isFocused ? ringColor : .clear, lineWidth: 4)
            )
            .shadow(color: isFocused ? glowColor : .clear,
                    radius: isFocused ? 26 : 0, y: isFocused ? 10 : 0)
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.2), value: isFocused)
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
struct FrameIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FrameIconBody(configuration: configuration)
    }

    private struct FrameIconBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.dynamicAccent) private var accent

        private var active: Bool {
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
                    Circle().fill(active ? accent.opacity(0.25) : .clear)
                )
                .overlay(
                    Circle().strokeBorder(active ? accent : .clear, lineWidth: 2)
                )
                .scaleEffect(active ? 1.12 : 1.0)
                .animation(.easeOut(duration: 0.18), value: active)
        }
    }
}

extension View {
    /// Applies the compact icon-button focus style (no white focus card).
    func frameIconStyle() -> some View {
        buttonStyle(FrameIconButtonStyle())
    }
}

/// A focus style for full-width rows that already sit inside a card/list container
/// (e.g. search suggestions). It highlights on focus with an accent tint and rounded
/// fill, without adding its own outer card, and never shows the tvOS white focus card.
struct FrameListRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FrameListRowBody(configuration: configuration)
    }

    private struct FrameListRowBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.dynamicAccent) private var accent

        private var active: Bool {
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
                        .fill(active ? accent.opacity(0.22) : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .strokeBorder(active ? accent : .clear, lineWidth: 2)
                )
                .scaleEffect(active ? 1.01 : 1.0)
                .animation(.easeOut(duration: 0.18), value: active)
        }
    }
}
