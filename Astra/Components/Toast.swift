//
//  Toast.swift
//  Astra
//
//  A lightweight, non-blocking toast for transient messages (e.g. "Added to
//  Library", "Couldn't reach OpenSubtitles") plus a small haptics helper. Attach
//  `.toastHost()` near the root and post messages via the ToastCenter.
//

import SwiftUI

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var systemImage: String = "info.circle"
    var isError: Bool = false
    var duration: Duration = .seconds(2.5)
}

@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()
    @Published var current: ToastMessage?

    private var dismissTask: Task<Void, Never>?

    func show(_ text: String,
              systemImage: String = "checkmark.circle.fill",
              isError: Bool = false,
              duration: Duration = .seconds(2.5)) {
        let msg = ToastMessage(text: text, systemImage: systemImage, isError: isError, duration: duration)
        current = msg
        Haptics.play(isError ? .error : .success)
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: duration)
            if Task.isCancelled { return }
            if current?.id == msg.id {
                withAnimation { current = nil }
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation { current = nil }
    }
}

private struct ToastHost: ViewModifier {
    @ObservedObject private var center = ToastCenter.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let msg = center.current {
                Button {
                    center.dismiss()
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: msg.systemImage)
                            .foregroundStyle(msg.isError ? Theme.Colors.error : Theme.Colors.accent)
                            .accessibilityHidden(true)
                        Text(msg.text)
                            .font(.appFont(18, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "xmark")
                            .font(.appFont(12, weight: .bold))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(msg.text)
                .accessibilityHint("Dismiss notification")
                .accessibilityAddTraits(.updatesFrequently)
                .frame(maxWidth: Theme.isCompact ? 360 : 620)
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.bottom, Theme.Spacing.xl)
                .allowsHitTesting(true)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: center.current)
    }
}

extension View {
    /// Hosts transient toast messages posted to ToastCenter.shared.
    func toastHost() -> some View { modifier(ToastHost()) }
}

// MARK: - Haptics

/// UIKit feedback generators are main-actor-isolated, and haptics are UI feedback
/// fired from view actions, so the whole helper is `@MainActor`.
@MainActor
enum Haptics {
    enum Kind { case success, warning, error, light }
    enum Impact { case light, medium, rigid, soft }

    static func impact(_ style: Impact = .light) {
        #if os(iOS)
        let mapped: UIImpactFeedbackGenerator.FeedbackStyle
        switch style {
        case .light: mapped = .light
        case .medium: mapped = .medium
        case .rigid: mapped = .rigid
        case .soft: mapped = .soft
        }
        UIImpactFeedbackGenerator(style: mapped).impactOccurred()
        #endif
    }

    static func selection() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    static func play(_ kind: Kind) {
        #if os(iOS)
        switch kind {
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        #endif
    }
}
