//
//  SourceCard.swift
//  Astra
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
    let action: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.appFont(34, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.Colors.accent)
                    Spacer()
                    Image(systemName: status.systemImage)
                        .foregroundStyle(status.color)
                        .font(.appFont(24))
                }

                Spacer()

                Text(title)
                    .font(Theme.Font.cardTitle())
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 8, height: 8)
                    Text(statusLine)
                        .font(.appFont(15))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: Theme.CardSize.sourceHeight,
                   alignment: .topLeading)
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.largeCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.largeCard, style: .continuous)
                    .stroke(focused ? Theme.Colors.accent : Theme.Colors.separator,
                            lineWidth: focused ? 4 : 1)
            )
        }
        .buttonStyle(.pressable)
        .focused($focused)
        // Accessibility: speak the card as one element — name plus connection status.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(statusLine)")
        .accessibilityAddTraits(.isButton)
        .scaleEffect(focused ? Theme.CardSize.focusScale : 1.0)
        .animation(.easeOut(duration: 0.16), value: focused)
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
