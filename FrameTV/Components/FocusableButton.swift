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

    @FocusState private var focused: Bool
    @Environment(\.dynamicAccent) private var accent

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: prominent ? .infinity : nil)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .stroke(focused ? accent : .clear, lineWidth: 3)
            )
            .shadow(color: focused ? accent.opacity(0.45) : .clear,
                    radius: focused ? 20 : 0, y: focused ? 6 : 0)
            .scaleEffect(focused ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.18), value: focused)
        }
        .buttonStyle(.plain)
        .focused($focused)
    }

    private var background: some ShapeStyle {
        if prominent {
            return AnyShapeStyle(accent)
        }
        return AnyShapeStyle(focused ? accent.opacity(0.9) : Theme.Colors.card)
    }

    private var foreground: Color {
        if prominent { return .white }
        return focused ? .white : Theme.Colors.textPrimary
    }
}
