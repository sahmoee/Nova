//
//  Polish.swift
//  Astra
//
//  Small reusable view modifiers and components that standardize the app's visual
//  language: a card surface, a section header, and an interactive press state for
//  iOS that mirrors the tvOS focus feel.
//

import SwiftUI

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
