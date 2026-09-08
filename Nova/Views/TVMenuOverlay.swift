#if os(tvOS)
import SwiftUI

/// A compact floating menu. Only this panel participates in focus while open;
/// the active screen stays visible behind it without shifting its artwork.
struct TVMenuOverlay: View {
    @Binding var selection: AppTab
    var onDismiss: () -> Void
    var onRemote: () -> Void
    @Namespace private var menuScope
    @FocusState private var focused: String?
    private let tabs: [AppTab] = [.home, .discover, .library, .settings]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.08).ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 4) {
                menuRow("Remote", symbol: "appletvremote.gen1", id: "remote", action: onRemote)
                ForEach(tabs, id: \.self) { tab in
                    menuRow(tab.title, symbol: symbol(for: tab), id: tab.title) {
                        selection = tab
                        onDismiss()
                    }
                }
            }
            .padding(10)
            .frame(width: 344)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .background(Color.black.opacity(0.50), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 30, y: 12)
            .padding(.leading, 44).padding(.top, 32)
            .focusSection()
        }
        .ignoresSafeArea()
        .focusScope(menuScope)
        .onAppear { focused = tabs.contains(selection) ? selection.title : AppTab.home.title }
        .onExitCommand(perform: onDismiss)
        .accessibilityIdentifier("tv.navigation.menu")
    }

    private func menuRow(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Image(systemName: symbol).font(.system(size: 28, weight: .medium)).frame(width: 36)
                Text(title).font(.system(size: 26, weight: .semibold))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).frame(height: 74)
        }
        .buttonStyle(TVMenuRowStyle())
        .focused($focused, equals: id)
        .prefersDefaultFocus(id == selection.title, in: menuScope)
        .accessibilityIdentifier("tv.navigation.\(id.lowercased())")
    }

    private func symbol(for tab: AppTab) -> String {
        switch tab {
        case .home: return "house"
        case .discover: return "magnifyingglass"
        case .library: return "books.vertical"
        case .settings: return "gearshape"
        case .ai: return "sparkles"
        }
    }
}

private struct TVMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Row(configuration: configuration) }
    private struct Row: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            configuration.label
                .foregroundStyle(focused ? Color(white: 0.10) : .white)
                .background(focused ? Color(white: 0.94) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .opacity(configuration.isPressed ? 0.85 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: focused)
        }
    }
}

struct TVRemoteHelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Label("Remote", systemImage: "appletvremote.gen1").font(.system(size: 38, weight: .semibold))
            Text("Move through Nova with the clickpad or directional buttons. Press the center to choose a title or action.")
            Label("Back: return from a title, or open the menu from a main page. Press Back again to close the menu.", systemImage: "chevron.left")
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
