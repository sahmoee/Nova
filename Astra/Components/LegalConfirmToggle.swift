//
//  LegalConfirmToggle.swift
//  Astra
//
//  The reusable legal-access confirmation toggle used by Direct URL and Magnet
//  flows. Copy comes from LegalAccessGate so it stays consistent.
//

import SwiftUI

struct LegalConfirmToggle: View {
    @Binding var isOn: Bool
    @FocusState private var focused: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.appFont(30))
                    .foregroundStyle(isOn ? Theme.Colors.accent : Theme.Colors.textSecondary)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(LegalAccessGate.confirmationText)
                        .font(.appFont(22, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(LegalAccessGate.explanation)
                        .font(.appFont(18))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(focused ? Theme.Colors.accent : Theme.Colors.separator,
                            lineWidth: focused ? 3 : 1)
            )
        }
        .buttonStyle(.plain)
        .focused($focused)
    }
}
