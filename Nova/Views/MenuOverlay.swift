//
//  MenuOverlay.swift
//  Nova
//
//  A shared, in-place navigation menu used on iPhone and tvOS (iPad keeps its
//  persistent NavigationSplitView sidebar). It is a slide-over / pop-up panel that
//  overlays the current screen instead of pushing a separate navigation screen: a
//  dimmed backdrop plus a translucent card of section rows that slides in from the
//  leading edge. Picking a section switches to it and dismisses the panel; picking
//  the current section pops it to root.
//
//  On iPhone the panel is summoned by a small floating menu button and can be
//  dismissed by tapping the backdrop. On tvOS it is summoned by the Menu / TV
//  button (handled in RootView) and dismissed with Menu again.
//

import SwiftUI

struct MenuOverlay: View {
    @Binding var selection: AppTab
    var onDismiss: () -> Void
    /// Called when a section is chosen. RootView uses this to always pop that
    /// section's navigation stack back to its root, so pressing a menu button
    /// reliably returns to the section's main screen (never a stale detail screen).
    var onSelect: ((AppTab) -> Void)? = nil

    @Environment(\.dynamicAccent) private var accent
    #if os(tvOS)
    @FocusState private var focusedTab: AppTab?
    #endif

    var body: some View {
        ZStack(alignment: .leading) {
            // Dimmed backdrop. Tapping it closes the panel (iPhone). On tvOS the
            // backdrop is non-interactive; the Menu button closes the panel.
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                #if os(iOS)
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }
                #endif

            panel
                .frame(maxWidth: panelWidth, maxHeight: .infinity, alignment: .top)
                .padding(.vertical, Theme.Spacing.xl)
                .padding(.leading, panelInset)
        }
        #if os(tvOS)
        .onExitCommand { onDismiss() }
        .onAppear { focusedTab = selection }
        #endif
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nova")
                .font(.appFont(Theme.isCompact ? 28 : 30, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)

            ForEach(AppTab.allCases, id: \.self) { tab in
                menuRow(tab)
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 30, x: 8, y: 14)
        )
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    private func menuRow(_ tab: AppTab) -> some View {
        Button {
            if let onSelect {
                onSelect(tab)
            } else {
                selection = tab
            }
            onDismiss()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: tab.systemImage)
                    .font(.appFont(24, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: Theme.isCompact ? 32 : 34)
                Text(tab.title)
                    .font(.appFont(24, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle(isSelected: tab == selection, accent: accent))
        #if os(tvOS)
        .focused($focusedTab, equals: tab)
        #endif
    }

    // MARK: - Metrics

    private var panelWidth: CGFloat {
        #if os(tvOS)
        return 520
        #else
        return 240
        #endif
    }

    private var panelInset: CGFloat {
        #if os(tvOS)
        return Theme.Spacing.xl
        #else
        return Theme.Spacing.md
        #endif
    }
}

/// A row style that highlights the active section and, on tvOS, the focused row
/// (white fill / black text), matching the Apple TV app's menu feel.
private struct MenuRowStyle: ButtonStyle {
    var isSelected: Bool
    var accent: Color

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        MenuRowBody(configuration: configuration, isSelected: isSelected, accent: accent)
    }
}

private struct MenuRowBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    let accent: Color
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    #endif

    var body: some View {
        #if os(tvOS)
        configuration.label
            .foregroundStyle(isFocused ? .black : (isSelected ? .white : Color.white.opacity(0.7)))
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isFocused ? Color.white
                          : (isSelected ? accent.opacity(0.22) : Color.clear))
                    .padding(.horizontal, Theme.Spacing.sm)
            )
            .scaleEffect(isFocused ? 1.03 : 1.0)
            .animation(.easeOut(duration: 0.16), value: isFocused)
        #else
        configuration.label
            .foregroundStyle(isSelected ? accent : Theme.Colors.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.14) : Color.clear)
                    .padding(.horizontal, Theme.Spacing.sm)
            )
            .opacity(configuration.isPressed ? 0.6 : 1.0)
        #endif
    }
}

#if os(iOS)
/// A small floating capsule button that summons the menu overlay on iPhone. Sits
/// above the bottom-leading corner, out of the way of content, and hides while the
/// player is on screen (handled by the caller).
struct MenuButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .bold))
                Text("Menu")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
#endif
