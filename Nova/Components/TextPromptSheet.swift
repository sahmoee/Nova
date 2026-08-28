//
//  TextPromptSheet.swift
//  Nova
//
//  A generic single-field text prompt, presented as a sheet rather than an
//  `.alert` with an embedded TextField. SwiftUI alerts with a TextField compile
//  fine on tvOS but the Siri Remote cannot focus or type into them — the field
//  is visible but functionally dead. A sheet hosting a normal, `.focused()`-bound
//  TextField works correctly on every platform, including tvOS's on-screen
//  keyboard. Use this instead of an alert-hosted TextField anywhere text entry
//  is needed (naming something, entering a code, etc).
//

import SwiftUI

struct TextPromptSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    var message: String? = nil
    var placeholder: String = ""
    var confirmTitle: String = "Save"
    var initialValue: String = ""
    var onSubmit: (String) -> Void

    @State private var text: String = ""
    @FocusState private var fieldFocused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 0)
            Text(title)
                .font(Theme.Font.screenTitle())
                .screenTitleStyle()
                .foregroundStyle(Theme.Colors.textPrimary)
            if let message {
                Text(message)
                    .font(.appFont(17))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
            TextField(placeholder, text: $text)
                .focused($fieldFocused)
                #if os(iOS)
                .autocorrectionDisabled(false)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                #endif
                .font(.appFont(24, weight: .semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
                .onSubmit(submit)
            HStack(spacing: Theme.Spacing.md) {
                FocusableButton(title: "Cancel", systemImage: "xmark") { dismiss() }
                    .frame(maxWidth: .infinity)
                FocusableButton(title: confirmTitle, systemImage: "checkmark",
                                 prominent: true) { submit() }
                    .frame(maxWidth: .infinity)
                    .disabled(trimmed.isEmpty)
                    .opacity(trimmed.isEmpty ? 0.5 : 1)
            }
            .frame(maxWidth: 480)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.appBackground.ignoresSafeArea())
        .onAppear {
            text = initialValue
            #if os(iOS)
            fieldFocused = true
            #endif
        }
    }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        let entered = trimmed
        dismiss()
        onSubmit(entered)
    }
}
