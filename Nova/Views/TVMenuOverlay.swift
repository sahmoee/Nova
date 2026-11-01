#if os(tvOS)
import SwiftUI

/// Omni-style persistent sidebar. It rests as an icon rail (or fully hidden) and
/// expands with labels while it holds focus. Selecting an item switches sections
/// and returns focus to the content; Back from a section root focuses the sidebar.
struct NovaSidebar: View {
    @Binding var selection: AppTab
    @FocusState.Binding var focusedTab: AppTab?
    var onRemoteHelp: () -> Void

    @AppStorage(OmniLayoutKey.sidebarStyle) private var styleRaw = OmniSidebarStyle.rail.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var sidebarScope

    private var tabs: [AppTab] { AppTab.primaryTabs.filter { $0 != .settings } }
    private var expanded: Bool { focusedTab != nil }
    private var style: OmniSidebarStyle { OmniSidebarStyle(rawValue: styleRaw) ?? .rail }

    var body: some View {
        ZStack(alignment: .leading) {
            // Scrim fades the page behind the expanded labels.
            LinearGradient(colors: [.black.opacity(0.92), .black.opacity(0.75), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: expanded ? OmniStyle.sidebarExpandedWidth + 260 : OmniStyle.sidebarRailWidth + 40)
                .opacity(expanded || style == .rail ? 1 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 6) {
                wordmark
                    .padding(.bottom, 34)
                ForEach(tabs, id: \.self) { tab in item(tab) }
                Spacer(minLength: 0)
                item(.settings)
                helpButton
            }
            .padding(.vertical, 54)
            .padding(.horizontal, 22)
            .frame(width: expanded ? OmniStyle.sidebarExpandedWidth : OmniStyle.sidebarRailWidth, alignment: .leading)
            .opacity(expanded || style == .rail ? 1 : 0)
            .focusSection()
        }
        .frame(maxHeight: .infinity, alignment: .leading)
        .focusScope(sidebarScope)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: expanded)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tv.navigation.sidebar")
    }

    private var wordmark: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle")
                .font(.system(size: 30, weight: .semibold))
                .frame(width: 48)
            if expanded {
                Text("Nova")
                    .font(.appFont(36, weight: .semibold, design: .serif))
                    .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .padding(.leading, 8)
        .accessibilityHidden(true)
    }

    private func item(_ tab: AppTab) -> some View {
        let selected = tab == selection
        return Button {
            selection = tab
            focusedTab = nil
        } label: {
            HStack(spacing: 18) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 26, weight: selected ? .bold : .medium))
                    .frame(width: 48)
                if expanded {
                    Text(tab.title)
                        .font(.appFont(26, weight: selected ? .bold : .medium))
                        .lineLimit(1)
                        .transition(.opacity)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: OmniStyle.sidebarItemHeight)
        }
        .buttonStyle(SidebarItemStyle(selected: selected))
        .focused($focusedTab, equals: tab)
        .prefersDefaultFocus(selected, in: sidebarScope)
        .accessibilityIdentifier("tv.navigation.\(tab.title.lowercased())")
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var helpButton: some View {
        Button(action: onRemoteHelp) {
            HStack(spacing: 18) {
                Image(systemName: "appletvremote.gen1")
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 48)
                if expanded {
                    Text("Remote Help").font(.appFont(22, weight: .medium)).transition(.opacity)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 54)
        }
        .buttonStyle(SidebarItemStyle(selected: false))
        .opacity(expanded ? 1 : 0)
        .disabled(!expanded)
        .accessibilityLabel("Remote Help")
    }
}

/// Sidebar rows: the selected section keeps a soft pill; focus fills it white with
/// dark content, matching tvOS system focus.
private struct SidebarItemStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.isFocused) private var focused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(focused ? Color.black : (selected ? Color.white : Color.white.opacity(0.6)))
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(focused ? Color.white : (selected ? Color.white.opacity(0.14) : .clear))
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.14), value: focused)
    }
}

struct TVRemoteHelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Label("Remote", systemImage: "appletvremote.gen1").font(.system(size: 38, weight: .semibold))
            Text("Move through Nova with the clickpad or directional buttons. Press the center to choose a title or action.")
            Label("Back: return from a title, or move to the sidebar from a main page.", systemImage: "chevron.left")
            Label("Play/Pause: control the current video during playback.", systemImage: "playpause")
            Text("For text entry, open Apple TV Remote in your iPhone or iPad Control Center and choose this Apple TV. Both devices must be able to reach each other on your network.")
                .foregroundStyle(.white.opacity(0.72))
            Button("Done") { dismiss() }
                .padding(.top, 10)
                .buttonStyle(TVReferenceButtonStyle())
        }
        .font(.system(size: 26))
        .padding(60).frame(maxWidth: 1200, maxHeight: .infinity, alignment: .center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TVReferenceStyle.canvas.ignoresSafeArea())
        .onExitCommand { dismiss() }
    }
}
#endif
