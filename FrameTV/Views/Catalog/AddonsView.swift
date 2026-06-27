//
//  AddonsView.swift
//  FrameTV
//
//  Manage Stremio-protocol addons: install by manifest URL, quick-add presets for
//  AIOStreams and Comet, enable/disable, and remove. FrameTV ships no addons itself;
//  everything here is user-supplied.
//

import SwiftUI

struct AddonsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var showAdd = false

    private var store: AddonStore { env.addonStore }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header

                if store.addons.isEmpty {
                    EmptyStateView(
                        systemImage: "puzzlepiece.extension",
                        title: "No addons yet",
                        message: "Add a Stremio-compatible addon by its manifest URL to find streams. AIOStreams and Comet are supported.",
                        actionTitle: "Add Addon",
                        action: { showAdd = true }
                    )
                    .frame(minHeight: 360)
                } else {
                    ForEach(store.addons) { addon in
                        addonRow(addon)
                    }
                }

                presetSection
            }
            .padding(Theme.Spacing.edge)
            .frame(maxWidth: Theme.contentMaxWidth(1200), alignment: .leading)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .sheet(isPresented: $showAdd) {
            AddAddonView()
        }
    }

    private var header: some View {
        ScreenHeader(title: "Addons", subtitle: "Stream sources you've installed") {
            FocusableButton(title: "Add", systemImage: "plus", prominent: true) {
                showAdd = true
            }
            .frame(maxWidth: Theme.isCompact ? .infinity : 200)
        }
    }

    private func addonRow(_ addon: InstalledAddon) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.appFont(28))
                .foregroundStyle(addon.isEnabled ? Theme.Colors.accent : Theme.Colors.textTertiary)
                .frame(width: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(addon.name)
                    .font(.appFont(24, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(addon.resources.joined(separator: " · "))
                    .font(.appFont(16))
                    .foregroundStyle(Theme.Colors.textTertiary)
                if let desc = addon.description, !desc.isEmpty {
                    Text(desc)
                        .font(.appFont(16))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer()

            Toggle("", isOn: Binding(
                get: { addon.isEnabled },
                set: { store.setEnabled(addon, $0) }
            ))
            .labelsHidden()

            FocusableButton(title: "Remove", systemImage: "trash") {
                store.remove(addon)
            }
            .frame(maxWidth: Theme.isCompact ? .infinity : 200)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Quick Add")
                .font(Theme.Font.sectionTitle())
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("These addons require your own configured instance URL.")
                .font(.appFont(18))
                .foregroundStyle(Theme.Colors.textSecondary)

            ForEach(AddonPreset.allCases) { preset in
                NavigationLink {
                    AddAddonView(preset: preset)
                } label: {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: preset.systemImage)
                            .font(.appFont(26))
                            .foregroundStyle(Theme.Colors.accentSecondary)
                            .frame(width: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preset.displayName)
                                .font(.appFont(22, weight: .semibold))
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(preset.blurb)
                                .font(.appFont(16))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, Theme.Spacing.md)
    }
}

// MARK: - Add addon

struct AddAddonView: View {
    var preset: AddonPreset?

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var isInstalling = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text(preset?.displayName ?? "Add Addon")
                    .font(Theme.Font.screenTitle())
                    .screenTitleStyle()
                    .foregroundStyle(Theme.Colors.textPrimary)

                if let preset {
                    Text(preset.blurb)
                        .font(.appFont(20))
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    Text("Paste the addon's manifest URL (ends in /manifest.json).")
                        .font(.appFont(20))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                TextField(preset?.placeholderURL ?? "https://…/manifest.json", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.appFont(22))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    #if os(iOS)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    #endif

                if let errorMessage {
                    Text(errorMessage)
                        .font(.appFont(18))
                        .foregroundStyle(Theme.Colors.error)
                }

                FocusableButton(title: isInstalling ? "Installing…" : "Install",
                                systemImage: "square.and.arrow.down",
                                prominent: true) {
                    install()
                }
                .frame(maxWidth: Theme.isCompact ? .infinity : 320)
                .disabled(isInstalling || normalizedURL == nil)
            }
            .padding(Theme.Spacing.edge)
            .frame(maxWidth: Theme.contentMaxWidth(1000), alignment: .leading)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }

    private var normalizedURL: URL? {
        var s = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        if !s.lowercased().hasSuffix("manifest.json") {
            if !s.hasSuffix("/") { s += "/" }
            s += "manifest.json"
        }
        return URL(string: s)
    }

    private func install() {
        guard let url = normalizedURL else { return }
        isInstalling = true
        errorMessage = nil
        Task {
            do {
                _ = try await env.addonStore.install(manifestURL: url)
                await MainActor.run { isInstalling = false; dismiss() }
            } catch {
                await MainActor.run {
                    isInstalling = false
                    errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? "Couldn't install that addon. Check the URL."
                }
            }
        }
    }
}
