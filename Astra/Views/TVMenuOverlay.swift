//
//  TVMenuOverlay.swift
//  Astra
//
//  tvOS-only. Summoned by the Menu / TV button, styled like the Apple TV app's
//  top tab bar: a translucent capsule bar pinned near the top of the screen with
//  text pills for each section. The focused pill fills white with black text;
//  the current section shows a subtle underline marker when unfocused.
//

#if os(tvOS)
import SwiftUI

struct TVMenuOverlay: View {
    @Binding var selection: AppTab
    var onDismiss: () -> Void

    @Namespace private var menuScope
    @FocusState private var focusedTab: AppTab?

    var body: some View {
        ZStack(alignment: .top) {
            // Dim and blur the content behind so the bar reads as a layer above,
            // exactly like the system tab bar treatment.
            LinearGradient(colors: [.black.opacity(0.72), .black.opacity(0.25), .clear],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            // The Apple-TV-style top bar: one capsule row of text pills.
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    tabPill(tab)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 30, y: 14)
            .padding(.top, Theme.Spacing.xl)
            .focusSection()
        }
        // Confine the tvOS focus engine to this overlay so the content behind it
        // can't receive focus or remote movement.
        .focusScope(menuScope)
        // Pressing Menu again while the bar is up dismisses it.
        .onExitCommand { onDismiss() }
        // Land focus on the current section as soon as the bar appears.
        .onAppear { focusedTab = selection }
        // If focus ever escapes to nil while the bar is open, pull it back.
        .onChange(of: focusedTab) { _, newValue in
            if newValue == nil { focusedTab = selection }
        }
    }

    private func tabPill(_ tab: AppTab) -> some View {
        Button {
            selection = tab
            onDismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.systemImage)
                    .font(.appFont(22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(tab.title)
                    .font(.appFont(24, weight: .semibold))
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .contentShape(Capsule())
        }
        .buttonStyle(TVTabPillStyle(isSelected: tab == selection))
        .focused($focusedTab, equals: tab)
        // The current section is the default focus target when the bar opens.
        .prefersDefaultFocus(tab == selection, in: menuScope)
    }
}

/// Apple TV app tab pill: focused = white fill, black text, gentle lift; the
/// active-but-unfocused section keeps a soft white wash so it reads as current.
private struct TVTabPillStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        TVTabPillBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct TVTabPillBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .foregroundStyle(isFocused ? .black : (isSelected ? .white : Color.white.opacity(0.65)))
            .background(
                Capsule().fill(isFocused ? Color.white
                               : (isSelected ? Color.white.opacity(0.16) : Color.clear))
            )
            .shadow(color: isFocused ? Color.black.opacity(0.5) : .clear,
                    radius: isFocused ? 18 : 0, y: isFocused ? 8 : 0)
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}
#endif
