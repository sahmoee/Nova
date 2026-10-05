#if os(iOS)
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
    @Published var lastError: String?
    @Published var skippedCount = 0

    private init() {
        targetCalendarID = UserDefaults.standard.string(forKey: "nova.cal.calendarID")
    }

    // MARK: - Authorization

    func requestAccess() async -> Bool {
        let status: Bool
        if #available(iOS 17, *) {
            status = (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            status = await withCheckedContinuation { cont in
                store.requestAccess(to: .event) { granted, _ in cont.resume(returning: granted) }
            }
        }
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        return status
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .fullAccess
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
        guard !isAdding else { return }
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        lastAddedCount = 0; skippedCount = 0; lastError = nil
        guard isAuthorized else { lastError = "Calendar access is required."; return }
        isAdding = true
        defer { isAdding = false }

        // Hydrate if needed — use what we have if seasons are already populated.
        let source: CatalogItem
        if catalog.seasons.isEmpty, let hydrated = try? await tmdb.hydrateSeriesForCalendar(catalog) {
            source = hydrated
        } else {
            source = catalog
        }

        let upcoming = source.allEpisodes.filter { ep in
            guard let airDate = ep.airDate else { return false }
            return airDate > Date()
        }

        for episode in upcoming.prefix(100) {
            if Task.isCancelled { break }
            do { _ = try addEpisode(episode, for: source); lastAddedCount += 1 }
            catch CalendarError.alreadyExists { skippedCount += 1 }
            catch { lastError = error.localizedDescription; break }
        }
    }

    /// Adds a single episode to the calendar. Returns the new event.
    @discardableResult
    func addEpisode(_ episode: EpisodeInfo, for show: CatalogItem) throws -> EKEvent {
        guard let airDate = episode.airDate else {
            throw CalendarError.noAirDate
        }

        guard let cal = targetCalendar, cal.allowsContentModifications else { throw CalendarError.noCalendar }
        let event = EKEvent(eventStore: store)

        event.title = "\(show.title) — \(episode.displayTitle)"
        event.notes = episode.overview

        // TMDB supplies a date, not a verified broadcast time. Preserve its UTC day.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = utc.dateComponents([.year, .month, .day], from: airDate)
        guard let startDate = Calendar.current.date(from: components),
              let endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate) else {
            throw CalendarError.noAirDate
        }
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = true
        event.calendar = cal

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

    enum CalendarError: LocalizedError {
        case noCalendar
        var errorDescription: String? {
            switch self {
            case .noCalendar: return "Choose a writable calendar before adding episodes."
            case .noAirDate: return "This episode has no valid air date."
            case .alreadyExists: return "This episode is already in your calendar."
            }
        }
        case noAirDate
        case alreadyExists
    }
}

// MARK: - TMDBClient hydrate helper (mirrors the one in EpisodeAvailabilityNotifier)

private extension TMDBClient {
    func hydrateSeriesForCalendar(_ item: CatalogItem) async throws -> CatalogItem? {
        return try await hydrateSeries(item)
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
                ProgressView().tint(Theme.Colors.accent)
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
        resultMessage = calService.lastError ?? (count == 0
            ? "No upcoming episodes found to add."
            : "\(count) upcoming episode\(count == 1 ? "" : "s") added to your calendar.")
        if calService.skippedCount > 0 { resultMessage += " \(calService.skippedCount) already present." }
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
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            calService.targetCalendarID = cal.calendarIdentifier
                        }
                        .accessibilityAddTraits(.isButton)
                    }
                }

                Section {
                    Button("Add Upcoming Episodes") {
                        dismiss()
                        onConfirm()
                    }
                    .foregroundStyle(Theme.Colors.accent)
                } footer: {
                    Text("Only episodes that haven't aired yet will be added. Air dates are all-day events; exact broadcast times are not supplied.")
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

    var body: some View {
        Form {
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
                                    Image(systemName: "checkmark").foregroundStyle(Theme.Colors.accent)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                calService.targetCalendarID = cal.calendarIdentifier
                            }
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                } else {
                    Section {
                        Button("Grant Calendar Access") {
                            Task { _ = await calService.requestAccess() }
                        }
                        .foregroundStyle(Theme.Colors.accent)
                    } footer: {
                        Text("Nova needs calendar access to select a calendar and avoid duplicates. Events are only added when you confirm.")
                    }
                }
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#endif
