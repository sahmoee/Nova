//
//  TVMenuOverlay.swift
//  FrameTV
//
//  tvOS-only. Replaces the always-visible TabView tab bar with a menu that is
//  summoned by pressing the Menu / TV button on the Siri Remote. The selected
//  screen fills the display; pressing Menu brings up this overlay to switch
//  sections, and choosing one (or pressing Menu again) dismisses it back to the
//  content.
//

#if os(tvOS)
import SwiftUI

struct TVMenuOverlay: View {
    @Binding var selection: AppTab
    var onDismiss: () -> Void

    @Environment(\.dynamicAccent) private var accent
    @Namespace private var menuScope
    @FocusState private var focusedTab: AppTab?

    var body: some View {
        ZStack {
            // Dim the content behind the menu so it reads as a layer on top. This
            // also catches clicks outside the menu to dismiss it.
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.xl) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "film.stack")
                        .font(.appFont(34, weight: .bold))
                        .foregroundStyle(accent)
                    Text("Frame")
                        .font(.appFont(40, weight: .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }

                // The row of tiles is one focus section so left/right movement stays
                // within it and wraps naturally across the four items.
                HStack(spacing: Theme.Spacing.lg) {
                    ForEach(AppTab.allCases, id: \.self) { tab in
                        menuButton(tab)
                    }
                }
                .focusSection()
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.xl)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
        }
        // Confine the tvOS focus engine to this overlay so the content behind it
        // can't receive focus or remote movement.
        .focusScope(menuScope)
        // Pressing Menu again while the overlay is up dismisses it.
        .onExitCommand { onDismiss() }
        // Land focus on the current section as soon as the menu appears.
        .onAppear { focusedTab = selection }
        // If focus ever escapes to nil while the menu is open, pull it back.
        .onChange(of: focusedTab) { _, newValue in
            if newValue == nil { focusedTab = selection }
        }
    }

    private func menuButton(_ tab: AppTab) -> some View {
        Button {
            selection = tab
            onDismiss()
        } label: {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: tab.systemImage)
                    .font(.appFont(40, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(tab.title)
                    .font(.appFont(24, weight: .semibold))
            }
            .frame(width: 220, height: 150)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(TVMenuButtonStyle(isSelected: tab == selection))
        .focused($focusedTab, equals: tab)
        // The current section is the default focus target when the menu opens.
        .prefersDefaultFocus(tab == selection, in: menuScope)
    }
}

/// Focus style for the menu tiles: accent fill + lift on focus, a subtle marker on
/// the currently active section, and no tvOS default white card.
private struct TVMenuButtonStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        TVMenuButtonBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct TVMenuButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    @Environment(\.isFocused) private var isFocused
    @Environment(\.dynamicAccent) private var accent

    var body: some View {
        configuration.label
            .foregroundStyle(isFocused ? .white : (isSelected ? accent : Theme.Colors.textSecondary))
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isFocused ? accent : (isSelected ? accent.opacity(0.18) : Theme.Colors.card))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isSelected && !isFocused ? accent : .clear, lineWidth: 2)
            )
            .shadow(color: isFocused ? accent.opacity(0.45) : .clear,
                    radius: isFocused ? 24 : 0, y: isFocused ? 10 : 0)
            .scaleEffect(isFocused ? 1.07 : 1.0)
            .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}
#endif
