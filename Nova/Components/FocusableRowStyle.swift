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

/// Neutral native controls: tvOS owns one glass/focus surface; iOS retains system-blue
/// selection and a quiet pointer highlight. Selected state survives focus moving away.
struct NovaRowButtonStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        #if os(tvOS)
        TVReferenceButtonStyle(selected: selected, cornerRadius: Theme.Radius.card, horizontalPadding: 16, verticalPadding: 12)
            .makeBody(configuration: configuration)
        #else
        NovaHandheldControl(configuration: configuration, role: .row, selected: selected)
        #endif
    }
}

struct NovaChipButtonStyle: ButtonStyle {
    var selected = false
    /// Existing chips own their fill. Opt in for a bare label to avoid stacking surfaces.
    var providesSurface = false
    func makeBody(configuration: Configuration) -> some View {
        #if os(tvOS)
        TVReferenceButtonStyle(selected: selected, cornerRadius: Theme.Radius.chip,
                               horizontalPadding: providesSurface ? 16 : 0,
                               verticalPadding: providesSurface ? 8 : 0)
            .makeBody(configuration: configuration)
        #else
        NovaHandheldControl(configuration: configuration, role: .chip, selected: selected, providesSurface: providesSurface)
        #endif
    }
}

struct NovaIconButtonStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        #if os(tvOS)
        TVReferenceButtonStyle(selected: selected, cornerRadius: Theme.Radius.pill,
                               horizontalPadding: 8, verticalPadding: 8,
                               minimumWidth: TVReferenceStyle.controlHeight)
            .makeBody(configuration: configuration)
        #else
        NovaHandheldControl(configuration: configuration, role: .icon, selected: selected)
        #endif
    }
}

struct NovaListRowStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        #if os(tvOS)
        TVReferenceButtonStyle(selected: selected, cornerRadius: Theme.Radius.button)
            .makeBody(configuration: configuration)
        #else
        NovaHandheldControl(configuration: configuration, role: .list, selected: selected)
        #endif
    }
}

/// Poster links retain their artwork rather than inheriting a row's filled surface.
struct NovaArtworkButtonStyle: ButtonStyle {
    /// Radius of the outer focus frame, including its six-point artwork inset.
    var cornerRadius: CGFloat = Theme.Radius.poster + 6
    func makeBody(configuration: Configuration) -> some View {
        #if os(tvOS)
        TVArtworkButtonStyle(cornerRadius: cornerRadius).makeBody(configuration: configuration)
        #else
        HandheldArtworkBody(configuration: configuration, cornerRadius: cornerRadius)
        #endif
    }

    #if !os(tvOS)
    private struct HandheldArtworkBody: View {
        let configuration: ButtonStyleConfiguration
        let cornerRadius: CGFloat
        @Environment(\.isFocused) private var focused
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.colorSchemeContrast) private var contrast
        @State private var hovered = false
        var body: some View {
            let active = enabled && (focused || hovered)
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            configuration.label
                .padding(6)
                .overlay(shape.strokeBorder(active ? Theme.Colors.accent : .white.opacity(contrast == .increased ? 0.3 : 0),
                                            lineWidth: active ? Theme.Control.focusLineWidth : 1)
                    .allowsHitTesting(false))
                .contentShape(shape)
                .opacity(enabled ? 1 : Theme.Control.disabledOpacity)
                .scaleEffect(enabled && configuration.isPressed && !reduceMotion ? Theme.Control.pressedScale : 1)
                .animation(reduceMotion ? nil : Theme.Motion.quick, value: active)
                .animation(reduceMotion ? nil : Theme.Motion.quick, value: configuration.isPressed)
                .onHover { hovered = $0 }
        }
    }
    #endif
}

#if !os(tvOS)
/// Shared handheld rendering avoids four subtly different hover/press/disabled policies.
struct NovaHandheldControl: View {
    enum Role: Equatable { case row, chip, icon, list, prominent, button }
    let configuration: ButtonStyleConfiguration
    let role: Role
    var selected = false
    var providesSurface = true
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovered = false

    private var active: Bool { enabled && (focused || hovered || configuration.isPressed) }
    private var radius: CGFloat {
        switch role {
        case .row: Theme.Radius.card
        case .chip: Theme.Radius.chip
        case .icon: Theme.Radius.pill
        default: Theme.Radius.button
        }
    }
    private var horizontalPadding: CGFloat {
        switch role { case .row, .button, .prominent: Theme.Spacing.md; case .chip: providesSurface ? 14 : 0; case .icon: 4; default: 0 }
    }
    private var verticalPadding: CGFloat {
        switch role { case .row, .button, .prominent: Theme.Spacing.sm; case .icon: 4; default: 0 }
    }
    private var fill: Color {
        if role == .prominent { return Theme.Colors.accent }
        if selected { return reduceTransparency ? Color(white: 0.18) : Theme.Colors.accent.opacity(0.18) }
        return Color(white: active ? 0.23 : 0.14)
    }
    private var foreground: Color {
        role == .prominent ? .white : selected ? Theme.Colors.accent : Theme.Colors.textPrimary
    }
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minWidth: role == .icon ? Theme.minTouchTarget : nil, minHeight: Theme.minTouchTarget)
            .foregroundStyle(foreground)
            .background {
                if providesSurface {
                    if reduceTransparency || contrast == .increased || role == .row || role == .list || role == .prominent {
                        shape.fill(fill)
                    } else {
                        shape.fill(fill.opacity(0.45)).glassEffect(.regular.interactive(), in: shape)
                    }
                }
            }
            .overlay {
                shape.strokeBorder(selected || (focused && enabled) ? Theme.Colors.accent : .white.opacity(active ? 0.38 : contrast == .increased ? 0.45 : providesSurface ? 0.12 : 0),
                                   lineWidth: selected || (focused && enabled) || contrast == .increased ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
            .opacity(enabled ? 1 : Theme.Control.disabledOpacity)
            .scaleEffect(enabled && configuration.isPressed && !reduceMotion ? Theme.Control.pressedScale : 1)
            .animation(reduceMotion ? nil : Theme.Motion.quick, value: active)
            .onHover { hovered = $0 }
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
#endif

/// For a non-button container only. Button styles already own their focus frame.
struct FocusHighlight: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.card
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        let active = focused && enabled
        content
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(active ? Theme.Colors.focusRing : .clear, lineWidth: Theme.Control.focusLineWidth)
                .allowsHitTesting(false))
            .scaleEffect(active && !reduceMotion ? Theme.Control.focusScale : 1)
            .animation(reduceMotion ? nil : Theme.Motion.quick, value: active)
    }
}

extension View {
    func novaRowStyle() -> some View { buttonStyle(NovaRowButtonStyle()) }
    func novaIconStyle() -> some View { buttonStyle(NovaIconButtonStyle()) }
    func focusHighlight(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        modifier(FocusHighlight(cornerRadius: cornerRadius))
    }
}
