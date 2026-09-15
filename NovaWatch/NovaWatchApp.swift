import SwiftUI

@main
struct NovaWatchApp: App {
    @StateObject private var store = NovaWatchStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            NovaWatchHome().environmentObject(store).environmentObject(store.connection)
                .tint(.white)
        }
        .onChange(of: phase) { _, phase in if phase == .active { store.refresh() } }
        .backgroundTask(.watchConnectivity) { await store.finishBackgroundDelivery() }
    }
}

struct NovaWatchHome: View {
    @EnvironmentObject private var store: NovaWatchStore
    @EnvironmentObject private var connection: NovaWatchConnectivity
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { NovaWatchNowPlaying() } label: { Label("Now Playing", systemImage: "play.circle") }
                    NavigationLink { NovaWatchTitles(mode: .continueWatching) } label: { Label("Continue Watching", systemImage: "play.rectangle") }
                    NavigationLink { NovaWatchLibrary() } label: { Label("Library & Search", systemImage: "magnifyingglass") }
                    NavigationLink { NovaWatchTitles(mode: .favorites) } label: { Label("Favorites", systemImage: "star") }
                    NavigationLink { NovaWatchTitles(mode: .queue) } label: { Label("Up Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                    NavigationLink { NovaWatchTitles(mode: .history) } label: { Label("Watch History", systemImage: "clock.arrow.circlepath") }
                    NavigationLink { NovaWatchPlans() } label: { Label("Watch Night", systemImage: "moon.stars") }
                }
                Section {
                    NavigationLink { NovaWatchSync() } label: {
                        Label(store.pendingCount > 0 ? "\(store.pendingCount) pending" : "Sync & Status", systemImage: "arrow.triangle.2.circlepath")
                    }
                    if let date = store.snapshot?.generatedAt {
                        Text("Updated \(date.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                    } else { Text("Open Nova on your paired iPhone to load your library.").font(.caption) }
                }
            }
            .navigationTitle("Nova")
        }
    }
}

enum NovaWatchTitleMode: String { case continueWatching = "Continue Watching", favorites = "Favorites", queue = "Up Next", history = "History" }
struct NovaWatchTitles: View {
    var mode: NovaWatchTitleMode
    @EnvironmentObject private var store: NovaWatchStore
    @EnvironmentObject private var connection: NovaWatchConnectivity
    private var scope: NovaWatchLibraryScope {
        switch mode { case .continueWatching: .continueWatching; case .favorites: .favorites; case .queue: .queue; case .history: .history }
    }
    private var cached: [NovaWatchTitle] {
        store.titles.filter {
            switch mode { case .continueWatching: $0.hasResume; case .favorites: $0.favorite; case .queue: $0.queued; case .history: $0.lastPlayed != nil }
        }.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
    }
    var body: some View {
        List {
            if store.searching && connection.reachable { ProgressView("Loading iPhone library…") }
            ForEach(connection.reachable ? store.searchResults.map(store.overlay) : cached) { title in
                NavigationLink { NovaWatchTitleDetail(initial: title) } label: { NovaWatchTitleRow(title: title) }
            }
            if connection.reachable {
                Text("\(store.searchTotal) titles · page \(store.searchOffset / 25 + 1)").font(.caption2).foregroundStyle(.secondary)
                if store.searchOffset > 0 { Button("Previous 25") { store.search("", offset: max(0, store.searchOffset - 25), scope: scope) } }
                if store.searchOffset + store.searchResults.count < store.searchTotal { Button("Next 25") { store.search("", offset: store.searchOffset + 25, scope: scope) } }
            } else { Text("Offline · showing cached titles. Connect to iPhone for the full list.").font(.caption2).foregroundStyle(.secondary) }
            if let message = store.message { Text(message).font(.caption2).foregroundStyle(.secondary) }
        }.navigationTitle(mode.rawValue).onAppear { if connection.reachable { store.search("", scope: scope) } }
            .onChange(of: connection.reachable) { _, reachable in if reachable { store.search("", scope: scope) } }
    }
}

struct NovaWatchTitleRow: View {
    var title: NovaWatchTitle
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(title.title).font(.headline).lineLimit(3); if title.favorite { Image(systemName: "star.fill").accessibilityLabel("Favorite") } }
            if !title.subtitle.isEmpty { Text(title.subtitle).font(.caption2).foregroundStyle(.secondary) }
            if title.hasResume { ProgressView(value: title.progress).accessibilityLabel("Watch progress").accessibilityValue("\(Int(title.progress * 100)) percent") }
            if title.watched { Label("Watched", systemImage: "checkmark").font(.caption2) }
        }.padding(.vertical, 3)
    }
}

struct NovaWatchLibrary: View {
    @EnvironmentObject private var store: NovaWatchStore
    @EnvironmentObject private var connection: NovaWatchConnectivity
    @State private var query = ""
    private var cached: [NovaWatchTitle] { store.titles.filter { query.isEmpty || $0.title.localizedStandardContains(query) } }
    var body: some View {
        List {
            TextField("Search titles", text: $query).accessibilityLabel("Search library")
            if store.searching { ProgressView("Searching iPhone…") }
            if connection.reachable {
                Text("\(store.searchTotal) titles · page \(store.searchOffset / 25 + 1)").font(.caption2).foregroundStyle(.secondary)
                ForEach(store.searchResults.map(store.overlay)) { title in NavigationLink { NovaWatchTitleDetail(initial: title) } label: { NovaWatchTitleRow(title: title) } }
                if store.searchOffset > 0 { Button("Previous 25") { store.search(query, offset: max(0, store.searchOffset - 25)) } }
                if store.searchOffset + store.searchResults.count < store.searchTotal { Button("Next 25") { store.search(query, offset: store.searchOffset + 25) } }
                if !store.searching && store.searchResults.isEmpty { Text("No matching titles on iPhone.").foregroundStyle(.secondary) }
            } else {
                Text("Offline cache · \(cached.count) of \(store.snapshot?.totalTitles ?? 0) titles").font(.caption2).foregroundStyle(.secondary)
                ForEach(cached) { title in NavigationLink { NovaWatchTitleDetail(initial: title) } label: { NovaWatchTitleRow(title: title) } }
            }
            if let message = store.message { Text(message).font(.caption2).foregroundStyle(.secondary) }
        }.navigationTitle("Library")
            .task(id: query) { try? await Task.sleep(for: .milliseconds(350)); guard !Task.isCancelled else { return }; if connection.reachable { store.search(query) } }
            .onChange(of: connection.reachable) { _, reachable in if reachable { store.search(query) } }
    }
}

struct NovaWatchTitleDetail: View {
    var initial: NovaWatchTitle
    @EnvironmentObject private var store: NovaWatchStore
    @State private var clearProgress = false
    private var title: NovaWatchTitle { store.overlay(initial) }
    var body: some View {
        List {
            Section { NovaWatchTitleRow(title: title)
                if let duration = title.duration { Text("Runtime \(Duration.seconds(duration).formatted(.time(pattern: .hourMinuteSecond)))").font(.caption) }
                if let played = title.lastPlayed { Text("Last played \(played.formatted(date: .abbreviated, time: .omitted))").font(.caption2).foregroundStyle(.secondary) }
            }
            Section {
                Button { store.submit(.openOnPhone, itemID: title.id) } label: { Label("Open on iPhone", systemImage: "iphone.and.arrow.forward") }.disabled(!store.live)
                Text("Playback opens on iPhone. Media servers, streams, downloads, and subtitles are managed there.").font(.caption2).foregroundStyle(.secondary)
            }
            Section {
                Button { store.submit(.setFavorite, itemID: title.id, flag: !title.favorite) } label: { Label(title.favorite ? "Remove Favorite" : "Favorite", systemImage: title.favorite ? "star.fill" : "star") }
                Button { store.submit(.setQueued, itemID: title.id, flag: !title.queued) } label: { Label(title.queued ? "Remove from Up Next" : "Add to Up Next", systemImage: title.queued ? "checkmark.circle.fill" : "plus.circle") }
                Button { if title.watched || title.position > 0 { clearProgress = true } else { store.submit(.setWatched, itemID: title.id, flag: true) } } label: {
                    Label(title.watched ? "Mark Unwatched" : title.position > 0 ? "Update Watch Status" : "Mark Watched", systemImage: "checkmark.circle")
                }
                NavigationLink { NovaWatchAddToPlan(title: title) } label: { Label("Add to Watch Night", systemImage: "moon.stars") }
            }.disabled(!store.canEdit)
            if store.pendingCount > 0 { Text("\(store.pendingCount) edits waiting for confirmation.").font(.caption2).foregroundStyle(.secondary) }
            if let message = store.message { Text(message).font(.caption2).foregroundStyle(.secondary) }
        }.navigationTitle("Title")
            .confirmationDialog("Update watch status?", isPresented: $clearProgress) {
                if !title.watched { Button("Mark Watched") { store.submit(.setWatched, itemID: title.id, flag: true) } }
                Button("Clear Watch Progress", role: .destructive) { store.submit(.setWatched, itemID: title.id, flag: false) }
                Button("Cancel", role: .cancel) {}
            }
    }
}

struct NovaWatchPlans: View {
    @EnvironmentObject private var store: NovaWatchStore
    @State private var name = ""
    var body: some View {
        List {
            ForEach(store.plans) { plan in
                NavigationLink { NovaWatchPlanDetail(id: plan.id) } label: {
                    VStack(alignment: .leading) { Text(plan.name).font(.headline); Text("\(plan.count) titles · \(plan.startsAt.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            Section("New Watch Night") {
                TextField("Plan name", text: $name)
                Button("Create Plan") { store.submit(.createPlan, planID: UUID(), text: name); name = "" }
                    .disabled(!store.canEdit || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 100)
            }
            if store.pendingCount > 0 { Text("Plan changes appear after iPhone confirms them.").font(.caption2).foregroundStyle(.secondary) }
            if let message = store.message { Text(message).font(.caption2).foregroundStyle(.secondary) }
        }.navigationTitle("Watch Night").onAppear { store.loadPlans() }
            .onChange(of: store.pendingCount) { old, new in if old > 0 && new == 0 { store.loadPlans() } }
    }
}

struct NovaWatchPlanDetail: View {
    let id: UUID
    @EnvironmentObject private var store: NovaWatchStore
    @Environment(\.dismiss) private var dismiss
    @State private var delete = false
    var body: some View {
        List {
            if let plan = store.plan(id) {
                Section {
                    Text(plan.name).font(.headline)
                    Text(plan.startsAt.formatted(date: .abbreviated, time: .shortened))
                    Text("\(plan.availableMinutes) min available · \(plan.breakMinutes) min breaks").font(.caption)
                    Text(plan.unknownCount > 0 ? "\(plan.unknownCount) runtimes unknown" : "Estimated \(Int(plan.knownSeconds / 60)) min").font(.caption2).foregroundStyle(.secondary)
                    if plan.exceedsBudget { Label("Over your time budget", systemImage: "clock.badge.exclamationmark").font(.caption) }
                    NavigationLink("Edit Plan") { NovaWatchPlanEditor(plan: plan) }
                }
                ForEach(plan.entries) { entry in
                    VStack(alignment: .leading) {
                        Text(entry.title).font(.headline)
                        if let seconds = entry.estimatedSeconds { Text("\(Int(seconds / 60)) min").font(.caption2) }
                        Button("Remove from Plan", role: .destructive) { store.submit(.removePlanEntry, planID: id, entryID: entry.id) }.font(.caption)
                    }
                }
                Section {
                    NavigationLink("Add a Title") { NovaWatchPlanTitlePicker(plan: plan) }
                    Button("Delete Plan", role: .destructive) { delete = true }
                }.disabled(!store.canEdit)
            } else { Text("Open Nova on iPhone to load this plan, or refresh if it was deleted."); Button("Refresh Plan") { store.loadPlan(id) } }
            if store.pendingCount > 0 { Text("Waiting for iPhone confirmation…").font(.caption2).foregroundStyle(.secondary) }
        }.navigationTitle("Plan").onAppear { store.loadPlan(id) }
            .onChange(of: store.pendingCount) { old, new in if old > 0 && new == 0 { store.loadPlan(id) } }
            .confirmationDialog("Delete this Watch Night plan?", isPresented: $delete) {
                Button("Delete Plan", role: .destructive) { store.submit(.deletePlan, planID: id); dismiss() }
                Button("Cancel", role: .cancel) {}
            }
    }
}
struct NovaWatchPlanEditor: View {
    var plan: WatchNightPlan
    @EnvironmentObject private var store: NovaWatchStore
    @State private var name = ""
    @State private var date = Date()
    @State private var minutes = 180
    var body: some View {
        Form {
            TextField("Name", text: $name)
            Button("Save Name") { store.submit(.renamePlan, planID: plan.id, text: name) }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 100)
            DatePicker("Starts", selection: $date)
            Stepper("\(minutes) min available", value: $minutes, in: 15...1440, step: 15)
            Button("Save Schedule") { store.submit(.setPlanSchedule, planID: plan.id, value: Double(minutes), date: date) }
            Text("Changes save through iPhone. Breaks and advanced plan settings remain available there.").font(.caption2).foregroundStyle(.secondary)
        }.disabled(!store.canEdit).navigationTitle("Edit Plan")
            .onAppear { name = plan.name; date = plan.startsAt; minutes = plan.availableMinutes }
    }
}
struct NovaWatchAddToPlan: View {
    var title: NovaWatchTitle
    @EnvironmentObject private var store: NovaWatchStore
    var body: some View {
        List {
            ForEach(store.plans) { plan in Button(plan.name) { store.submit(.setPlanItem, itemID: title.id, planID: plan.id, flag: true) } }
            if store.plans.isEmpty { Text("Create a Watch Night plan first.") }
            if let message = store.message { Text(message).font(.caption2) }
        }.navigationTitle("Add to Plan").onAppear { store.loadPlans() }.disabled(!store.canEdit)
    }
}
struct NovaWatchPlanTitlePicker: View {
    var plan: WatchNightPlan
    @EnvironmentObject private var store: NovaWatchStore
    var body: some View {
        List {
            ForEach(store.titles) { title in
                Button { store.submit(.setPlanItem, itemID: title.id, planID: plan.id, flag: true) } label: {
                    Label(title.title, systemImage: plan.entries.contains(where: { $0.titleID == title.planKey }) ? "checkmark.circle.fill" : "plus.circle")
                }.disabled(plan.entries.contains(where: { $0.titleID == title.planKey }))
            }
            Text("For titles beyond this cache, use Library & Search, open a title, then Add to Watch Night.").font(.caption2).foregroundStyle(.secondary)
        }.navigationTitle("Add Title")
    }
}

struct NovaWatchNowPlaying: View {
    @EnvironmentObject private var store: NovaWatchStore
    @State private var volume = 1.0
    @State private var editingVolume = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            List {
                if let player = store.snapshot?.player {
                    let fresh = store.live && context.date.timeIntervalSince(player.observedAt) < 20
                    Text(player.title).font(.headline)
                    Text(fresh ? (player.playing ? "Playing on iPhone" : "Paused on iPhone") : "Last known iPhone state").font(.caption).foregroundStyle(.secondary)
                    if let duration = player.duration {
                        ProgressView(value: min(player.position, duration), total: duration)
                        Text("\(Duration.seconds(player.position).formatted(.time(pattern: .hourMinuteSecond))) / \(Duration.seconds(duration).formatted(.time(pattern: .hourMinuteSecond)))").font(.caption2).monospacedDigit()
                    }
                    Button { store.submit(.setPlaying, flag: !player.playing) } label: { Label(player.playing ? "Pause" : "Resume", systemImage: player.playing ? "pause.fill" : "play.fill") }.disabled(!fresh)
                    HStack {
                        Button { store.submit(.seek, value: max(0, player.position - 15)) } label: { Image(systemName: "gobackward.15") }.accessibilityLabel("Back 15 seconds")
                        Button { store.submit(.seek, value: min(player.duration ?? player.position, player.position + 15)) } label: { Image(systemName: "goforward.15") }.accessibilityLabel("Forward 15 seconds")
                    }.disabled(!fresh || !player.canSeek || player.duration == nil)
                    if player.volume != nil {
                        VStack { Text("Player Volume").font(.caption); Slider(value: $volume, in: 0...1, onEditingChanged: { editing in editingVolume = editing; if !editing { store.submit(.setVolume, value: volume) } }).accessibilityLabel("Player volume") }
                            .disabled(!fresh).onAppear { volume = min(1, max(0, player.volume ?? 1)) }
                            .onChange(of: player.volume) { _, value in if !editingVolume { volume = min(1, max(0, value ?? 1)) } }
                    }
                } else { Text("Start a title in Nova on iPhone to use your watch as a remote.") }
                Button("Refresh Player") { store.refresh() }
                Text("Controls require Nova in the foreground on iPhone. They expire instead of playing later when disconnected.").font(.caption2).foregroundStyle(.secondary)
                if let message = store.message { Text(message).font(.caption2).foregroundStyle(.secondary) }
            }.navigationTitle("Now Playing")
        }
    }
}
struct NovaWatchSync: View {
    @EnvironmentObject private var store: NovaWatchStore
    @EnvironmentObject private var connection: NovaWatchConnectivity
    @State private var clear = false
    var body: some View {
        List {
            Text(connection.status).font(.headline)
            if let snapshot = store.snapshot {
                Text("\(snapshot.titles.count) cached / \(snapshot.totalTitles) library titles")
                Text("Last sync \(snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption2)
                if let message = snapshot.phoneMessage { Text(message).font(.caption) }
            }
            Text("\(store.pendingCount) pending changes")
            Button("Sync with iPhone") { store.refresh() }.disabled(!connection.reachable || store.blocked)
            if let message = store.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            Section("Recent Results") { ForEach(store.receipts.reversed()) { receipt in Label(receipt.message, systemImage: receipt.outcome == .applied ? "checkmark.circle" : "exclamationmark.circle").font(.caption2) } }
            Section {
                Text("Your iPhone owns the library. Watch data contains title metadata and plans, never source addresses, passwords, or private Watch Night notes.").font(.caption2)
                Button("Reset Watch Cache", role: .destructive) { clear = true }
            }
        }.navigationTitle("Sync")
            .confirmationDialog("Clear this watch cache and cancel queued edits? Changes already delivered to iPhone may still finish.", isPresented: $clear) {
                Button("Reset Watch Cache", role: .destructive) { store.resetLocalCache() }
                Button("Cancel", role: .cancel) {}
            }
    }
}
