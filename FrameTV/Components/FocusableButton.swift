//
//  FocusableButton.swift
//  FrameTV
//
//  A button styled for tvOS with a clear focus state (scale + accent fill).
//

import SwiftUI

struct FocusableButton: View {
    let title: String
    var systemImage: String? = nil
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: prominent ? .infinity : nil)
        }
        .buttonStyle(FocusableButtonStyle(prominent: prominent))
    }
}

/// The button style behind FocusableButton. Implemented as a ButtonStyle (reading
/// isFocused from the environment) so that on tvOS it fully replaces the system focus
/// appearance — no white card behind the button.
struct FocusableButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        FocusableButtonBody(configuration: configuration, prominent: prominent)
    }

    private struct FocusableButtonBody: View {
        let configuration: Configuration
        let prominent: Bool
        @Environment(\.isFocused) private var isFocused
        @Environment(\.dynamicAccent) private var accent

        private var active: Bool {
            #if os(tvOS)
            return isFocused
            #else
            return configuration.isPressed
            #endif
        }

        private var background: some ShapeStyle {
            #if os(tvOS)
            // Apple TV app style: the focused button fills white; unfocused stays a
            // dim translucent pill. Prominent buttons are white when focused too.
            if active { return AnyShapeStyle(Color.white) }
            if prominent { return AnyShapeStyle(Color.white.opacity(0.24)) }
            return AnyShapeStyle(Color.white.opacity(0.12))
            #else
            if prominent {
                if Theme.uiStyle == .refined {
                    return AnyShapeStyle(
                        LinearGradient(colors: [accent, accent.opacity(0.82)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                }
                return AnyShapeStyle(accent)
            }
            return AnyShapeStyle(active ? accent.opacity(0.9) : Theme.Colors.card)
            #endif
        }

        private var foreground: Color {
            #if os(tvOS)
            return active ? .black : .white
            #else
            if prominent { return .white }
            return active ? .white : Theme.Colors.textPrimary
            #endif
        }

        var body: some View {
            let refined = Theme.uiStyle == .refined
            return configuration.label
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, refined ? Theme.Spacing.md : Theme.Spacing.sm)
                .background(background)
                .foregroundStyle(foreground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                #if os(tvOS)
                .shadow(color: .black.opacity(active ? 0.55 : 0), radius: active ? 18 : 0, y: active ? 10 : 0)
                #else
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .stroke(active ? accent : (refined && !prominent ? Color.white.opacity(0.06) : .clear),
                                lineWidth: active ? 3 : 1)
                )
                .shadow(color: prominent && refined ? accent.opacity(0.35) : (active ? accent.opacity(0.45) : .clear),
                        radius: prominent && refined ? 14 : (active ? 20 : 0),
                        y: prominent && refined ? 5 : (active ? 6 : 0))
                #endif
                .scaleEffect(active ? 1.06 : 1.0)
                .animation(.easeOut(duration: 0.18), value: active)
        }
    }
}
