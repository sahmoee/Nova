//
//  GuestModeView.swift
//  Nova
//
//  Lightweight shared-device mode. When on, source setup, magnets/direct URLs, and
//  advanced settings are hidden across the app, leaving the library and playback. An
//  optional PIN is required to turn guest mode back off.
//

import SwiftUI

struct GuestModeView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var enteredPIN = ""
    @State private var newPIN = ""
    @State private var showPINError = false

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Guest Mode")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("For shared TVs. Hides source setup, magnets, direct URLs, and advanced settings, leaving just your library and playback.")
                        .font(.appFont(18))
                        .foregroundStyle(Theme.Colors.textSecondary)

                    if settings.guestMode {
                        activePanel
                    } else {
                        setupPanel
                    }
                }
                .padding(Theme.Spacing.edge)
                .frame(maxWidth: Theme.contentMaxWidth(900), alignment: .leading)
            }
        }
    }

    // Turning guest mode ON, optionally setting a PIN.
    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Optional PIN to exit")
                .font(.appFont(20, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            SecureField("4-digit PIN (leave blank for none)", text: $newPIN)
                .textFieldStyle(.plain)
                .font(.appFont(22))
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(Theme.Spacing.md)
                .refinedCardBackground()
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif

            FocusableButton(title: "Turn On Guest Mode", systemImage: "person.2", prominent: true) {
                let trimmed = newPIN.filter(\.isNumber)
                settings.guestPIN = trimmed.count == 4 ? trimmed : ""
                settings.guestMode = true
                dismiss()
            }
            .frame(maxWidth: Theme.isCompact ? .infinity : 360)
        }
        .padding(Theme.Spacing.lg)
        .refinedCardBackground()
    }

    // Turning guest mode OFF, PIN-gated if one was set.
    private var activePanel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Label("Guest mode is on", systemImage: "person.2.fill")
                .font(.appFont(22, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)

            if settings.guestPIN.isEmpty {
                FocusableButton(title: "Turn Off Guest Mode", systemImage: "lock.open") {
                    settings.guestMode = false
                    dismiss()
                }
                .frame(maxWidth: Theme.isCompact ? .infinity : 360)
            } else {
                Text("Enter your PIN to turn off guest mode.")
                    .font(.appFont(18))
                    .foregroundStyle(Theme.Colors.textSecondary)
                SecureField("PIN", text: $enteredPIN)
                    .textFieldStyle(.plain)
                    .font(.appFont(22))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(Theme.Spacing.md)
                    .refinedCardBackground()
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                if showPINError {
                    Text("Incorrect PIN.")
                        .font(.appFont(16))
                        .foregroundStyle(Theme.Colors.error)
                }
                FocusableButton(title: "Unlock", systemImage: "lock.open") {
                    if enteredPIN.filter(\.isNumber) == settings.guestPIN {
                        settings.guestMode = false
                        settings.guestPIN = ""
                        dismiss()
                    } else {
                        showPINError = true
                        enteredPIN = ""
                    }
                }
                .frame(maxWidth: Theme.isCompact ? .infinity : 360)
            }
        }
        .padding(Theme.Spacing.lg)
        .refinedCardBackground()
    }
}
