//
//  WatchStatsView.swift
//  Nova
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
                HStack(alignment: .firstTextBaseline) {
                    Text("Watch Stats")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    #if os(iOS)
                    ShareLink(item: statsSummary) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.appFont(17, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    .novaRowStyle()
                    #endif
                }

                let s = stats
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: Theme.Spacing.md)],
                          spacing: Theme.Spacing.md) {
                    statCard(value: "\(s.watchedThisMonth)", label: "Watched this month", icon: "calendar")
                    statCard(value: "\(s.watchedAllTime)", label: "Watched all time", icon: "checkmark.circle")
                    statCard(value: "\(s.inProgress)", label: "In progress", icon: "play.circle")
                    statCard(value: hours(s.totalHoursWatched), label: "Time watched", icon: "clock")
                    statCard(value: "\(s.movies)", label: "Movies", icon: "film")
                    statCard(value: "\(s.shows)", label: "Shows", icon: "tv")
                    statCard(value: "\(s.playedThisWeek)", label: "Played this week", icon: "calendar.badge.clock")
                    statCard(value: s.currentStreak == 1 ? "1 day" : "\(s.currentStreak) days", label: "Current streak", icon: "flame")
                }

                activityChart(s.lastSevenDays)

                if s.bestStreak > 1 {
                    detailRow(title: "Best streak", value: "\(s.bestStreak) days in a row", icon: "trophy")
                }
                if !s.topShows.isEmpty {
                    detailRow(title: "Most-watched shows",
                              value: s.topShows.map { "\($0.title) (\($0.episodes))" }.joined(separator: " · "),
                              icon: "tv.and.mediabox")
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


    /// A plain-text summary of the stats for the share sheet.
    private var statsSummary: String {
        let s = stats
        var lines = [
            "Library Watch Stats",
            "Watched this month: \(s.watchedThisMonth)",
            "Watched all time: \(s.watchedAllTime)",
            "In progress: \(s.inProgress)",
            "Time watched: \(hours(s.totalHoursWatched))",
            "Movies: \(s.movies)  Shows: \(s.shows)",
            "Played this week: \(s.playedThisWeek)",
            "Current streak: \(s.currentStreak) days (best \(s.bestStreak))"
        ]
        if !s.topShows.isEmpty {
            lines.append("Most-watched shows: " + s.topShows.map { "\($0.title) (\($0.episodes) episodes)" }.joined(separator: ", "))
        }
        if let longest = s.longestTitle {
            lines.append("Longest title: \(longest.title) (\(longest.minutes) min)")
        }
        return lines.joined(separator: "\n")
    }

    /// Seven small bars, one per day, labelled with the weekday initial.
    private func activityChart(_ days: [(day: Date, count: Int)]) -> some View {
        let peak = max(1, days.map(\.count).max() ?? 1)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Last 7 days")
                .font(.appFont(15))
                .foregroundStyle(Theme.Colors.textSecondary)
            HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                ForEach(days, id: \.day) { entry in
                    VStack(spacing: 6) {
                        Text("\(entry.count)")
                            .font(.appFont(13, weight: .semibold))
                            .foregroundStyle(entry.count > 0 ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(entry.count > 0 ? Theme.Colors.accent : Theme.Colors.textTertiary.opacity(0.25))
                            .frame(height: max(6, 70 * CGFloat(entry.count) / CGFloat(peak)))
                        Text(entry.day.formatted(.dateTime.weekday(.narrow)))
                            .font(.appFont(12))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(entry.day.formatted(.dateTime.weekday(.wide))): \(entry.count) played")
                }
            }
            .frame(height: 110, alignment: .bottom)
        }
        .padding(Theme.Spacing.md)
        .refinedCardBackground()
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
        .refinedCardBackground()
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
        .refinedCardBackground()
    }
}
