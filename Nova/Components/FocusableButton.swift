//
//  FocusableButton.swift
//  Nova
//
//  A platform-adaptive Apple TV-style control with a bright, lifted focus state.
//

import SwiftUI

struct FocusableButton: View {
    let title: String
    var systemImage: String? = nil
    var prominent: Bool = false
    var accessibilityHint: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            // Prominent buttons stretch to fill; secondary buttons get a comfortable
            // minimum width so a short label ("Edit", "Add") still reads as a proper
            // button rather than a cramped chip, and a guaranteed 44pt-tall tap target.
            .frame(minWidth: prominent ? nil : Theme.minButtonWidth,
                   maxWidth: prominent ? .infinity : nil,
                   minHeight: Theme.minTouchTarget)
        }
        .buttonStyle(FocusableButtonStyle(prominent: prominent))
        .accessibilityHint(accessibilityHint ?? "")
    }
}

/// The button style behind FocusableButton. Implemented as a ButtonStyle (reading
/// isFocused from the environment) so that on tvOS it fully replaces the system focus
/// appearance — no white card behind the button.
struct FocusableButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        #if os(tvOS)
        TVReferenceButtonStyle(selected: prominent, horizontalPadding: 22, verticalPadding: 10).makeBody(configuration: configuration)
        #else
        FocusableButtonBody(configuration: configuration, prominent: prominent)
        #endif
    }

    private struct FocusableButtonBody: View {
        let configuration: Configuration
        let prominent: Bool
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

        private var background: some ShapeStyle {
            if prominent {
                return AnyShapeStyle(Theme.Colors.focusedControl)
            }
            return active ? AnyShapeStyle(Theme.Colors.focusedControl)
                          : AnyShapeStyle(Theme.Colors.controlGlass)
        }

        private var foreground: Color {
            guard isEnabled else { return Theme.Colors.textTertiary }
            return Theme.Colors.textPrimary
        }

        var body: some View {
            return configuration.label
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
                .background(background)
                .foregroundStyle(foreground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .stroke(Color.white.opacity(active ? 0.45 : 0.14), lineWidth: 1))
                .scaleEffect(active && !Theme.isReduceMotion ? 1.06 : 1.0)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(Theme.isReduceMotion ? nil : .easeOut(duration: 0.18), value: active)
        }
    }
}
