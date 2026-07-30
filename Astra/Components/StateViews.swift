//
//  StateViews.swift
//  Astra
//
//  Reusable loading / empty / error state views used across screens.
//

import SwiftUI

// MARK: - Loading

struct LoadingView: View {
    var message: String = "Loading…"

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .scaleEffect(1.6)
                .tint(Theme.Colors.accent)
            Text(message)
                .font(.appFont(22))
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xl)
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
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(message)
                .font(.appFont(20))
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
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
            Text(title)
                .font(.appFont(30, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(message)
                .font(.appFont(20))
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: Theme.isCompact ? 360 : 720)

            VStack(spacing: Theme.Spacing.sm) {
                if let onPrimary, let primaryTitle {
                    FocusableButton(title: primaryTitle, systemImage: "forward.fill",
                                    prominent: true, action: onPrimary)
                        .frame(maxWidth: Theme.isCompact ? .infinity : 320)
                }
                HStack(spacing: Theme.Spacing.md) {
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
            EmptyStateView(systemImage: "exclamationmark.triangle", title: title,
                           message: message, actionTitle: actionTitle, action: action)
        }
    }
}
