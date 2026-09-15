import Foundation
import Combine
import CryptoKit
import UIKit

@MainActor
final class NovaPhoneWatchBridge {
    static let shared = NovaPhoneWatchBridge()
    let connection = NovaWatchConnectivity()
    var openItem: ((UUID) -> Bool)?
    private weak var environment: AppEnvironment?
    private var journal = NovaWatchJournal()
    private var writable = true
    private var subscriptions = Set<AnyCancellable>()
    private var pending: [(Data, (Data) -> Void)] = []
    private var draining = false
    private var timer: Task<Void, Never>?
    private var publishTask: Task<Void, Never>?
    private var projectionTask: Task<Void, Never>?
    private var projectionRevision = UUID()
    private var cachedTitles: [NovaWatchTitle] = []
    private var searchableTitles: [NovaWatchTitle] = []
    private let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NovaWatch/phone-journal.json")
    private init() {
        do { if let saved = try NovaWatchCodec.read(NovaWatchJournal.self, from: url) { try saved.validate(); journal = saved } }
        catch { writable = false }
    }
    func configure(environment: AppEnvironment) {
        guard self.environment == nil else { return }
        self.environment = environment
        connection.onCommand = { [weak self] data, reply in
            guard let self else { return }
            guard self.pending.count < 100 else { reply(Data()); return }
            self.pending.append((data, reply)); self.drain()
        }
        connection.onReady = { [weak self] in
            guard let self else { return }
            if self.searchableTitles.isEmpty { self.scheduleProjection() }
            else { self.publish() }
        }
        connection.activate()
        scheduleProjection()
        environment.library.objectWillChange.sink { [weak self] _ in self?.scheduleProjection() }.store(in: &subscriptions)
        WatchNightStore.shared.objectWillChange.sink { [weak self] _ in self?.schedulePublish() }.store(in: &subscriptions)
        WatchNightStore.shared.$resetRevision.dropFirst().sink { [weak self] _ in self?.invalidateEpoch() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .novaBackupRestored).sink { [weak self] _ in
            Task { @MainActor in self?.invalidateEpoch() }
        }.store(in: &subscriptions)
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                if self.connection.reachable && self.foreground && PlaybackCoordinator.shared.hasActivePlayer { self.publish() }
            }
        }
    }
    /// Erase/restore boundaries are persisted before later commands can be admitted.
    func invalidateEpoch(allowRecovery: Bool = false) {
        guard environment != nil else { return }
        guard writable || allowRecovery else { scheduleProjection(); return }
        journal = NovaWatchJournal()
        journal.resetWatermark = resetWatermark
        cachedTitles = []; searchableTitles = []; projectionRevision = UUID(); scheduleProjection()
        do { try NovaWatchCodec.write(journal, to: url); writable = true }
        catch { writable = false }
        schedulePublish()
    }
    private var resetWatermark: Double { max(CloudSync.shared.deletionDate(.library), CloudSync.shared.deletionDate(.history)) }
    private func checkResetBoundary() {
        if writable && resetWatermark > journal.resetWatermark { invalidateEpoch() }
    }
    func sceneChanged() { schedulePublish() }
    private func schedulePublish() {
        publishTask?.cancel()
        publishTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }; self?.publish()
        }
    }
    private var foreground: Bool { UIApplication.shared.applicationState == .active }
    nonisolated private static func projection(_ item: MediaItem, queued: Set<UUID>) -> NovaWatchTitle {
        NovaWatchTitle(id: item.id, title: NovaWatchPolicy.boundedText(item.displayTitle, characters: 179, bytes: 400), subtitle: NovaWatchPolicy.boundedText(item.subtitleLine, characters: 99, bytes: 150),
                       planKey: Self.key(item), duration: item.duration, position: item.lastPlayedPosition,
                       favorite: item.isFavorite, queued: queued.contains(item.id),
                       watched: item.isWatched, lastPlayed: item.lastPlayedDate, isSeries: item.isSeries, resumeAvailable: item.hasResumePoint)
    }
    nonisolated private static func key(_ item: MediaItem) -> String { SHA256.hash(data: Data(item.contentKey.utf8)).map { String(format: "%02x", $0) }.joined() }
    private func scheduleProjection() {
        projectionTask?.cancel()
        projectionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled, self.connection.available, let environment = self.environment else { return }
            let revision = UUID(); self.projectionRevision = revision
            let items = environment.library.items, queue = Set(environment.library.queueIDs)
            let worker = Task.detached(priority: .utility) { () throws -> ([NovaWatchTitle], [NovaWatchTitle]) in
                try Task.checkCancellation()
                var projected: [NovaWatchTitle] = []; projected.reserveCapacity(items.count)
                for item in items { try Task.checkCancellation(); projected.append(Self.projection(item, queued: queue)) }
                projected.sort {
                    let order = $0.title.localizedStandardCompare($1.title)
                    return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
                }
                try Task.checkCancellation()
                let ranked = projected.sorted {
                    let lhs = ($0.hasResume ? 8 : 0) + ($0.favorite ? 4 : 0) + ($0.queued ? 2 : 0)
                    let rhs = ($1.hasResume ? 8 : 0) + ($1.favorite ? 4 : 0) + ($1.queued ? 2 : 0)
                    if lhs != rhs { return lhs > rhs }
                    if $0.lastPlayed != $1.lastPlayed { return ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
                    return $0.id.uuidString < $1.id.uuidString
                }
                try Task.checkCancellation()
                return (projected, Array(ranked.prefix(120)))
            }
            guard let (projected, bounded) = try? await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() }),
                  !Task.isCancelled, self.projectionRevision == revision else { return }
            self.searchableTitles = projected; self.cachedTitles = bounded
            self.publish()
        }
    }
    private func snapshot() -> NovaWatchSnapshot? {
        guard environment != nil else { return nil }
        checkResetBoundary()
        if journal.snapshotRevision < Int64.max { journal.snapshotRevision += 1 }
        // Preserve an unreadable original. Only an explicit reset replaces it.
        if writable { do { try NovaWatchCodec.write(journal, to: url) } catch { writable = false } }
        var value = NovaWatchSnapshot(phoneID: journal.phoneID, revision: journal.snapshotRevision, generatedAt: Date(), totalTitles: environment?.library.items.count ?? searchableTitles.count,
            titles: Array(cachedTitles.prefix(environment?.library.items.count ?? 0)), plans: Array(WatchNightStore.shared.state.plans.prefix(3)).map(Self.planProjection), totalPlans: WatchNightStore.shared.state.plans.count,
            phoneForeground: foreground, acceptsEdits: writable && (environment?.library.allowsWatchEdits ?? false), player: currentPlayer(), phoneMessage: writable ? nil : "Watch edits are paused because the phone journal could not be read or saved.")
        // Leave room for a page/receipt; all titles remain available through paginated search.
        while (try? NovaWatchCodec.encode(value, limit: 24_000)) == nil {
            if !value.plans.isEmpty { value.plans.removeLast() }
            else if !value.titles.isEmpty { value.titles.removeLast() }
            else { return nil }
        }
        return value
    }
    nonisolated private static func planProjection(_ plan: WatchNightPlan) -> WatchNightPlan {
        var copy = plan
        copy.entries = plan.entries.map { entry in
            var value = entry
            value.title = NovaWatchPolicy.boundedText(value.title, characters: 179, bytes: 400)
            return value
        }
        return copy
    }
    private func currentPlayer() -> NovaWatchPlayer? {
        guard foreground, let player = PlaybackCoordinator.shared.watchRemotePlayer else { return nil }
        return player.watchStatus(sessionID: PlaybackCoordinator.shared.watchSessionID)
    }
    private func publish() {
        guard connection.available else { return }
        guard let snapshot = snapshot(), let data = try? NovaWatchCodec.encode(NovaWatchEnvelope(snapshot: snapshot)) else { return }
        connection.publish(data)
    }
    private func drain() {
        guard !draining else { return }; draining = true
        Task { [weak self] in
            guard let self else { return }
            while !self.pending.isEmpty {
                let (data, reply) = self.pending.removeFirst()
                guard let command = try? NovaWatchCodec.decode(NovaWatchCommand.self, data: data) else { reply(Data()); continue }
                let receipt = await self.handle(command)
                var envelope = NovaWatchEnvelope(snapshot: self.snapshot(), receipt: receipt)
                while (try? NovaWatchCodec.encode(envelope)) == nil && envelope.snapshot != nil {
                    if envelope.snapshot?.plans.isEmpty == false { envelope.snapshot?.plans.removeLast() }
                    else if envelope.snapshot?.titles.isEmpty == false { envelope.snapshot?.titles.removeLast() }
                    else { envelope.snapshot = nil }
                }
                reply((try? NovaWatchCodec.encode(envelope)) ?? Data())
                self.publish()
            }
            self.draining = false
        }
    }
    private func handle(_ command: NovaWatchCommand) async -> NovaWatchReceipt {
        func receipt(_ outcome: NovaWatchReceipt.Outcome, _ message: String) -> NovaWatchReceipt {
            NovaWatchReceipt(id: command.id, outcome: outcome, message: message)
        }
        do {
            checkResetBoundary()
            try command.validate()
            if command.action == .refresh { return receipt(.applied, "Synced with iPhone") }
            guard command.phoneID == journal.phoneID else { return receipt(.rejected, "iPhone data changed or was reset. Refresh before making new edits.") }
            guard let environment else { throw NovaWatchFailure.disconnected }
            if command.action == .plans {
                var result = receipt(.applied, "Watch Night refreshed"); result.plans = WatchNightStore.shared.state.plans.map(NovaWatchPlanSummary.init); return result
            }
            if command.action == .planDetails {
                var result = receipt(.applied, "Plan refreshed"); result.plan = WatchNightStore.shared.state.plans.first { $0.id == command.planID }.map(Self.planProjection); return result
            }
            if command.action == .search {
                if let projectionTask { await projectionTask.value }
                let query = (command.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let titles = searchableTitles
                let all = await Task.detached(priority: .userInitiated) {
                    titles.filter { title in
                        let matches = query.isEmpty || title.title.localizedStandardContains(query)
                        switch command.scope ?? .all {
                        case .all: return matches
                        case .continueWatching: return matches && title.hasResume
                        case .favorites: return matches && title.favorite
                        case .queue: return matches && title.queued
                        case .history: return matches && title.lastPlayed != nil
                        }
                    }
                }.value
                guard command.phoneID == journal.phoneID else { throw NovaWatchFailure.invalid }
                let offset = min(command.offset ?? 0, all.count)
                var result = receipt(.applied, "Library page updated")
                result.search = Array(all.dropFirst(offset).prefix(25)); result.searchTotal = all.count
                result.query = query; result.offset = offset
                return result
            }
            if command.action.isDurable {
                guard writable else { throw NovaWatchFailure.unreadable }
                if let previous = journal.previous(command) { return previous }
                var reserved = journal; try reserved.reserve(command)
                try NovaWatchCodec.write(reserved, to: url); journal = reserved
            }
            let message = try await apply(command, environment: environment)
            if let id = command.itemID, let item = environment.library.items.first(where: { $0.id == id }) {
                let title = Self.projection(item, queued: Set(environment.library.queueIDs))
                if let index = cachedTitles.firstIndex(where: { $0.id == id }) { cachedTitles[index] = title }
                else { cachedTitles.insert(title, at: 0); cachedTitles = Array(cachedTitles.prefix(120)) }
                if let index = searchableTitles.firstIndex(where: { $0.id == id }) { searchableTitles[index] = title }
            }
            var result = receipt(.applied, message)
            result.updatedTitle = cachedTitles.first { $0.id == command.itemID }
            if command.action.isDurable {
                // A reset while an async plan save was suspended invalidates the old command.
                guard command.phoneID == journal.phoneID else { return receipt(.interrupted, "iPhone data was reset during this change. Refresh to see current state.") }
                var completed = journal; completed.finish(result)
                do { try NovaWatchCodec.write(completed, to: url); journal = completed }
                catch { writable = false; return receipt(.interrupted, "Change may have been saved, but its receipt could not be stored. Refresh on iPhone.") }
            }
            return result
        } catch {
            let result = receipt(.rejected, error.localizedDescription)
            if command.action.isDurable, command.phoneID == journal.phoneID, journal.previous(command) != nil {
                var completed = journal; completed.finish(result)
                do { try NovaWatchCodec.write(completed, to: url); journal = completed } catch { writable = false }
            }
            return result
        }
    }
    private func apply(_ command: NovaWatchCommand, environment: AppEnvironment) async throws -> String {
        let library = environment.library
        if [.setFavorite, .setQueued, .setWatched].contains(command.action), !library.allowsWatchEdits { throw NovaWatchFailure.unreadable }
        func item() throws -> MediaItem {
            guard let item = library.items.first(where: { $0.id == command.itemID }) else { throw WatchNightError.invalid("This title is no longer in the iPhone library.") }; return item
        }
        switch command.action {
        case .setFavorite:
            let title = try item(); library.setFavorite(command.flag == true, for: [title.id])
            guard library.items.first(where: { $0.id == title.id })?.isFavorite == command.flag else { throw WatchNightError.invalid("iPhone could not save the favorite. Open Library on iPhone.") }
            return command.flag == true ? "Added to favorites" : "Removed from favorites"
        case .setQueued:
            let title = try item()
            if command.flag == true { library.addToQueue(title) } else { library.removeFromQueue(title) }
            guard library.isQueued(title) == (command.flag == true) else { throw WatchNightError.invalid("iPhone could not save Up Next.") }
            return command.flag == true ? "Added to Up Next" : "Removed from Up Next"
        case .setWatched:
            var title = try item()
            if command.flag == true {
                if !title.isWatched {
                    guard let duration = title.duration else { throw WatchNightError.invalid("This title has no runtime yet. Refresh its metadata on iPhone before marking it watched.") }
                    title.lastPlayedPosition = duration; title.lastPlayedDate = Date()
                }
            } else { title.lastPlayedPosition = 0; title.lastPlayedDate = nil }
            library.update(title)
            guard library.items.first(where: { $0.id == title.id }) == title else { throw WatchNightError.invalid("iPhone could not save watch history.") }
            if command.flag == true { library.removeFromQueue(title) }
            return command.flag == true ? "Marked watched" : "Watch progress cleared"
        case .createPlan, .renamePlan, .setPlanSchedule, .setPlanItem, .removePlanEntry, .deletePlan:
            let planID = command.planID!
            let title = command.action == .setPlanItem ? try item() : nil
            let success = await WatchNightStore.shared.update { state in
                guard command.phoneID == self.journal.phoneID else { throw NovaWatchFailure.invalid }
                if command.action == .createPlan {
                    guard !state.plans.contains(where: { $0.id == planID }) else { return }
                    state.plans.append(WatchNightPlan(id: planID, name: command.text!.trimmingCharacters(in: .whitespacesAndNewlines)))
                    return
                }
                if command.action == .deletePlan { state.plans.removeAll { $0.id == planID }; return }
                guard let index = state.plans.firstIndex(where: { $0.id == planID }) else { throw WatchNightError.invalid("This Watch Night plan was removed on iPhone.") }
                switch command.action {
                case .renamePlan: state.plans[index].name = command.text!.trimmingCharacters(in: .whitespacesAndNewlines)
                case .setPlanSchedule: state.plans[index].startsAt = command.date!; state.plans[index].availableMinutes = Int(command.value!)
                case .removePlanEntry: state.plans[index].entries.removeAll { $0.id == command.entryID }
                case .setPlanItem:
                    if let title {
                        let key = Self.key(title)
                        if command.flag == true {
                            guard !state.plans[index].entries.contains(where: { $0.titleID == key }) else { return }
                            state.plans[index].entries.append(WatchNightEntry(id: command.id, titleID: key, title: String(title.displayTitle.prefix(300)),
                                estimatedSeconds: title.duration.flatMap { $0 <= 86400 ? $0 : nil }))
                        } else { state.plans[index].entries.removeAll { $0.titleID == key } }
                    }
                default: break
                }
            }
            guard success else { throw WatchNightError.invalid(WatchNightStore.shared.error ?? "Watch Night is busy or could not save. Try again after refreshing.") }
            return "Watch Night updated"
        case .openOnPhone:
            let title = try item()
            guard foreground, openItem?(title.id) == true else { throw WatchNightError.invalid("Open Nova on iPhone and close any sheet, then try again.") }
            return "Title requested on iPhone. Choose Play there."
        case .setPlaying, .seek, .setVolume:
            guard foreground, command.playerSessionID == PlaybackCoordinator.shared.watchSessionID,
                  let player = PlaybackCoordinator.shared.watchRemotePlayer,
                  player.watchStatus(sessionID: PlaybackCoordinator.shared.watchSessionID) != nil else { throw NovaWatchFailure.disconnected }
            try player.applyWatchCommand(command)
            return "Control sent to the active iPhone player"
        case .refresh, .search, .plans, .planDetails: return "Synced with iPhone"
        }
    }
}
