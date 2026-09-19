//
//  NovaEpisodeCalendar.swift
//  Nova
//
//  Adds upcoming episode air dates to the user's calendar via EventKit.
//  Works with EpisodeInfo.airDate populated by TMDBClient.hydrateSeries().
//
//  Usage:
//  1. Add NSCalendarsUsageDescription and NSCalendarsWriteOnlyAccessUsageDescription
//     keys to Info.plist.
//  2. On a CatalogItem detail screen:
//       NovaEpisodeCalendarButton(catalog: item, tmdb: env.tmdb)
//  3. For a single episode:
//       NovaEpisodeCalendar.shared.addEpisode(episode, for: catalogItem)
//

import SwiftUI
import EventKit

// MARK: - Calendar service

@MainActor
final class NovaEpisodeCalendar: ObservableObject {
    static let shared = NovaEpisodeCalendar()

    private let store = EKEventStore()

    @Published var authorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published var targetCalendarID: String? {
        didSet { UserDefaults.standard.set(targetCalendarID, forKey: "nova.cal.calendarID") }
    }
    @Published var isAdding = false
    @Published var lastAddedCount = 0

    private init() {
        targetCalendarID = UserDefaults.standard.string(forKey: "nova.cal.calendarID")
    }

    // MARK: - Authorization

    func requestAccess() async -> Bool {
        let status: Bool
        if #available(iOS 17, *) {
            status = (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        } else {
            status = await withCheckedContinuation { cont in
                store.requestAccess(to: .event) { granted, _ in cont.resume(returning: granted) }
            }
        }
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        return status
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .fullAccess ||
        authorizationStatus == .writeOnly
    }

    // MARK: - Calendar selection

    var availableCalendars: [EKCalendar] {
        store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .sorted { $0.title < $1.title }
    }

    var targetCalendar: EKCalendar? {
        if let id = targetCalendarID,
           let cal = store.calendar(withIdentifier: id) {
            return cal
        }
        return store.defaultCalendarForNewEvents
    }

    // MARK: - Add episodes for a whole show

    /// Fetches episodes via TMDB and adds future air dates to the calendar.
    /// Only adds episodes that haven't aired yet.
    func addUpcomingEpisodes(for catalog: CatalogItem, tmdb: TMDBClient) async {
        guard isAuthorized else { return }
        isAdding = true
        defer { isAdding = false }

        // Hydrate if needed — use what we have if seasons are already populated.
        let source: CatalogItem
        if catalog.seasons.isEmpty, let hydrated = try? await tmdb.hydrateSeries(catalog.contentID) {
            source = hydrated
        } else {
            source = catalog
        }

        let upcoming = source.allEpisodes.filter { ep in
            guard let airDate = ep.airDate else { return false }
            return airDate > Date()
        }

        var added = 0
        for episode in upcoming {
            if (try? addEpisode(episode, for: source)) != nil { added += 1 }
        }
        lastAddedCount = added

        // Commit to the store.
        try? store.commit()
    }

    /// Adds a single episode to the calendar. Returns the new event.
    @discardableResult
    func addEpisode(_ episode: EpisodeInfo, for show: CatalogItem) throws -> EKEvent {
        guard let airDate = episode.airDate else {
            throw CalendarError.noAirDate
        }

        let cal = targetCalendar ?? store.defaultCalendarForNewEvents!
        let event = EKEvent(eventStore: store)

        event.title = "\(show.title) — \(episode.displayTitle)"
        event.notes = episode.overview

        // Air dates from TMDB are calendar-day dates (midnight UTC).
        // Use a 1-hour all-day-ish window at 9 PM local so the alert is useful.
        var components = Calendar.current.dateComponents([.year, .month, .day], from: airDate)
        components.hour = 21
        components.minute = 0
        let startDate = Calendar.current.date(from: components) ?? airDate
        event.startDate = startDate
        event.endDate   = startDate.addingTimeInterval(episode.runtime ?? 3600)

        event.calendar = cal

        // Add a 30-minute-before alarm.
        event.addAlarm(EKAlarm(relativeOffset: -30 * 60))

        // Check for existing event to avoid duplicates (match by title + start date).
        let predicate = store.predicateForEvents(
            withStart: startDate.addingTimeInterval(-60),
            end: startDate.addingTimeInterval(60),
            calendars: [cal]
        )
        let existing = store.events(matching: predicate)
        if existing.contains(where: { $0.title == event.title }) {
            throw CalendarError.alreadyExists
        }

        try store.save(event, span: .thisEvent)
        return event
    }

    enum CalendarError: Error {
        case noAirDate
        case alreadyExists
    }
}

// MARK: - TMDBClient hydrate helper (mirrors the one in EpisodeAvailabilityNotifier)

private extension TMDBClient {
    func hydrateSeries(_ contentID: ContentID) async throws -> CatalogItem? {
        guard contentID.tmdb != nil else { return nil }
        var result: CatalogItem?
        await hydrateSeries(contentID) { partial in result = partial }
        return result
    }
}

// MARK: - Add-episodes button (drop into CatalogItem detail screen)

struct NovaEpisodeCalendarButton: View {
    let catalog: CatalogItem
    let tmdb: TMDBClient

    @StateObject private var calService = NovaEpisodeCalendar.shared
    @State private var showSheet = false
    @State private var showResult = false
    @State private var resultMessage = ""

    var body: some View {
        Button {
            Task { await tapped() }
        } label: {
            if calService.isAdding {
                ProgressView().tint(.orange)
            } else {
                Label("Add to Calendar", systemImage: "calendar.badge.plus")
            }
        }
        .disabled(calService.isAdding)
        .sheet(isPresented: $showSheet) {
            CalendarPickerSheet(calService: calService) {
                Task { await addEpisodes() }
            }
        }
        .alert("Calendar", isPresented: $showResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resultMessage)
        }
    }

    private func tapped() async {
        if !calService.isAuthorized {
            let granted = await calService.requestAccess()
            guard granted else {
                resultMessage = "Calendar access is required. Enable it in Settings → Privacy → Calendars."
                showResult = true
                return
            }
        }
        showSheet = true
    }

    private func addEpisodes() async {
        await calService.addUpcomingEpisodes(for: catalog, tmdb: tmdb)
        let count = calService.lastAddedCount
        resultMessage = count == 0
            ? "No upcoming episodes found to add."
            : "\(count) upcoming episode\(count == 1 ? "" : "s") added to your calendar."
        showResult = true
    }
}

// MARK: - Calendar picker sheet

private struct CalendarPickerSheet: View {
    @ObservedObject var calService: NovaEpisodeCalendar
    var onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Select Calendar") {
                    ForEach(calService.availableCalendars, id: \.calendarIdentifier) { cal in
                        HStack {
                            Circle()
                                .fill(Color(cgColor: cal.cgColor))
                                .frame(width: 12, height: 12)
                            Text(cal.title)
                            Spacer()
                            if calService.targetCalendarID == cal.calendarIdentifier {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            calService.targetCalendarID = cal.calendarIdentifier
                        }
                    }
                }

                Section {
                    Button("Add Upcoming Episodes") {
                        dismiss()
                        onConfirm()
                    }
                    .foregroundStyle(.orange)
                } footer: {
                    Text("Only episodes that haven't aired yet will be added. Each event includes a 30-minute reminder.")
                }
            }
            .navigationTitle("Add to Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Settings entry (add to Nova Settings screen)

struct NovaCalendarSettingsRow: View {
    @StateObject private var calService = NovaEpisodeCalendar.shared

    var body: some View {
        NavigationLink {
            NovaCalendarSettingsView(calService: calService)
        } label: {
            Label("Calendar Integration", systemImage: "calendar")
        }
    }
}

struct NovaCalendarSettingsView: View {
    @ObservedObject var calService: NovaEpisodeCalendar
    @AppStorage("nova.cal.enabled") private var enabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Add Air Dates to Calendar", isOn: $enabled)
            } footer: {
                Text("When you open a series, Nova can add its upcoming episode air dates to your calendar so you never miss a premiere.")
            }

            if enabled {
                if calService.isAuthorized {
                    Section("Default Calendar") {
                        ForEach(calService.availableCalendars, id: \.calendarIdentifier) { cal in
                            HStack {
                                Circle()
                                    .fill(Color(cgColor: cal.cgColor))
                                    .frame(width: 12, height: 12)
                                Text(cal.title)
                                Spacer()
                                if calService.targetCalendarID == cal.calendarIdentifier
                                    || (calService.targetCalendarID == nil
                                        && cal == calService.targetCalendar) {
                                    Image(systemName: "checkmark").foregroundStyle(.orange)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                calService.targetCalendarID = cal.calendarIdentifier
                            }
                        }
                    }
                } else {
                    Section {
                        Button("Grant Calendar Access") {
                            Task { _ = await calService.requestAccess() }
                        }
                        .foregroundStyle(.orange)
                    } footer: {
                        Text("Nova needs calendar write access to add episode air dates.")
                    }
                }
            }
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }
}
