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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    var message: String? = nil
    var placeholder: String = ""
    var confirmTitle: String = "Save"
    var initialValue: String = ""
    var onSubmit: (String) -> Void

    @State private var text: String = ""
    @State private var didInitialize = false
    @State private var didSubmit = false
    @State private var showDiscard = false
    @FocusState private var fieldFocused: Bool

    private var trimmed: String { NovaPresentationPolicy.searchQuery(text) }
    private var hasChanges: Bool { didInitialize && text != initialValue }

    var body: some View {
        ScrollView {
          VStack(spacing: Theme.Spacing.lg) {
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
                .accessibilityLabel(placeholder.isEmpty ? title : placeholder)
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Theme.Spacing.md))
                : AnyLayout(HStackLayout(spacing: Theme.Spacing.md))) {
                FocusableButton(title: "Cancel", systemImage: "xmark") { cancel() }
                    .frame(maxWidth: .infinity)
                FocusableButton(title: confirmTitle, systemImage: "checkmark",
                                 prominent: true) { submit() }
                    .frame(maxWidth: .infinity)
                    .disabled(trimmed.isEmpty || didSubmit)
                    .opacity(trimmed.isEmpty ? 0.5 : 1)
            }
            .frame(maxWidth: 480)
          }
          .padding(Theme.Spacing.xl)
          .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.appBackground.ignoresSafeArea())
        .onAppear {
            guard !didInitialize else { return }
            didInitialize = true
            text = initialValue
            #if os(iOS)
            fieldFocused = true
            #endif
        }
        .interactiveDismissDisabled(hasChanges && !didSubmit)
        .confirmationDialog("Discard changes?", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) { fieldFocused = true }
        }
        #if os(tvOS)
        .onExitCommand { cancel() }
        #endif
    }

    private func cancel() {
        if hasChanges { showDiscard = true } else { dismiss() }
    }

    private func submit() {
        guard !trimmed.isEmpty, !didSubmit else { return }
        didSubmit = true
        let entered = trimmed
        dismiss()
        onSubmit(entered)
    }
}
