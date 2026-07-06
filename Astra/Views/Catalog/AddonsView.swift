//
//  AddonsView.swift
//  Astra
//
//  Manage Stremio-protocol addons: install by manifest URL, quick-add presets for
//  AIOStreams and Comet, enable/disable, and remove. Astra ships no addons itself;
//  everything here is user-supplied.
//

import SwiftUI
#if os(iOS)
import UniformTypeIdentifiers
#endif
#if os(iOS)
import UIKit
#endif

/// Signals that an addon install exceeded the client-side ceiling.
private enum AddonInstallTimeout: Error { case timedOut }

struct AddonsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var showAdd = false
    @State private var health: [UUID: AddonStore.Health] = [:]
    @State private var isChecking = false
    #if os(iOS)
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDoc: AddonExportDocument?
    #endif

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
                            .contextMenu {
                                // Assign this addon to a category (or clear it). New
                                // categories are created by picking any suggestion or
                                // reusing one already in use.
                                Menu {
                                    ForEach(categorySuggestions(for: addon), id: \.self) { name in
                                        Button {
                                            store.setCategory(name, for: addon)
                                        } label: {
                                            if addon.category == name {
                                                Label(name, systemImage: "checkmark")
                                            } else {
                                                Text(name)
                                            }
                                        }
                                    }
                                    if addon.category != nil {
                                        Divider()
                                        Button(role: .destructive) {
                                            store.setCategory(nil, for: addon)
                                        } label: { Label("Clear Category", systemImage: "xmark") }
                                    }
                                } label: {
                                    Label(addon.category.map { "Category: \($0)" } ?? "Set Category",
                                          systemImage: "folder")
                                }
                                if let category = addon.category {
                                    Button {
                                        store.setEnabledForCategory(category, true)
                                    } label: { Label("Enable All in \(category)", systemImage: "checkmark.circle") }
                                    Button {
                                        store.setEnabledForCategory(category, false)
                                    } label: { Label("Disable All in \(category)", systemImage: "circle.slash") }
                                }
                            }
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
        #if os(iOS)
        .fileExporter(isPresented: $showExporter,
                      document: exportDoc,
                      contentType: .json,
                      defaultFilename: "Astra-Addons") { _ in }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                Task {
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url) {
                        _ = await store.importData(data)
                    }
                }
            }
        }
        #endif
    }

    private var header: some View {
        ScreenHeader(title: "Addons", subtitle: "Stream sources you've installed") {
            HStack(spacing: Theme.Spacing.sm) {
                if !store.addons.isEmpty {
                    FocusableButton(title: isChecking ? "Checking…" : "Health",
                                    systemImage: "stethoscope") {
                        runHealthCheck()
                    }
                    #if os(iOS)
                    Menu {
                        Button {
                            if let data = try? store.exportData() {
                                exportDoc = AddonExportDocument(data: data)
                                showExporter = true
                            }
                        } label: { Label("Export Addons", systemImage: "square.and.arrow.up") }
                        Button {
                            showImporter = true
                        } label: { Label("Import Addons", systemImage: "square.and.arrow.down") }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                            .font(.appFont(22))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    #endif
                }
                FocusableButton(title: "Add", systemImage: "plus", prominent: true) {
                    showAdd = true
                }
                .frame(maxWidth: Theme.isCompact ? .infinity : 200)
            }
        }
    }


    /// Category options offered in the context menu: any categories already in use
    /// plus a few sensible defaults, deduplicated and sorted.
    private func categorySuggestions(for addon: InstalledAddon) -> [String] {
        var set = Set(store.categories)
        for base in ["Movies", "TV Shows", "Live TV", "Anime"] { set.insert(base) }
        if let current = addon.category { set.insert(current) }
        return set.sorted()
    }

    private func runHealthCheck() {
        isChecking = true
        Task {
            let result = await store.checkHealth()
            await MainActor.run {
                health = result
                isChecking = false
            }
        }
    }

    private func addonRow(_ addon: InstalledAddon) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.appFont(28))
                    .foregroundStyle(addon.isEnabled ? Theme.Colors.accent : Theme.Colors.textTertiary)
                if let h = health[addon.id] {
                    Circle()
                        .fill(healthColor(h))
                        .frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Theme.Colors.appBackground, lineWidth: 2))
                        .offset(x: 4, y: 2)
                }
            }
            .frame(width: 56)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(addon.name)
                        .font(.appFont(24, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if let category = addon.category {
                        Text(category)
                            .font(.appFont(13, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .overlay(Capsule().strokeBorder(Theme.Colors.accent.opacity(0.5), lineWidth: 1))
                    }
                }
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
        .softCard()
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
                .astraRowStyle()
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
                    .softCard()

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

                HStack(spacing: Theme.Spacing.sm) {
                    TextField(preset?.placeholderURL ?? "https://…/manifest.json", text: $urlText)
                        .textFieldStyle(.plain)
                        .font(.appFont(22))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .textSelection(.enabled)
                        #endif
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                        )
                    #if os(iOS)
                    PasteButton(text: $urlText)
                    #endif
                }

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
        var text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // Some aggregators (AIOStreams, Comet) hand the user only an opaque config
        // id from their configure page. If the field holds a bare token and this
        // preset has a known host, expand it into a real manifest URL so the install
        // doesn't hang resolving the token as a hostname.
        let looksBare = !text.lowercased().hasPrefix("http") && !text.contains("/") && !text.contains(".")
        if looksBare, let host = preset?.hostForBareConfig {
            text = "\(host)/\(text)/manifest.json"
        } else {
            if !text.lowercased().hasPrefix("http") { text = "https://" + text }
            text = text.replacingOccurrences(of: "stremio://", with: "https://")
            if !text.lowercased().hasSuffix("manifest.json") {
                if !text.hasSuffix("/") { text += "/" }
                text += "manifest.json"
            }
        }
        return URL(string: text)
    }

    private func install(_ explicitURL: URL? = nil) {
        guard let url = explicitURL ?? normalizedURL else { return }
        isInstalling = true
        errorMessage = nil
        Task {
            do {
                // Race the install against a hard 25s ceiling so the button can never
                // stick on Installing if the network stalls beyond the request timeout.
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { _ = try await env.addonStore.install(manifestURL: url) }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 25_000_000_000)
                        throw AddonInstallTimeout.timedOut
                    }
                    try await group.next()
                    group.cancelAll()
                }
                await MainActor.run { isInstalling = false; dismiss() }
            } catch is CancellationError {
                await MainActor.run { isInstalling = false }
            } catch AddonInstallTimeout.timedOut {
                await MainActor.run {
                    isInstalling = false
                    errorMessage = "That took too long. Check the URL is a full manifest link and the instance is reachable."
                }
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

// MARK: - Addon health color + export document

extension AddonsView {
    func healthColor(_ h: AddonStore.Health) -> Color {
        switch h {
        case .reachable:      return Theme.Colors.success
        case .broken:         return Theme.Colors.error
        case .checking:       return Theme.Colors.warning
        case .unknown:        return Theme.Colors.textTertiary
        }
    }
}

#if os(iOS)
/// A tiny JSON document used by the file exporter to save the addon config.
struct AddonExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif
