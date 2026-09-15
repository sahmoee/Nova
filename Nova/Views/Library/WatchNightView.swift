import SwiftUI
import UniformTypeIdentifiers

struct WatchNightView: View {
    @EnvironmentObject private var library: LibraryStore
    @StateObject private var store = WatchNightStore.shared
    let openItem: (MediaItem) -> Void
    @State private var showNew = false
    @State private var showImport = false
    @State private var pendingRemoval: WatchNightPlan?
    @State private var undoRemoval: WatchNightPlan?
    @State private var query = ""
    private var plans: [WatchNightPlan] {
        store.state.plans.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.startsAt == $1.startsAt ? $0.id.uuidString < $1.id.uuidString : $0.startsAt < $1.startsAt }
    }
    var body: some View {
        WatchNightCanvas {
            Text("Build a lineup for tonight, find something that fits, and keep your own notes.").foregroundStyle(.secondary)
            Text("Plans and notes stay on this device. Export a plan to move it to another Nova device.").font(.caption).foregroundStyle(.secondary)
            if store.isLoading { ProgressView("Loading watch plans…") }
            if store.loadFailed {
                Label("Saved plans could not be opened. The original file is preserved.", systemImage: "exclamationmark.triangle")
                Button("Try loading again") { Task { await store.reload() } }.novaRowStyle()
            }
            NavigationLink { WatchNightPicker(store: store, fitOnly: true, openItem: openItem) } label: {
                Label("Find a title that fits", systemImage: "clock.badge.checkmark").frame(maxWidth: .infinity, alignment: .leading)
            }.novaRowStyle()
            NavigationLink { WatchNightCompareView(store: store, openItem: openItem) } label: {
                Label("Compare titles", systemImage: "rectangle.split.3x1").frame(maxWidth: .infinity, alignment: .leading)
            }.novaRowStyle()
            NavigationLink { WatchNightNotesView(store: store) } label: {
                Label("Private viewing notes", systemImage: "note.text").frame(maxWidth: .infinity, alignment: .leading)
            }.novaRowStyle()
            Text("Your plans · \(store.state.plans.count) / 30").font(.headline)
            TextField("Find a watch plan", text: $query).accessibilityLabel("Find a watch plan")
            if plans.isEmpty && !store.isLoading && !store.loadFailed {
                Text(query.isEmpty ? "No watch nights yet. Create a plan, then add titles from your library." : "No plans match that name.")
                    .foregroundStyle(.secondary)
                if !query.isEmpty { Button("Clear search") { query = "" }.novaRowStyle() }
            }
            ForEach(plans) { plan in
                VStack(alignment: .leading, spacing: 12) {
                    NavigationLink {
                        WatchNightPlanView(store: store, planID: plan.id, openItem: openItem)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(plan.name).font(.headline)
                            Text("\(plan.entries.count) titles · \(plan.startsAt.formatted(date: .abbreviated, time: .shortened))").font(.subheadline)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.novaRowStyle()
                    Button("Remove plan", systemImage: "trash", role: .destructive) { pendingRemoval = plan }.disabled(!store.canEdit)
                }
            }
            if let undoRemoval {
                Button("Undo removal of \(undoRemoval.name)", systemImage: "arrow.uturn.backward") {
                    Task { if await store.savePlan(undoRemoval) { self.undoRemoval = nil } }
                }.novaRowStyle().disabled(!store.canEdit)
            }
            if store.isSaving { ProgressView("Saving…") }
        }
        .navigationTitle("Watch Night")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Import", systemImage: "square.and.arrow.down") { showImport = true }.disabled(!store.canEdit || store.state.plans.count >= 30)
                Button("New plan", systemImage: "plus") { showNew = true }.disabled(!store.canEdit || store.state.plans.count >= 30)
            }
        }
        .sheet(isPresented: $showNew) { WatchNightPlanEditor(store: store, initial: WatchNightPlan(name: "")) }
        .sheet(isPresented: $showImport) { WatchNightImportView(store: store) }
        .confirmationDialog("Remove this watch plan?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }), titleVisibility: .visible) {
            Button("Remove plan", role: .destructive) {
                guard let plan = pendingRemoval else { return }
                Task {
                    if await store.update({ $0.plans.removeAll { $0.id == plan.id } }) { undoRemoval = plan }
                    pendingRemoval = nil
                }
            }
        } message: { Text("Your library titles and viewing notes stay in Nova. You can undo the removal here.") }
        .onChange(of: store.resetRevision) { _, _ in
            undoRemoval = nil; pendingRemoval = nil; showNew = false; showImport = false
        }
        .onReceive(library.$items) { store.refreshLibrary($0) }
        .watchNightErrors(store)
    }
}

private struct WatchNightCanvas<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg, content: content)
                .padding(.horizontal, Theme.Spacing.edge).padding(.vertical, Theme.Spacing.lg)
                .frame(maxWidth: Theme.contentMaxWidth(1100), alignment: .leading).frame(maxWidth: .infinity)
        }.background(Theme.Colors.background.ignoresSafeArea())
    }
}

private extension View {
    func watchNightErrors(_ store: WatchNightStore) -> some View {
        alert("Watch Night", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

private struct WatchNightPlanView: View {
    @ObservedObject var store: WatchNightStore
    let planID: UUID
    let openItem: (MediaItem) -> Void
    @State private var showEdit = false
    @State private var showAdd = false
    #if os(iOS)
    @State private var showExport = false
    @State private var document: WatchNightDocument?
    #endif
    @State private var showJSON = false
    @State private var jsonText = ""
    private var plan: WatchNightPlan? { store.state.plans.first { $0.id == planID } }
    var body: some View {
        WatchNightCanvas {
            if let plan {
                schedule(plan)
                if plan.entries.isEmpty { Text("Add titles to build your lineup. Their order becomes your viewing schedule.").foregroundStyle(.secondary) }
                ForEach(Array(plan.entries.enumerated()), id: \.element.id) { index, entry in
                    entryRow(entry, index: index, plan: plan)
                }
                Button("Add titles", systemImage: "plus") { showAdd = true }.novaRowStyle().disabled(!store.canEdit || plan.entries.count >= 40)
                Text("\(plan.entries.count) / 40 titles. Scheduling is an estimate from saved runtime; it does not start playback automatically.").font(.caption).foregroundStyle(.secondary)
            } else { Text("This plan is no longer available.").foregroundStyle(.secondary) }
        }
        .navigationTitle(plan?.name ?? "Watch Night")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Schedule", systemImage: "calendar") { showEdit = true }.disabled(!store.canEdit || plan == nil)
                Button(WatchNightLayout.isTV ? "View JSON" : "Export", systemImage: "square.and.arrow.up") { prepareExport() }.disabled(plan == nil)
            }
        }
        .sheet(isPresented: $showEdit) { if let plan { WatchNightPlanEditor(store: store, initial: plan) } }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                WatchNightPicker(store: store, fitOnly: false, openItem: openItem, addTitle: { title, remaining in
                    guard var plan = self.plan else { return false }
                    guard !plan.entries.contains(where: { $0.titleID == title.id }) else { store.error = "This title is already in the lineup."; return false }
                    plan.entries.append(title.entry(remaining: remaining))
                    return await store.savePlan(plan)
                })
            }
        }
        .sheet(isPresented: $showJSON) {
            NavigationStack {
                WatchNightCanvas {
                    Text("Read-only plan JSON. File export is available on iPhone and iPad. On Apple TV, import a plan by pasting JSON with your iPhone remote keyboard. Private notes and playback addresses are excluded.").font(.subheadline)
                    Text(jsonText).font(.caption.monospaced())
                }.navigationTitle("Plan JSON")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showJSON = false } } }
            }
        }
        #if os(iOS)
        .fileExporter(isPresented: $showExport, document: document, contentType: .json, defaultFilename: "Nova Watch Night") { result in
            if case .failure(let error) = result { store.error = error.localizedDescription }
            document = nil
        }
        #endif
        .watchNightErrors(store)
    }
    private func schedule(_ plan: WatchNightPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(plan.startsAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar").font(.headline)
            Text("\(plan.unknownCount > 0 ? "At least " : "")\(WatchNightLogic.minutes(plan.knownSeconds)) · \(plan.breakMinutes)-minute breaks")
            if let end = plan.estimatedEnd, !plan.entries.isEmpty { Text("Estimated finish · \(end.formatted(date: .abbreviated, time: .shortened))") }
            if plan.unknownCount > 0 { Label("\(plan.unknownCount) titles have unknown runtime. Finish time is unavailable.", systemImage: "questionmark.circle") }
            if plan.exceedsBudget { Label("This lineup exceeds your \(plan.availableMinutes)-minute budget.", systemImage: "exclamationmark.clock").foregroundStyle(.orange) }
            else { Text("Time available · \(plan.availableMinutes) minutes").foregroundStyle(.secondary) }
        }.padding(Theme.Spacing.md).refinedCardBackground().accessibilityElement(children: .combine)
    }
    private func entryRow(_ entry: WatchNightEntry, index: Int, plan: WatchNightPlan) -> some View {
        let matched = WatchNightLogic.matching(entry, in: store.titles)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                WatchNightPoster(url: matched?.posterURL)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(index + 1). \(entry.title)").font(.headline)
                    Text(WatchNightLogic.minutes(entry.estimatedSeconds) + (entry.usesRemainingTime ? " remaining" : "")).foregroundStyle(.secondary)
                    if let start = plan.startDate(for: index) { Text(start.formatted(date: .omitted, time: .shortened)).font(.subheadline.monospacedDigit()) }
                    if matched == nil { Label("No unique match in this device’s library", systemImage: "link.badge.plus").font(.caption) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: WatchNightLayout.isTV ? 230 : 140))], spacing: 12) {
                if let matched, let item = store.mediaItem(for: matched.id) {
                    Button("Open title", systemImage: "play.rectangle") { openItem(item) }.novaRowStyle()
                    NavigationLink { WatchNightNoteView(store: store, titleID: matched.id, title: matched.title) } label: { Label("Viewing note", systemImage: "note.text") }.novaRowStyle()
                    Button("Update runtime", systemImage: "arrow.clockwise") {
                        Task {
                            guard var next = self.plan, let currentIndex = next.entries.firstIndex(where: { $0.id == entry.id }) else { return }
                            next.entries[currentIndex].estimatedSeconds = entry.usesRemainingTime ? matched.remaining ?? matched.duration : matched.duration
                            _ = await store.savePlan(next)
                        }
                    }.novaRowStyle().disabled(!store.canEdit)
                }
                Button("Move earlier", systemImage: "arrow.up") { move(entry, by: -1) }.novaRowStyle().disabled(index == 0 || !store.canEdit)
                Button("Move later", systemImage: "arrow.down") { move(entry, by: 1) }.novaRowStyle().disabled(index == plan.entries.count - 1 || !store.canEdit)
                Button("Remove title", systemImage: "minus.circle", role: .destructive) {
                    Task { guard var next = self.plan else { return }; next.entries.removeAll { $0.id == entry.id }; _ = await store.savePlan(next) }
                }.novaRowStyle().disabled(!store.canEdit)
            }
        }.padding(Theme.Spacing.md).refinedCardBackground()
    }
    private func move(_ entry: WatchNightEntry, by amount: Int) {
        Task {
            guard var next = plan, let index = next.entries.firstIndex(where: { $0.id == entry.id }), next.entries.indices.contains(index + amount) else { return }
            next.entries.swapAt(index, index + amount); _ = await store.savePlan(next)
        }
    }
    private func prepareExport() {
        guard let plan else { return }
        do {
            let data = try WatchNightPortablePlan.encode(plan)
            #if os(iOS)
            document = WatchNightDocument(data: data); showExport = true
            #else
            jsonText = String(decoding: data, as: UTF8.self); showJSON = true
            #endif
        } catch { store.error = error.localizedDescription }
    }
}

private struct WatchNightPlanEditor: View {
    @ObservedObject var store: WatchNightStore
    let initial: WatchNightPlan
    @State private var draft: WatchNightPlan
    @Environment(\.dismiss) private var dismiss
    init(store: WatchNightStore, initial: WatchNightPlan) { self.store = store; self.initial = initial; _draft = State(initialValue: initial) }
    private var valid: Bool { (try? draft.validate()) != nil }
    var body: some View {
        NavigationStack {
            WatchNightCanvas {
                TextField("Plan name", text: $draft.name).accessibilityLabel("Watch plan name")
                Text("\(draft.name.count) / 100 characters").font(.caption).foregroundStyle(.secondary)
                #if os(iOS)
                DatePicker("Starts", selection: $draft.startsAt, in: Date(timeIntervalSince1970: -2_208_988_800)...Date(timeIntervalSince1970: 7_258_118_400))
                #else
                Text("Starts · \(draft.startsAt.formatted(date: .abbreviated, time: .shortened))")
                Menu("Set start time") {
                    ForEach([0, 15, 30, 60, 120], id: \.self) { value in
                        Button(value == 0 ? "Start now" : "In \(value) minutes") { draft.startsAt = Date().addingTimeInterval(Double(value * 60)) }
                    }
                }.novaRowStyle()
                #endif
                Picker("Time available", selection: $draft.availableMinutes) {
                    ForEach(Array(Set([15,30,45,60,90,120,180,240,360,480,720,1440,draft.availableMinutes])).sorted(), id: \.self) { Text("\($0) minutes").tag($0) }
                }
                Picker("Break between titles", selection: $draft.breakMinutes) {
                    ForEach(Array(Set([0,5,10,15,20,30,60,draft.breakMinutes])).sorted(), id: \.self) { Text("\($0) minutes").tag($0) }
                }
                Text("Scheduling uses known runtimes and your chosen breaks. Nova will not start a title or send reminders automatically.").font(.caption).foregroundStyle(.secondary)
                if !valid { Text("Enter a plan name of 1–100 characters before saving.").foregroundStyle(.secondary) }
                if store.isSaving { ProgressView("Saving plan…") }
            }.navigationTitle(initial.name.isEmpty ? "New watch plan" : "Plan & schedule")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isSaving) }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { if await store.savePlan(draft) { dismiss() } } }.disabled(!valid || !store.canEdit) }
                }
                .interactiveDismissDisabled(store.isSaving).watchNightErrors(store)
                .onChange(of: store.resetRevision) { _, _ in dismiss() }
        }
    }
}

private struct WatchNightPicker: View {
    @ObservedObject var store: WatchNightStore
    let fitOnly: Bool
    let openItem: (MediaItem) -> Void
    var addTitle: ((WatchNightTitle, Bool) async -> Bool)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var minutes = 120
    @State private var useRemaining = true
    @State private var unwatchedOnly = false
    @State private var onlyMovies = false
    @State private var limit = 40
    @State private var results: [WatchNightTitle] = []
    @State private var searching = false
    private var searchKey: String { "\(store.titleRevision)|\(query)|\(minutes)|\(useRemaining)|\(unwatchedOnly)|\(onlyMovies)" }
    private func updateResults() async {
        searching = true
        do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
        let snapshot = store.titles
        let query = self.query, minutes = self.minutes, remaining = useRemaining
        let onlyUnwatched = unwatchedOnly, onlyMovies = self.onlyMovies, fitting = fitOnly
        let child = Task.detached(priority: .userInitiated) {
            let titles = fitting ? WatchNightLogic.fitting(snapshot, minutes: minutes, useRemaining: remaining,
                unwatchedOnly: onlyUnwatched, isCancelled: { Task.isCancelled }) : snapshot
            var matches: [WatchNightTitle] = []
            for title in titles {
                if Task.isCancelled { break }
                if (!onlyMovies || !title.isSeries) && (!onlyUnwatched || !title.isWatched) && (query.isEmpty || title.title.localizedCaseInsensitiveContains(query)) { matches.append(title) }
            }
            return matches
        }
        let found = await withTaskCancellationHandler(operation: { await child.value }, onCancel: { child.cancel() })
        guard !Task.isCancelled else { return }
        results = found; searching = false; limit = 40
    }
    var body: some View {
        WatchNightCanvas {
            TextField("Find a library title", text: Binding(get: { query }, set: { query = String($0.prefix(200)) })).accessibilityLabel("Find a library title")
            if fitOnly {
                Picker("Time available", selection: $minutes) { ForEach([15,30,45,60,90,120,150,180,240,360], id: \.self) { Text("\($0) minutes").tag($0) } }
            }
            Toggle("Use remaining time for started titles", isOn: $useRemaining)
            Toggle("Unwatched only", isOn: $unwatchedOnly)
            Toggle("Movies only", isOn: $onlyMovies)
            if store.isIndexing || searching { ProgressView(store.isIndexing ? "Reading library metadata…" : "Finding titles…") }
            Text("\(results.count) matching titles").font(.headline)
            if fitOnly { Text("Closest fit appears first. Titles without a saved runtime and live channels are excluded; runtime estimates do not guarantee source availability.").font(.caption).foregroundStyle(.secondary) }
            if results.isEmpty && !store.isIndexing && !searching {
                Text(store.titles.isEmpty ? "Your visible on-demand library is empty. Add a source or save a title first." : "No titles match. Increase the available time or clear your filters.").foregroundStyle(.secondary)
                Button("Reset filters") { query = ""; minutes = 120; unwatchedOnly = false; onlyMovies = false; useRemaining = true }.novaRowStyle()
            }
            ForEach(results.prefix(limit)) { title in
                if let addTitle {
                    Button { Task { if await addTitle(title, useRemaining) { dismiss() } } } label: { WatchNightTitleRow(title: title, remaining: useRemaining) }
                        .novaRowStyle().disabled(!store.canEdit)
                } else {
                    NavigationLink { WatchNightTitleActions(store: store, title: title, openItem: openItem) } label: { WatchNightTitleRow(title: title, remaining: useRemaining) }.novaRowStyle()
                }
            }
            if results.count > limit { Button("Show \(min(40, results.count - limit)) more titles") { limit += 40 }.novaRowStyle() }
        }.navigationTitle(fitOnly ? "Fits your time" : "Choose a title")
            .task(id: searchKey) { await updateResults() }
            .onChange(of: query) { _, _ in limit = 40 }
            .watchNightErrors(store)
            .toolbar { if addTitle != nil { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } } }
    }
}

private struct WatchNightTitleActions: View {
    @ObservedObject var store: WatchNightStore
    let title: WatchNightTitle
    let openItem: (MediaItem) -> Void
    @State private var addedTo: String?
    var body: some View {
        WatchNightCanvas {
            WatchNightTitleRow(title: title, remaining: true)
            if let item = store.mediaItem(for: title.id) { Button("Open title", systemImage: "play.rectangle") { openItem(item) }.novaRowStyle() }
            NavigationLink { WatchNightNoteView(store: store, titleID: title.id, title: title.title) } label: { Label("Private viewing note", systemImage: "note.text") }.novaRowStyle()
            Text("Add to a plan").font(.headline)
            if store.state.plans.isEmpty { Text("Create a Watch Night plan to build a lineup with this title.").foregroundStyle(.secondary) }
            ForEach(store.state.plans) { plan in
                let added = plan.entries.contains { $0.titleID == title.id }
                Button(added ? "Added to \(plan.name)" : plan.name, systemImage: added ? "checkmark.circle" : "plus.circle") {
                    Task {
                        guard var next = store.state.plans.first(where: { $0.id == plan.id }), !next.entries.contains(where: { $0.titleID == title.id }) else { return }
                        next.entries.append(title.entry(remaining: true))
                        if await store.savePlan(next) { addedTo = next.name }
                    }
                }.novaRowStyle().disabled(added || plan.entries.count >= 40 || !store.canEdit).accessibilityAddTraits(added ? [.isSelected] : [])
            }
            if let addedTo { Label("Added to \(addedTo)", systemImage: "checkmark.circle").accessibilityLabel("Added to \(addedTo)") }
        }.navigationTitle(title.title).watchNightErrors(store)
    }
}

private struct WatchNightTitleRow: View {
    let title: WatchNightTitle
    var remaining = false
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            WatchNightPoster(url: title.posterURL)
            VStack(alignment: .leading, spacing: 6) {
                Text(title.title).font(.headline)
                Text([title.year.map(String.init), title.isSeries ? "Episode / series" : "Movie", title.source].compactMap { $0 }.joined(separator: " · ")).font(.caption)
                Text(WatchNightLogic.minutes(remaining ? title.remaining ?? title.duration : title.duration) + (remaining && title.remaining != nil ? " remaining" : "")).font(.subheadline)
                if title.isWatched { Label("Watched", systemImage: "checkmark.circle").font(.caption) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityElement(children: .combine)
    }
}

private struct WatchNightPoster: View {
    let url: URL?
    var body: some View {
        CachedAsyncImage(url: url, maxPixel: 300) { $0.resizable().scaledToFill() } placeholder: {
            Rectangle().fill(Color.white.opacity(0.08)).overlay { Image(systemName: "film").foregroundStyle(.secondary) }
        }.frame(width: WatchNightLayout.isTV ? 90 : 54, height: WatchNightLayout.isTV ? 135 : 81).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.poster)).accessibilityHidden(true)
    }
}

private struct WatchNightCompareView: View {
    @ObservedObject var store: WatchNightStore
    let openItem: (MediaItem) -> Void
    @State private var selected: [String] = []
    @State private var showPicker = false
    private var titles: [WatchNightTitle] { selected.compactMap { id in store.titles.first { $0.id == id } } }
    var body: some View {
        WatchNightCanvas {
            Text("Compare up to three titles using metadata already in your library.").foregroundStyle(.secondary)
            if titles.isEmpty { Text("Choose two or three possibilities to compare runtime, remaining time, source, and watch status.").foregroundStyle(.secondary) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: WatchNightLayout.isTV ? 320 : 260))], alignment: .leading, spacing: Theme.Spacing.lg) {
                ForEach(titles) { title in
                    VStack(alignment: .leading, spacing: 16) {
                        WatchNightTitleRow(title: title)
                        Label("Remaining · \(WatchNightLogic.minutes(title.remaining ?? title.duration))", systemImage: "clock")
                        Label(title.isFavorite ? "Favorite" : "Not favorited", systemImage: title.isFavorite ? "star.fill" : "star")
                        NavigationLink { WatchNightTitleActions(store: store, title: title, openItem: openItem) } label: { Text("Title options") }.novaRowStyle()
                        Button("Remove from comparison", systemImage: "minus.circle") { selected.removeAll { $0 == title.id } }.novaRowStyle()
                    }.padding(Theme.Spacing.md).refinedCardBackground()
                }
            }
            Button("Choose a title", systemImage: "plus") { showPicker = true }.novaRowStyle().disabled(titles.count >= 3)
        }.navigationTitle("Compare titles")
            .sheet(isPresented: $showPicker) {
                NavigationStack {
                    WatchNightPicker(store: store, fitOnly: false, openItem: openItem, addTitle: { title, _ in
                        guard !selected.contains(title.id) else { store.error = "This title is already in your comparison."; return false }
                        selected.append(title.id); return true
                    })
                }
            }
            .onChange(of: store.titles) { _, values in selected.removeAll { id in !values.contains { $0.id == id } } }
    }
}

private struct WatchNightNotesView: View {
    @ObservedObject var store: WatchNightStore
    @State private var query = ""
    @State private var showPicker = false
    @State private var selected: WatchNightTitle?
    @State private var pickedTitle: WatchNightTitle?
    private var notes: [WatchNightNote] { store.state.notes.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }.sorted { $0.modifiedAt > $1.modifiedAt } }
    var body: some View {
        WatchNightCanvas {
            Text("Private notes stay on this device and are never included in a Watch Night plan export.").foregroundStyle(.secondary)
            TextField("Find a title with notes", text: $query).accessibilityLabel("Find a title with notes")
            if notes.isEmpty { Text(query.isEmpty ? "Remember a recommendation, a discussion point, or what you thought after watching." : "No notes match this title.").foregroundStyle(.secondary) }
            ForEach(notes) { note in
                NavigationLink { WatchNightNoteView(store: store, titleID: note.id, title: note.title) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(note.title).font(.headline)
                        Label(note.containsSpoilers ? "Spoilers hidden" : "Viewing note", systemImage: note.containsSpoilers ? "eye.slash" : "note.text").font(.caption)
                        Text(note.modifiedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.novaRowStyle()
            }
            Button("Add a viewing note", systemImage: "plus") { showPicker = true }.novaRowStyle().disabled(!store.canEdit || store.state.notes.count >= 300)
        }.navigationTitle("Private notes")
            .sheet(isPresented: $showPicker, onDismiss: { selected = pickedTitle; pickedTitle = nil }) {
                NavigationStack {
                    WatchNightPicker(store: store, fitOnly: false, openItem: { _ in }, addTitle: { title, _ in pickedTitle = title; return true })
                }
            }
            .navigationDestination(item: $selected) { title in WatchNightNoteView(store: store, titleID: title.id, title: title.title, editOnAppear: true) }
    }
}

private struct WatchNightNoteView: View {
    @ObservedObject var store: WatchNightStore
    @Environment(\.scenePhase) private var scenePhase
    let titleID: String
    let title: String
    var editOnAppear = false
    @State private var revealed = false
    @State private var editing = false
    @State private var confirmDelete = false
    private var note: WatchNightNote? { store.state.notes.first { $0.id == titleID } }
    var body: some View {
        WatchNightCanvas {
            Text(title).font(.headline)
            if let note {
                if note.containsSpoilers && !revealed {
                    Label("This note contains spoilers.", systemImage: "eye.slash")
                    Button("Reveal note") { revealed = true }.novaRowStyle()
                } else {
                    Text(note.text).frame(maxWidth: .infinity, alignment: .leading)
                    if note.containsSpoilers { Button("Hide spoilers") { revealed = false }.novaRowStyle() }
                }
                Text("Updated \(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                Button("Edit note", systemImage: "pencil") { editing = true }.novaRowStyle().disabled(!store.canEdit)
                Button("Delete note", systemImage: "trash", role: .destructive) { confirmDelete = true }.novaRowStyle().disabled(!store.canEdit)
            } else {
                Text("No note yet. Save your thoughts privately without changing watch history or ratings.").foregroundStyle(.secondary)
                Button("Write a note", systemImage: "square.and.pencil") { editing = true }.novaRowStyle().disabled(!store.canEdit)
            }
        }.navigationTitle("Viewing note")
            .sheet(isPresented: $editing) { WatchNightNoteEditor(store: store, initial: note ?? WatchNightNote(id: titleID, title: title, text: "")) }
            .confirmationDialog("Delete this private note?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete note", role: .destructive) { Task { _ = await store.update { $0.notes.removeAll { $0.id == titleID } } } }
            }
            .onAppear { revealed = false; if editOnAppear && note == nil { editing = true } }
            .onDisappear { revealed = false }
            .onChange(of: scenePhase) { _, phase in if phase != .active { revealed = false } }
            .watchNightErrors(store)
    }
}

private struct WatchNightNoteEditor: View {
    @ObservedObject var store: WatchNightStore
    @State private var draft: WatchNightNote
    @Environment(\.dismiss) private var dismiss
    init(store: WatchNightStore, initial: WatchNightNote) { self.store = store; _draft = State(initialValue: initial) }
    var body: some View {
        NavigationStack {
            WatchNightCanvas {
                Text(draft.title).font(.headline)
                TextField("Your thoughts", text: $draft.text, axis: .vertical).accessibilityLabel("Private viewing note")
                Text("\(draft.text.count) / 4,000 characters").font(.caption).foregroundStyle(.secondary)
                Toggle("Contains spoilers", isOn: $draft.containsSpoilers)
                Text("Spoiler notes stay concealed until you choose Reveal. Private notes are excluded from plan exports.").font(.caption).foregroundStyle(.secondary)
            }.navigationTitle("Edit viewing note")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isSaving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { draft.text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines); draft.modifiedAt = Date(); if await store.saveNote(draft) { dismiss() } } }
                            .disabled(!store.canEdit || draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.text.count > 4000)
                    }
                }.interactiveDismissDisabled(store.isSaving).watchNightErrors(store)
                .onChange(of: store.resetRevision) { _, _ in dismiss() }
        }
    }
}

#if os(iOS)
private struct WatchNightDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
#endif

private struct WatchNightImportView: View {
    @ObservedObject var store: WatchNightStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var showFiles = false
    @State private var candidate: WatchNightPlan?
    @State private var error: String?
    @State private var reading = false
    private var unmatched: Int { candidate?.entries.filter { WatchNightLogic.matching($0, in: store.titles) == nil }.count ?? 0 }
    var body: some View {
        NavigationStack {
            WatchNightCanvas {
                Text("Import a Nova Watch Night plan. Review the lineup before saving a new copy. Private notes and playback access never transfer with a plan.").foregroundStyle(.secondary)
                #if os(iOS)
                Button("Choose JSON file", systemImage: "doc") { showFiles = true }.novaRowStyle().disabled(reading)
                #endif
                TextField("Paste Watch Night JSON", text: $text, axis: .vertical).accessibilityLabel("Watch Night plan JSON").disabled(reading)
                Button("Preview pasted plan") {
                    let data = Data(text.utf8)
                    Task {
                        reading = true; defer { reading = false }
                        do {
                            candidate = try await Task.detached(priority: .userInitiated) { try WatchNightPortablePlan.decode(data) }.value
                            error = nil
                        } catch { self.error = "This plan could not be read. \(error.localizedDescription)"; candidate = nil }
                    }
                }.novaRowStyle().disabled(text.isEmpty || text.utf8.count > WatchNightPortablePlan.maximumBytes || reading)
                if text.utf8.count > WatchNightPortablePlan.maximumBytes { Text("The pasted plan exceeds 512 KB.").foregroundStyle(.orange) }
                if reading { ProgressView("Reading plan…") }
                if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                if let candidate {
                    Text(candidate.name).font(.headline)
                    Text("\(candidate.entries.count) titles · \(candidate.availableMinutes)-minute budget · \(candidate.breakMinutes)-minute breaks")
                    if unmatched > 0 { Text("\(unmatched) titles have no unique local match. They stay in the plan, but require adding or identifying those titles in your library.").foregroundStyle(.secondary) }
                    ForEach(candidate.entries) { entry in Text("• \(entry.title) · \(WatchNightLogic.minutes(entry.estimatedSeconds))") }
                    Button("Import as a new plan", systemImage: "square.and.arrow.down") {
                        Task { if await store.savePlan(candidate) { dismiss() } }
                    }.novaRowStyle().disabled(!store.canEdit || store.state.plans.count >= 30)
                    if store.state.plans.count >= 30 { Text("30-plan limit reached. Remove an unused plan before importing.").foregroundStyle(.secondary) }
                }
            }.navigationTitle("Import watch plan")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isSaving) } }
                .interactiveDismissDisabled(store.isSaving)
                .onChange(of: store.resetRevision) { _, _ in dismiss() }
                #if os(iOS)
                .fileImporter(isPresented: $showFiles, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                    Task {
                        reading = true; defer { reading = false }
                        do { guard let url = try result.get().first else { return }; candidate = try await WatchNightStore.readPortable(url); error = nil }
                        catch { self.error = "This plan could not be read. \(error.localizedDescription)"; candidate = nil }
                    }
                }
                #endif
                .onChange(of: text) { _, _ in candidate = nil }
                .watchNightErrors(store)
        }
    }
}

private enum WatchNightLayout {
    static var isTV: Bool {
        #if os(tvOS)
        true
        #else
        false
        #endif
    }
}
