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
        .background(Theme.Colors.appBackground.ignoresSafeArea())
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
                Text(capabilityText(for: addon))
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
                    .padding(.vertical, Theme.Spacing.xs)
                    .contentShape(Rectangle())
                }
                .frameRowStyle()
            }
        }
        .padding(.top, Theme.Spacing.md)
    }

    /// Translates an addon's technical resource list into a plain-language summary of
    /// what it does for the user, e.g. "Provides catalogs, streams, and subtitles".
    private func capabilityText(for addon: InstalledAddon) -> String {
        var parts: [String] = []
        if addon.resources.contains("catalog") { parts.append("catalogs") }
        if addon.resources.contains("stream")  { parts.append("streams") }
        if addon.resources.contains("meta")    { parts.append("info") }
        if addon.resources.contains("subtitles") { parts.append("subtitles") }
        guard !parts.isEmpty else { return "No content types reported" }
        let list: String
        switch parts.count {
        case 1: list = parts[0]
        case 2: list = "\(parts[0]) and \(parts[1])"
        default:
            list = parts.dropLast().joined(separator: ", ") + ", and " + parts.last!
        }
        return "Provides " + list
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

                // Setup steps for this preset.
                if let preset {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        ForEach(Array(preset.steps.enumerated()), id: \.offset) { idx, step in
                            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                                Text("\(idx + 1)")
                                    .font(.appFont(15, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 26, height: 26)
                                    .background(Theme.Colors.accent, in: Circle())
                                Text(step)
                                    .font(.appFont(18))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                    // One-tap install when this preset has a public instance.
                    if let direct = preset.directURL, let directURL = URL(string: direct) {
                        FocusableButton(title: isInstalling ? "Installing…" : "Quick Add \(preset.displayName)",
                                        systemImage: "bolt.fill", prominent: true) {
                            install(directURL)
                        }
                        .frame(maxWidth: Theme.isCompact ? .infinity : 320)
                        .disabled(isInstalling)

                        Text("Or paste a custom URL below.")
                            .font(.appFont(15))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }

                TextField(preset?.placeholderURL ?? "https://…/manifest.json", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.appFont(22))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    #endif

                if let errorMessage {
                    Text(errorMessage)
                        .font(.appFont(18))
                        .foregroundStyle(Theme.Colors.error)
                }

                FocusableButton(title: isInstalling ? "Installing…" : "Install",
                                systemImage: "square.and.arrow.down",
                                prominent: preset?.directURL == nil) {
                    install()
                }
                .frame(maxWidth: Theme.isCompact ? .infinity : 320)
                .disabled(isInstalling || normalizedURL == nil)
            }
            .padding(Theme.Spacing.edge)
            .frame(maxWidth: Theme.contentMaxWidth(1000), alignment: .leading)
        }
        .background(Theme.Colors.appBackground.ignoresSafeArea())
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

    private func install(_ explicitURL: URL? = nil) {
        guard let url = explicitURL ?? normalizedURL else { return }
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
