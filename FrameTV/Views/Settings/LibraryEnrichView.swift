//
//  LibraryEnrichView.swift
//  FrameTV
//
//  Options to clean up library titles and fetch missing artwork, with an AI-assisted
//  toggle that uses the configured Worker for smarter title cleanup.
//

import SwiftUI

struct LibraryEnrichView: View {
    @EnvironmentObject private var env: AppEnvironment
    var body: some View { LibraryEnrichContent(enricher: env.libraryEnricher) }
}

private struct LibraryEnrichContent: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var enricher: LibraryEnricher

    @State private var fetchImages = true
    @State private var cleanTitles = true
    @State private var useAI = false

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Clean Up Library")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(.top, Theme.Spacing.lg)

                    Text("Tidy messy filenames into proper titles and fetch missing posters and artwork from TMDB.")
                        .font(.appFont(16))
                        .foregroundStyle(Theme.Colors.textTertiary)

                    optionCard(
                        title: "Fetch Images",
                        subtitle: "Find posters and backdrops for items that are missing artwork.",
                        systemImage: "photo.on.rectangle.angled",
                        isOn: $fetchImages
                    )

                    optionCard(
                        title: "Clean Up Titles",
                        subtitle: "Turn names like \"WALL-E 2008 1080p\" into \"WALL-E\".",
                        systemImage: "textformat",
                        isOn: $cleanTitles
                    )

                    optionCard(
                        title: "Use AI",
                        subtitle: AISearchService.isConfigured
                            ? "Use your AI Worker for smarter title cleanup on tricky filenames."
                            : "Set up AI in Settings to enable smarter title cleanup.",
                        systemImage: "sparkles",
                        isOn: $useAI
                    )
                    .disabled(!AISearchService.isConfigured || !cleanTitles)
                    .opacity((AISearchService.isConfigured && cleanTitles) ? 1 : 0.5)

                    if enricher.isRunning {
                        HStack(spacing: Theme.Spacing.sm) {
                            ProgressView().tint(Theme.Colors.accent)
                            Text(enricher.progress ?? "Working…")
                                .font(.appFont(15))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    } else if let summary = enricher.lastSummary {
                        Label(summary, systemImage: "checkmark.circle.fill")
                            .font(.appFont(15, weight: .medium))
                            .foregroundStyle(Theme.Colors.accent)
                    }

                    FocusableButton(title: "Run Cleanup", systemImage: "wand.and.stars", prominent: true) {
                        let options = LibraryEnricher.Options(
                            fetchImages: fetchImages,
                            cleanTitles: cleanTitles,
                            useAI: useAI && AISearchService.isConfigured
                        )
                        Task { await enricher.enrichLibrary(using: env, options: options) }
                    }
                    .disabled(enricher.isRunning || (!fetchImages && !cleanTitles))
                    .padding(.top, Theme.Spacing.sm)
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.bottom, Theme.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func optionCard(title: String, subtitle: String, systemImage: String,
                            isOn: Binding<Bool>) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.appFont(22))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.appFont(17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(.appFont(14))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Theme.Colors.accent)
        }
        .padding(Theme.Spacing.md)
        .refinedCardBackground()
    }
}
