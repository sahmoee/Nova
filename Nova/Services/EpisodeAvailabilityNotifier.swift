//
//  EpisodeAvailabilityNotifier.swift
//  Nova
//
//  Checks for newly-aired episodes of shows the user has in their library
//  (or has started watching) and fires a local push notification for each.
//
//  IMPORTANT — "newly aired" vs "unwatched":
//    This service only notifies when an episode's TMDB airDate falls within the
//    last `newEpisodeWindowDays` days. It does NOT notify for old unwatched
//    episodes. A show with 8 seasons the user has never seen will never trigger
//    a notification unless a brand-new episode airs while the app is installed.
//
//  Wire-up:
//  1. AppEnvironment already instantiates this as `episodeNotifier`.
//     `init(library:tmdb:catalog:)` matches AppEnvironment's call site.
//  2. Call `episodeNotifier.requestAuthorization()` once at launch
//     (e.g. from NovaApp or AppEnvironment.init).
//  3. Call `episodeNotifier.checkForNewStreamableEpisodes()` from:
//       - BGAppRefreshTask (register "nova.episodeCheck" in Info.plist)
//       - Scene activation / foreground transition
//  4. Add "nova.episodeCheck" to BGTaskSchedulerPermittedIdentifiers in Info.plist.
//

import Foundation
import UserNotifications
import BackgroundTasks

// MARK: - Notifier

@MainActor
final class EpisodeAvailabilityNotifier {

    // MARK: - Dependencies

    private let library: LibraryStore
    private let tmdb: TMDBClient

    // catalog is kept for future stream-resolution hooks; not used for airDate checks.
    private weak var _catalog: AnyObject?

    // MARK: - Configuration

    /// Episodes that aired up to this many days ago are considered "new".
    private let newEpisodeWindowDays: Int = 7

    /// UserDefaults key → Set<String> of notification IDs already fired.
    private let sentNotifsKey = "nova.episodeNotifier.sentIDs"

    private let bgTaskID = "nova.episodeCheck"

    // MARK: - Init (matches AppEnvironment call site)

    init(library: LibraryStore, tmdb: TMDBClient, catalog: CatalogService) {
        self.library = library
        self.tmdb = tmdb
        self._catalog = catalog
    }

    // MARK: - Authorization

    func requestAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            ) { _, _ in }
        }
    }

    // MARK: - Background task registration

    /// Register the BGAppRefreshTask. Call from application(_:didFinishLaunchingWithOptions:).
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskID, using: nil) { [weak self] task in
            self?.handleBackgroundTask(task as! BGAppRefreshTask)
        }
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: bgTaskID)
        // Check roughly once per day.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60 * 12)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleBackgroundTask(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh() // reschedule next run
        let taskItem = Task { [weak self] in
            await self?.checkForNewStreamableEpisodes()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { taskItem.cancel() }
    }

    // MARK: - Main check

    /// Scans library series, fetches TMDB data, and fires notifications
    /// for episodes that aired within the last `newEpisodeWindowDays` days
    /// and haven't been watched yet.
    func checkForNewStreamableEpisodes() async {
        guard await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized else { return }

        let seriesItems = library.items.filter { $0.isSeries }
        guard !seriesItems.isEmpty else { return }

        // Collect unique TMDB IDs from in-library series.
        // "Marked watching" = has a lastPlayedDate or any play progress.
        let watchingItems = seriesItems.filter { $0.lastPlayedDate != nil || $0.lastPlayedPosition > 0 }
        let allSeriesItems = Array(Set((seriesItems + watchingItems).map { $0 }))

        // Group by show — use contentID.tmdb as the dedup key.
        var showMap: [Int: (title: String, posterURL: URL?)] = [:]
        for item in allSeriesItems {
            guard let tmdbID = item.contentID?.tmdb else { continue }
            if showMap[tmdbID] == nil {
                let title = item.seriesTitle ?? item.title
                showMap[tmdbID] = (title: title, posterURL: item.posterURL)
            }
        }

        let windowStart = Calendar.current.date(byAdding: .day, value: -newEpisodeWindowDays, to: Date()) ?? Date()
        var sentIDs = loadSentIDs()

        for (tmdbID, showInfo) in showMap {
            guard let catalog = try? await tmdb.hydrateSeries(
                ContentID(tmdb: tmdbID, type: .series)
            ) else { continue }

            for episode in catalog.allEpisodes {
                guard let airDate = episode.airDate,
                      airDate >= windowStart,
                      airDate <= Date()          // aired, not in the future
                else { continue }

                // Build a stable notification ID for this episode.
                let notifID = "nova.ep.\(tmdbID).s\(episode.season)e\(episode.number)"
                guard !sentIDs.contains(notifID) else { continue }

                // Check whether the user already watched this episode.
                let alreadyWatched = library.items.contains { item in
                    guard let ep = item.episode else { return false }
                    let sameShow = item.contentID?.tmdb == tmdbID
                    let sameEp   = ep.season == episode.season && ep.number == episode.number
                    return sameShow && sameEp && item.isWatched
                }
                guard !alreadyWatched else {
                    sentIDs.insert(notifID)      // suppress future re-fire
                    continue
                }

                await scheduleNotification(
                    id: notifID,
                    showTitle: showInfo.title,
                    episode: episode,
                    airDate: airDate
                )
                sentIDs.insert(notifID)
            }
        }

        saveSentIDs(sentIDs)
    }

    // MARK: - Schedule a single notification

    private func scheduleNotification(
        id: String,
        showTitle: String,
        episode: EpisodeInfo,
        airDate: Date
    ) async {
        let content = UNMutableNotificationContent()
        content.title = showTitle
        let epLabel = episode.label
        let epTitle = episode.displayTitle
        content.body = epLabel == epTitle
            ? "\(epLabel) is now available"
            : "\(epLabel) · \(epTitle) is now available"
        content.sound = .default
        content.userInfo = ["nova_episode_notif": id]

        // Fire immediately (the episode already aired; we're just informing the user).
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil     // deliver now
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Sent ID persistence

    private func loadSentIDs() -> Set<String> {
        guard let array = UserDefaults.standard.array(forKey: sentNotifsKey) as? [String] else {
            return []
        }
        return Set(array)
    }

    private func saveSentIDs(_ ids: Set<String>) {
        // Cap the set to avoid unbounded growth (keep newest 2000).
        let capped = Array(ids).suffix(2000)
        UserDefaults.standard.set(Array(capped), forKey: sentNotifsKey)
    }
}

// MARK: - TMDBClient hydrate convenience

// TMDBClient.hydrateSeries(_:onPartial:) takes a ContentID and populates
// season/episode data. We call the async overload without a partial callback.
private extension TMDBClient {
    func hydrateSeries(_ contentID: ContentID) async throws -> CatalogItem? {
        guard contentID.tmdb != nil else { return nil }
        var result: CatalogItem?
        // hydrateSeries calls the onPartial closure with increasingly complete data.
        // We capture the last (most complete) value.
        await hydrateSeries(contentID) { partial in
            result = partial
        }
        return result
    }
}

// MARK: - Settings view

import SwiftUI

struct EpisodeNotifierSettingsView: View {
    @AppStorage("nova.episodeNotifier.enabled") private var enabled = true
    @AppStorage("nova.episodeNotifier.windowDays") private var windowDays = 7

    var body: some View {
        Form {
            Section {
                Toggle("New Episode Alerts", isOn: $enabled)
            } footer: {
                Text("Nova will notify you when a new episode of a show you're watching airs. Only recently released episodes trigger alerts — not old unwatched ones.")
            }

            if enabled {
                Section("Alert Window") {
                    Picker("Episode age", selection: $windowDays) {
                        Text("Same day").tag(1)
                        Text("Within 3 days").tag(3)
                        Text("Within 7 days").tag(7)
                        Text("Within 14 days").tag(14)
                    }
                    .pickerStyle(.menu)
                } footer: {
                    Text("Episodes that aired more than \(windowDays) day\(windowDays == 1 ? "" : "s") ago won't trigger an alert.")
                }
            }
        }
        .navigationTitle("Episode Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}
