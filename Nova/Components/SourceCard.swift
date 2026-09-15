//
//  SourceCard.swift
//  Nova
//
//  Card representing a configured source, showing connection status, last sync,
//  and an error indicator.
//

import SwiftUI

enum SourceStatus: Equatable {
    case connected
    case disconnected
    case error(String)
    case notConfigured

    var label: String {
        switch self {
        case .connected:     return "Connected"
        case .disconnected:  return "Not connected"
        case .error:         return "Error"
        case .notConfigured: return "Not set up"
        }
    }

    var color: Color {
        switch self {
        case .connected:     return Theme.Colors.success
        case .disconnected:  return Theme.Colors.textTertiary
        case .error:         return Theme.Colors.error
        case .notConfigured: return Theme.Colors.textTertiary
        }
    }

    var systemImage: String {
        switch self {
        case .connected:     return "checkmark.circle.fill"
        case .disconnected:  return "circle"
        case .error:         return "exclamationmark.triangle.fill"
        case .notConfigured: return "plus.circle"
        }
    }
}

struct SourceCard: View {
    let title: String
    let systemImage: String
    let status: SourceStatus
    var lastSynced: Date? = nil
    var isInteractive = true
    let action: () -> Void

    @FocusState private var focused: Bool
    @Environment(\.isFocused) private var inheritedFocus
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovered = false
    private var active: Bool { enabled && (focused || inheritedFocus || hovered) }
    private var brightFocus: Bool {
        #if os(tvOS)
        active
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if isInteractive {
                Button(action: action) { cardContent }
                    .buttonStyle(.pressable)
                    .focused($focused)
            } else {
                cardContent
            }
        }
        // Accessibility: speak the card as one element — name plus connection status.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(statusLine)")
        .accessibilityAddTraits(isInteractive ? .isButton : [])
        .accessibilityHint(isInteractive ? "Open source settings" : "")
        .environment(\.colorScheme, brightFocus ? .light : .dark)
        .scaleEffect(enabled && (focused || inheritedFocus) && !reduceMotion ? Theme.CardSize.focusScale : 1.0)
        .shadow(color: .black.opacity(active ? 0.3 : 0.16), radius: active ? 16 : 8, y: active ? 8 : 4)
        // Interactive cards already dim through PressableButtonStyle. Passive
        // NavigationLink labels need the same treatment here, exactly once.
        .opacity(isInteractive || enabled ? 1 : Theme.Control.disabledOpacity)
        .animation(reduceMotion ? nil : Theme.Motion.quick, value: active)
        #if !os(tvOS)
        .onHover { hovered = $0 }
        #endif
        .zIndex(active ? 1 : 0)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.appFont(34, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(brightFocus ? Color.black : Theme.Colors.accent)
                    Spacer()
                    Image(systemName: status.systemImage)
                        .foregroundStyle(brightFocus ? Color.black : status.color)
                        .font(.appFont(24))
                }

                Spacer()

                Text(title)
                    .font(Theme.Font.cardTitle())
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Circle()
                        .fill(brightFocus ? Color.black : status.color)
                        .frame(width: 8, height: 8)
                    Text(statusLine)
                        .font(.appFont(15))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: Theme.CardSize.sourceHeight,
               alignment: .topLeading)
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            if brightFocus || reduceTransparency || contrast == .increased {
                shape.fill(brightFocus ? Color.white : Color(white: 0.16))
            } else {
                shape.fill(Color(white: active ? 0.2 : 0.14).opacity(0.75))
                    .glassEffect(.regular.interactive(), in: shape)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(active ? Theme.Colors.focusRing : .white.opacity(contrast == .increased ? 0.6 : 0.16),
                              lineWidth: active ? Theme.Control.focusLineWidth : 1)
                .allowsHitTesting(false)
        )
    }

    private var statusLine: String {
        if case .error(let message) = status { return message }
        if let lastSynced, status == .connected {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .short
            return "Synced \(f.localizedString(for: lastSynced, relativeTo: Date()))"
        }
        return status.label
    }
}
