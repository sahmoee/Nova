//
//  WatchStatsView.swift
//  FrameTV
//
//  Shows personal watch statistics computed from the library.
//

import SwiftUI

struct WatchStatsView: View {
    @EnvironmentObject private var library: LibraryStore

    private var stats: WatchStats { WatchStats.compute(from: library.items) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Watch Stats")
                    .font(Theme.Font.screenTitle())
                    .screenTitleStyle()
                    .foregroundStyle(Theme.Colors.textPrimary)

                let s = stats
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: Theme.Spacing.md)],
                          spacing: Theme.Spacing.md) {
                    statCard(value: "\(s.watchedThisMonth)", label: "Watched this month", icon: "calendar")
                    statCard(value: "\(s.watchedAllTime)", label: "Watched all time", icon: "checkmark.circle")
                    statCard(value: "\(s.inProgress)", label: "In progress", icon: "play.circle")
                    statCard(value: hours(s.totalHoursWatched), label: "Time watched", icon: "clock")
                    statCard(value: "\(s.movies)", label: "Movies", icon: "film")
                    statCard(value: "\(s.shows)", label: "Shows", icon: "tv")
                }

                if let longest = s.longestTitle {
                    detailRow(title: "Longest title", value: "\(longest.title) (\(longest.minutes) min)", icon: "hourglass")
                }
                if let recent = s.mostRecentlyPlayed {
                    detailRow(title: "Last played", value: "\(recent.title) · \(recent.date.formatted(date: .abbreviated, time: .omitted))", icon: "clock.arrow.circlepath")
                }

                Text("Stats are calculated from your library on this device.")
                    .font(.appFont(14))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.top, Theme.Spacing.sm)
            }
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.vertical, Theme.Spacing.xl)
            .frame(maxWidth: Theme.contentMaxWidth(900), alignment: .leading)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }

    private func hours(_ h: Double) -> String {
        if h < 1 { return "\(Int(h * 60))m" }
        return String(format: "%.0fh", h)
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.appFont(22))
                .foregroundStyle(Theme.Colors.accent)
            Text(value)
                .font(.appFont(34, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(label)
                .font(.appFont(15))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func detailRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.appFont(20))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.appFont(15)).foregroundStyle(Theme.Colors.textSecondary)
                Text(value).font(.appFont(18, weight: .medium)).foregroundStyle(Theme.Colors.textPrimary)
            }
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}
