//
//  TVMenuOverlay.swift
//  Nova
//
//  tvOS-only. Summoned by the Menu / TV button, styled like the Apple TV app's top
//  tab bar: a translucent capsule bar pinned near the top with text pills per
//  section. The focused pill fills white with black text; the current section shows
//  a soft white wash when unfocused.
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
            LinearGradient(colors: [.black.opacity(0.72), .black.opacity(0.25), .clear],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

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
        .focusScope(menuScope)
        .onExitCommand { onDismiss() }
        .onAppear { focusedTab = selection }
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
            // Slight press-down while the remote click is held, on top of focus lift.
            .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.06 : 1.0))
            .animation(.easeOut(duration: 0.16), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
#endif
