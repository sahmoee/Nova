//
//  DirectURLView.swift
//  FrameTV
//
//  Paste a direct video URL, validate it, add it to the library, and play.
//  This flow is fully functional in Phase 2.
//

import SwiftUI

struct DirectURLView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore

    @State private var urlText = ""
    @State private var titleText = ""
    @State private var posterText = ""
    @State private var legalConfirmed = false

    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var addedItem: MediaItem?

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Direct URL")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Paste a direct link to a video file you own or are authorized to access.")
                        .font(.appFont(22))
                        .foregroundStyle(Theme.Colors.textSecondary)

                    field("Video URL", text: $urlText, placeholder: "https://example.com/video.mp4")
                    field("Title (optional)", text: $titleText, placeholder: "My Video")
                    field("Poster URL (optional)", text: $posterText, placeholder: "https://example.com/poster.jpg")

                    if settings.requireLegalConfirmation {
                        LegalConfirmToggle(isOn: $legalConfirmed)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Colors.error)
                            .font(.appFont(20))
                    }

                    HStack(spacing: Theme.Spacing.md) {
                        FocusableButton(
                            title: isWorking ? "Checking…" : "Add & Play",
                            systemImage: "play.fill",
                            prominent: true
                        ) {
                            Task { await addAndPlay() }
                        }
                        .frame(maxWidth: Theme.isCompact ? .infinity : 320)
                        .disabled(isWorking || !canSubmit)

                        FocusableButton(title: "Add to Library", systemImage: "plus") {
                            Task { await addOnly() }
                        }
                        .frame(maxWidth: Theme.isCompact ? .infinity : 320)
                        .disabled(isWorking || !canSubmit)
                    }
                }
                .padding(Theme.Spacing.edge)
                .frame(maxWidth: Theme.contentMaxWidth(1100), alignment: .leading)
            }
        }
        .navigationDestination(item: $addedItem) { item in
            PlayerView(item: item)
        }
        .dismissKeyboardOnTap()
    }

    private var canSubmit: Bool {
        guard !urlText.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if settings.requireLegalConfirmation { return legalConfirmed }
        return true
    }

    // MARK: - Field

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label)
                .font(.appFont(20, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    // MARK: - Actions

    private func addAndPlay() async {
        guard let item = await buildItem() else { return }
        library.add(item)
        addedItem = item
    }

    private func addOnly() async {
        guard let item = await buildItem() else { return }
        library.add(item)
        // Reset the form on success.
        urlText = ""; titleText = ""; posterText = ""; legalConfirmed = false
    }

    /// Validates and constructs a MediaItem, surfacing any error inline.
    private func buildItem() async -> MediaItem? {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        do {
            let url = try await environment.directURL.validate(urlText)
            let poster = URL(string: posterText.trimmingCharacters(in: .whitespaces))
            return await environment.directURL.makeMediaItem(
                url: url,
                title: titleText,
                posterURL: poster,
                legalAccessConfirmed: legalConfirmed || !settings.requireLegalConfirmation
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }
}
