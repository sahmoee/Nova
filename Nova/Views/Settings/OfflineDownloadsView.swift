import SwiftUI

struct OfflineDownloadsView: View {
    @EnvironmentObject private var env: AppEnvironment
    var body: some View { OfflineDownloadsContent(manager: env.downloads) }
}

private struct OfflineDownloadsContent: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", active = "Active", paused = "Paused", complete = "Complete", failed = "Failed"
        var id: String { rawValue }
    }
    enum Sort: String, CaseIterable, Identifiable {
        case newest = "Newest", oldest = "Oldest", title = "Title", largest = "Largest"
        var id: String { rawValue }
    }

    @ObservedObject var manager: DownloadManager
    @State private var searchText = ""
    @State private var filter: Filter = .all
    @State private var sort: Sort = .newest
    @State private var pendingRemoval: OfflineDownload?
    @State private var showRemoveCompleted = false

    private var visibleDownloads: [OfflineDownload] {
        manager.downloads
            .filter { download in
                let matchesSearch = searchText.isEmpty || download.title.localizedCaseInsensitiveContains(searchText)
                let matchesFilter: Bool
                switch filter {
                case .all: matchesFilter = true
                case .active: matchesFilter = download.state == .queued || download.state == .downloading
                case .paused: matchesFilter = download.state == .paused
                case .complete: matchesFilter = download.state == .complete
                case .failed: matchesFilter = download.state == .failed
                }
                return matchesSearch && matchesFilter
            }
            .sorted {
                switch sort {
                case .newest: return $0.createdAt > $1.createdAt
                case .oldest: return $0.createdAt < $1.createdAt
                case .title: return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                case .largest: return $0.receivedBytes > $1.receivedBytes
                }
            }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
                header
                if !manager.isNetworkAvailable { offlineBanner }
                summary
                controls

                if manager.downloads.isEmpty {
                    EmptyStateView(systemImage: "arrow.down.circle", title: "Nothing downloaded",
                        message: "Use Download on an authorized direct or local media item to keep it offline.")
                        .frame(minHeight: 320)
                } else if visibleDownloads.isEmpty {
                    EmptyStateView(systemImage: "line.3.horizontal.decrease.circle", title: "No matching downloads",
                        message: "Change the search or filter to see the rest of your queue.",
                        actionTitle: "Show All", actionSystemImage: "arrow.counterclockwise") {
                            searchText = ""; filter = .all
                        }.frame(minHeight: 280)
                } else {
                    ForEach(visibleDownloads) { row($0) }
                }
            }
            .padding(Theme.Spacing.edge)
            .frame(maxWidth: Theme.contentMaxWidth(1400), alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .searchable(text: $searchText, prompt: "Search downloads")
        .background(Theme.Colors.appBackground.ignoresSafeArea())
        .confirmationDialog("Remove this download?", isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }
        ), titleVisibility: .visible) {
            Button("Remove Download", role: .destructive) {
                if let id = pendingRemoval?.id { manager.remove(id) }; pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { Text("The offline file will be removed from this device.") }
        .confirmationDialog("Remove all completed downloads?", isPresented: $showRemoveCompleted,
                            titleVisibility: .visible) {
            Button("Remove Completed", role: .destructive) { manager.removeCompleted() }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { manager.reconcileFiles() }
    }

    private var header: some View {
        ScreenHeader(title: "Offline Downloads",
            subtitle: "\(format(manager.storageBytes)) used" +
                (manager.availableStorageBytes.map { " · \(format($0)) available" } ?? "")) {
            Menu {
                if manager.activeCount + manager.queuedCount > 0 { Button("Pause All", systemImage: "pause.fill", action: manager.pauseAll) }
                if manager.downloads.contains(where: { $0.state == .paused }) { Button("Resume All", systemImage: "play.fill", action: manager.resumeAll) }
                if manager.failedCount > 0 { Button("Retry Failed", systemImage: "arrow.clockwise", action: manager.retryAllFailed) }
                if manager.completedCount > 0 {
                    Divider(); Button("Remove Completed", systemImage: "trash", role: .destructive) { showRemoveCompleted = true }
                }
            } label: {
                Label("Queue Actions", systemImage: "ellipsis.circle")
                    .font(.appFont(16, weight: .semibold)).foregroundStyle(Theme.Colors.accent)
            }
        }
    }

    private var offlineBanner: some View {
        Label("Downloads are waiting for a network connection and will resume automatically.", systemImage: "wifi.slash")
            .font(.appFont(15, weight: .medium)).foregroundStyle(Theme.Colors.warning)
            .padding(Theme.Spacing.md).frame(maxWidth: .infinity, alignment: .leading).softCard()
            .accessibilityAddTraits(.isStaticText)
    }

    private var summary: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.isCompact ? 135 : 190), spacing: Theme.Spacing.sm)],
                  spacing: Theme.Spacing.sm) {
            metric("Active", manager.activeCount + manager.queuedCount, "arrow.down.circle.fill", Theme.Colors.accent)
            metric("Paused", manager.downloads.filter { $0.state == .paused }.count, "pause.circle.fill", Theme.Colors.warning)
            metric("Complete", manager.completedCount, "checkmark.circle.fill", Theme.Colors.success)
            metric("Needs attention", manager.failedCount, "exclamationmark.triangle.fill", Theme.Colors.error)
        }
    }

    private func metric(_ title: String, _ value: Int, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon).font(.appFont(22)).foregroundStyle(color).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)").font(.appFont(22, weight: .bold)).foregroundStyle(Theme.Colors.textPrimary)
                Text(title).font(.appFont(13)).foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md).softCard().accessibilityElement(children: .combine)
    }

    private var controls: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Picker("Status", selection: $filter) { ForEach(Filter.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.menu)
            Picker("Sort", selection: $sort) { ForEach(Sort.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.menu)
            Spacer()
            if manager.activeCount + manager.queuedCount > 0 {
                ProgressView(value: manager.aggregateProgress).tint(Theme.Colors.accent)
                    .frame(maxWidth: Theme.isCompact ? 90 : 220)
                    .accessibilityLabel("Overall download progress")
                    .accessibilityValue(manager.aggregateProgress.formatted(.percent.precision(.fractionLength(0))))
            }
        }
        .font(.appFont(15, weight: .medium))
    }

    private func row(_ download: OfflineDownload) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon(download.state)).font(.appFont(26)).foregroundStyle(color(download.state))
                .frame(width: 44).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(download.title).font(.appFont(19, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if [.downloading, .queued, .paused].contains(download.state) {
                    ProgressView(value: download.progress).tint(Theme.Colors.accent)
                        .accessibilityLabel("Download progress")
                        .accessibilityValue(download.progress.formatted(.percent.precision(.fractionLength(0))))
                }
                Text(detail(download)).font(.appFont(14)).foregroundStyle(download.state == .failed ? Theme.Colors.error : Theme.Colors.textTertiary)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                if download.state == .complete, let date = download.completedAt {
                    Text("Finished \(date.formatted(.relative(presentation: .named)))")
                        .font(.appFont(13)).foregroundStyle(Theme.Colors.textQuaternary)
                }
            }
            Spacer(minLength: Theme.Spacing.sm)
            actionButtons(download)
        }
        .padding(Theme.Spacing.sm)
        .softCard()
        .contextMenu {
            if download.state == .downloading { Button("Pause", systemImage: "pause.fill") { manager.pause(download.id) } }
            if download.state == .paused { Button("Resume", systemImage: "play.fill") { manager.resume(download.id) } }
            if download.state == .failed { Button("Retry", systemImage: "arrow.clockwise") { manager.retry(download.id) } }
            Button("Remove", systemImage: "trash", role: .destructive) { pendingRemoval = download }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func actionButtons(_ download: OfflineDownload) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            if download.state == .downloading { compactButton("Pause", "pause.fill") { manager.pause(download.id) } }
            else if download.state == .paused { compactButton("Resume", "play.fill") { manager.resume(download.id) } }
            else if download.state == .failed { compactButton("Retry", "arrow.clockwise") { manager.retry(download.id) } }
            Button { pendingRemoval = download } label: {
                Image(systemName: "trash").frame(minWidth: 44, minHeight: 44)
            }.buttonStyle(.plain).foregroundStyle(Theme.Colors.error).accessibilityLabel("Remove \(download.title)")
        }
    }

    private func compactButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if Theme.isCompact { Image(systemName: icon) }
            else { Label(title, systemImage: icon) }
        }
            .buttonStyle(.plain).foregroundStyle(Theme.Colors.accent).frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(title)
    }

    private func detail(_ download: OfflineDownload) -> String {
        if let error = download.errorMessage { return error }
        var parts = [download.state.rawValue.capitalized, format(download.receivedBytes)]
        if let expected = download.expectedBytes { parts[1] += " of \(format(expected))" }
        if let rate = download.bytesPerSecond, rate > 0 { parts.append("\(format(Int64(rate)))/s") }
        if let eta = download.estimatedSecondsRemaining, eta.isFinite, eta > 0 {
            parts.append("about \(Duration.seconds(eta).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))) left")
        }
        if (download.retryCount ?? 0) > 0 { parts.append("retry \(download.retryCount!)") }
        return parts.joined(separator: " · ")
    }
    private func format(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    private func icon(_ state: OfflineDownload.State) -> String {
        switch state { case .queued, .downloading: "arrow.down.circle.fill"; case .paused: "pause.circle.fill"; case .complete: "checkmark.circle.fill"; case .failed: "exclamationmark.triangle.fill" }
    }
    private func color(_ state: OfflineDownload.State) -> Color {
        switch state { case .queued, .downloading: Theme.Colors.accent; case .paused: Theme.Colors.warning; case .complete: Theme.Colors.success; case .failed: Theme.Colors.error }
    }
}
