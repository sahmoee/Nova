//
//  PersonalMediaDisclosureView.swift
//  Nova
//
//  Shown once on first launch. Sets clear expectations that Nova is a player and
//  library manager for media the user owns or is authorized to access, and that it
//  does not include, host, index, or provide any content. Dismissed by "I understand",
//  which records acceptance so it never shows again.
//

import SwiftUI

struct PersonalMediaDisclosureView: View {
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Spacer(minLength: Theme.Spacing.xl)

                    Image(systemName: "play.rectangle.on.rectangle")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)

                    Text("Welcome to Nova")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("A player and library manager for your media")
                        .font(.appFont(22, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)

                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        point(icon: "person.crop.circle",
                              text: "Nova plays media you own, control, or are authorized to access.")
                        point(icon: "xmark.circle",
                              text: "Nova does not include, sell, host, index, or provide any video content.")
                        point(icon: "slider.horizontal.3",
                              text: "You add your own accounts, network shares, and sources. Nothing is bundled.")
                        point(icon: "lock.shield",
                              text: "Your library and settings stay on your device. Credentials are stored in the system Keychain.")
                    }
                    .padding(Theme.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                    Text("By continuing you confirm you will only use Nova with media you are authorized to access.")
                        .font(.appFont(15))
                        .foregroundStyle(Theme.Colors.textTertiary)

                    FocusableButton(title: "I understand", systemImage: "checkmark") {
                        onContinue()
                    }
                    .padding(.top, Theme.Spacing.sm)

                    Spacer(minLength: Theme.Spacing.xl)
                }
                .padding(Theme.Spacing.edge)
                .frame(maxWidth: Theme.contentMaxWidth(720), alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func point(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.appFont(22, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 32)
            Text(text)
                .font(.appFont(19))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
