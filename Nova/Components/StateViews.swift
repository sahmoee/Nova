//
//  StateViews.swift
//  Nova
//
//  Reusable loading / empty / error state views used across screens.
//

import SwiftUI

/// Presentation-only normalization. Stored user data and provider payloads remain unchanged.
enum NovaPresentationPolicy {
    static func searchQuery(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func progress(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }

    static func rateBytes(_ value: Double?) -> Int64? {
        guard let value, value.isFinite, value > 0, value < Double(Int64.max) else { return nil }
        return Int64(value)
    }

    static func unique<Element, ID: Hashable>(_ elements: [Element], by key: KeyPath<Element, ID>) -> [Element] {
        var seen: Set<ID> = []
        return elements.filter { seen.insert($0[keyPath: key]).inserted }
    }
}

// MARK: - Loading

struct LoadingView: View {
    var message: String = "Loading…"
    var systemImage: String = "play.tv.fill"
    @State private var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.18))
                    .frame(width: 88, height: 88)
                    .scaleEffect(reduceMotion ? 1 : (breathing ? 1.12 : 0.94))
                Image(systemName: systemImage)
                    .font(.appFont(34, weight: .semibold))
                    .foregroundStyle(.white)
                ProgressView().tint(.white).offset(y: 56)
            }
            Text(message)
                .font(.appFont(22))
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xl)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .onDisappear { breathing = false }
        .onChange(of: reduceMotion) { _, reduced in
            breathing = false
            guard !reduced else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { breathing = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

// MARK: - Empty

struct EmptyStateView: View {
    var systemImage: String = "tray"
    var title: String
    var message: String
    var actionTitle: String? = nil
    var actionSystemImage: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.appFont(72))
                .foregroundStyle(Theme.Colors.textTertiary)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            Text(title)
                .font(.appFont(30, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.appFont(20))
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: Theme.isCompact ? 360 : 720)
            if let actionTitle, let action {
                FocusableButton(title: actionTitle, systemImage: actionSystemImage, prominent: true, action: action)
                    .frame(maxWidth: Theme.isCompact ? .infinity : 360)
                    .padding(.top, Theme.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xl)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Error

struct ErrorStateView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var title: String = "Something went wrong"
    var message: String
    var retryTitle: String = "Retry"
    /// Optional prominent primary action shown above Retry (e.g. "Try Next Stream").
    var primaryTitle: String? = nil
    var onPrimary: (() -> Void)? = nil
    var onRetry: (() -> Void)? = nil
    var onOpenSettings: (() -> Void)? = nil
    var onBack: (() -> Void)? = nil
    var backTitle: String = "Go Back"

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.appFont(64))
                .foregroundStyle(Theme.Colors.error)
                .accessibilityHidden(true)
            Text(title)
                .font(.appFont(30, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.appFont(20))
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: Theme.isCompact ? 360 : 720)

            VStack(spacing: Theme.Spacing.sm) {
                if let onPrimary, let primaryTitle {
                    FocusableButton(title: primaryTitle, systemImage: "forward.fill",
                                    prominent: true, action: onPrimary)
                        .frame(maxWidth: Theme.isCompact ? .infinity : 320)
                }
                (dynamicTypeSize.isAccessibilitySize || Theme.isCompact
                    ? AnyLayout(VStackLayout(spacing: Theme.Spacing.md))
                    : AnyLayout(HStackLayout(spacing: Theme.Spacing.md))) {
                    if let onRetry {
                        FocusableButton(title: retryTitle, systemImage: "arrow.clockwise",
                                        prominent: onPrimary == nil, action: onRetry)
                            .frame(maxWidth: Theme.isCompact ? .infinity : 280)
                    }
                    if let onOpenSettings {
                        FocusableButton(title: "Open Settings", systemImage: "gearshape",
                                        action: onOpenSettings)
                            .frame(maxWidth: Theme.isCompact ? .infinity : 280)
                    }
                }
                .frame(maxWidth: .infinity)
                if let onBack {
                    FocusableButton(title: backTitle, systemImage: "chevron.left",
                                    action: onBack)
                        .frame(maxWidth: Theme.isCompact ? .infinity : 280)
                }
            }
            .padding(.top, Theme.Spacing.sm)
            .frame(maxWidth: Theme.isCompact ? .infinity : 600)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xl)
        .accessibilityElement(children: .contain)
    }
}


// MARK: - Unified state wrapper

/// One enum-driven view for the loading / empty / error triad, so screens don't
/// hand-assemble slightly different versions of the same three states.
struct ContentStateView: View {
    enum State {
        case loading(message: String = "Loading…")
        case empty(systemImage: String = "tray", title: String, message: String,
                   actionTitle: String? = nil, actionSystemImage: String? = nil, action: (() -> Void)? = nil)
        case error(title: String, message: String,
                   actionTitle: String? = nil, action: (() -> Void)? = nil)
    }

    let state: State

    var body: some View {
        switch state {
        case .loading(let message):
            LoadingView(message: message)
        case .empty(let symbol, let title, let message, let actionTitle, let actionSystemImage, let action):
            EmptyStateView(systemImage: symbol, title: title, message: message,
                           actionTitle: actionTitle, actionSystemImage: actionSystemImage, action: action)
        case .error(let title, let message, let actionTitle, let action):
            ErrorStateView(title: title, message: message, retryTitle: actionTitle ?? "Retry", onRetry: action)
        }
    }
}
