//
//  LibraryQualityView.swift
//  Nova
//
//  Scans the library and reports what is missing or broken (posters, matches, runtime,
//  season art, unavailable sources), then offers a one-tap "Fix all possible" that
//  backfills artwork and metadata for items that can be resolved from TMDB.
//

import SwiftUI

struct LibraryQualityView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var env: AppEnvironment

    @State private var fixing = false
    @State private var fixedCount = 0

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Library Health")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("A quick scan of your library for anything missing or broken.")
                        .font(.appFont(18))
                        .foregroundStyle(Theme.Colors.textSecondary)

                    let report = scan()

                    if report.allClear {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.Colors.success)
                            Text("Everything looks good. No issues found.")
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        .font(.appFont(20))
                        .padding(Theme.Spacing.md)
                        .refinedCardBackground()
                    } else {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            row("photo", "\(report.missingPosters) items missing posters", report.missingPosters)
                            row("questionmark.square.dashed", "\(report.unmatched) items not matched to a title", report.unmatched)
                            row("clock", "\(report.missingRuntime) items have no runtime", report.missingRuntime)
                            row("rectangle.on.rectangle", "\(report.missingBackdrop) items missing backdrop art", report.missingBackdrop)
                        }
                        .padding(Theme.Spacing.md)
                        .refinedCardBackground()

                        if fixedCount > 0 {
                            Text("Fixed \(fixedCount) item\(fixedCount == 1 ? "" : "s").")
                                .font(.appFont(16))
                                .foregroundStyle(Theme.Colors.success)
                        }

                        FocusableButton(
                            title: fixing ? "Fixing…" : "Fix all possible",
                            systemImage: "wand.and.stars",
                            prominent: true
                        ) {
                            Task { await fixAll() }
                        }
                        .disabled(fixing || !env.tmdb.hasKey)
                        .frame(maxWidth: Theme.isCompact ? .infinity : 360)

                        if !env.tmdb.hasKey {
                            Text("Add a TMDB key in Settings to enable automatic fixes.")
                                .font(.appFont(15))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                }
                .padding(Theme.Spacing.edge)
                .frame(maxWidth: Theme.contentMaxWidth(1000), alignment: .leading)
            }
        }
    }

    private func row(_ icon: String, _ text: String, _ count: Int) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(count > 0 ? Color.orange : Theme.Colors.textTertiary)
                .frame(width: 30)
            Text(text)
                .foregroundStyle(count > 0 ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
            Spacer()
        }
        .font(.appFont(18))
    }

    // MARK: - Scan

    struct Report {
        var missingPosters = 0
        var unmatched = 0
        var missingRuntime = 0
        var missingBackdrop = 0
        var allClear: Bool {
            missingPosters == 0 && unmatched == 0 && missingRuntime == 0 && missingBackdrop == 0
        }
    }

    private func scan() -> Report {
        var r = Report()
        for item in library.items {
            if item.posterURL == nil { r.missingPosters += 1 }
            if item.contentID?.tmdb == nil { r.unmatched += 1 }
            if item.duration == nil { r.missingRuntime += 1 }
            if item.backdropURL == nil { r.missingBackdrop += 1 }
        }
        return r
    }

    private func fixAll() async {
        guard env.tmdb.hasKey else { return }
        fixing = true
        var fixed = 0
        for item in library.items {
            // Only items we can resolve: need a TMDB id (or an IMDB id to resolve one).
            var tmdbID = item.contentID?.tmdb
            let isMovie = item.contentID?.type == .movie
            if tmdbID == nil, let imdb = item.contentID?.imdb {
                tmdbID = try? await env.tmdb.tmdbID(forIMDB: imdb, isMovie: isMovie)
            }
            guard let tmdb = tmdbID else { continue }
            guard let art = try? await env.tmdb.artwork(tmdbID: tmdb, isMovie: isMovie) else { continue }
            var updated = item
            var changed = false
            if updated.posterURL == nil, let p = art.poster { updated.posterURL = p; changed = true }
            if updated.backdropURL == nil, let b = art.backdrop { updated.backdropURL = b; changed = true }
            if updated.contentID?.tmdb == nil { updated.contentID?.tmdb = tmdb; changed = true }
            if changed { library.update(updated); fixed += 1 }
        }
        fixedCount = fixed
        fixing = false
    }
}
