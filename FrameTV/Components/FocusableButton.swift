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
            if prominent { return AnyShapeStyle(accent) }
            return AnyShapeStyle(active ? accent.opacity(0.9) : Theme.Colors.card)
        }

        private var foreground: Color {
            if prominent { return .white }
            return active ? .white : Theme.Colors.textPrimary
        }

        var body: some View {
            configuration.label
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(background)
                .foregroundStyle(foreground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .stroke(active ? accent : .clear, lineWidth: 3)
                )
                .shadow(color: active ? accent.opacity(0.45) : .clear,
                        radius: active ? 20 : 0, y: active ? 6 : 0)
                .scaleEffect(active ? 1.06 : 1.0)
                .animation(.easeOut(duration: 0.18), value: active)
        }
    }
}
