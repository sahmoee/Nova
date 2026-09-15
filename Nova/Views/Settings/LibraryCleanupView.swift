import SwiftUI

/// Explicit user actions only: a scan never removes titles or clears watch state.
struct LibraryCleanupView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var progress: PlaybackProgressStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var kept: Set<UUID> = []
    @State private var removal: MediaItem?
    @State private var progressReset: MediaItem?
    @State private var status: String?

    private var abandoned: [MediaItem] {
        LibraryCleanup.abandoned(in: library.items).filter { !kept.contains($0.id) }
    }

    var body: some View {
        let items = abandoned
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Tidy Up").font(Theme.Font.screenTitle()).screenTitleStyle()
                    .accessibilityAddTraits(.isHeader)
                Text("Review unfinished titles you haven't played in a while.")
                    .font(.appFont(16)).foregroundStyle(.secondary)
                if let status {
                    Label(status, systemImage: "checkmark.circle")
                        .font(.appFont(15)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !kept.isEmpty {
                    Button { kept.removeAll(); status = nil } label: {
                        Label("Show kept titles (\(kept.count))", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(NovaChipButtonStyle(providesSurface: true))
                }
                if items.isEmpty {
                    ContentUnavailableView {
                        Label("All caught up", systemImage: "checkmark.circle")
                    } description: {
                        Text(kept.isEmpty ? "No older unfinished titles need a review." : "You've reviewed the remaining titles for this visit.")
                    }
                } else {
                    Text("\(items.count) \(items.count == 1 ? "title to review" : "titles to review")")
                        .font(.appFont(15, weight: .medium)).foregroundStyle(.secondary)
                    ForEach(items) { cleanupRow($0) }
                }
            }
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.vertical, Theme.Spacing.lg)
            .frame(maxWidth: Theme.contentMaxWidth(1000), alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollClipDisabled()
        .background(Theme.Colors.background.ignoresSafeArea())
        .alert("Remove from Library?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } })) {
            Button("Cancel", role: .cancel) { removal = nil }
            Button("Remove", role: .destructive) {
                guard let item = removal else { return }
                library.remove(id: item.id)
                status = "Removed \(item.seriesTitle ?? item.title) from Library."
                removal = nil
            }
        } message: { Text("\(removal?.seriesTitle ?? removal?.title ?? "This title") will leave your library. The source file stays where it is.") }
        .alert("Clear watch progress?", isPresented: Binding(get: { progressReset != nil }, set: { if !$0 { progressReset = nil } })) {
            Button("Cancel", role: .cancel) { progressReset = nil }
            Button("Clear Progress", role: .destructive) {
                guard let item = progressReset else { return }
                library.clearProgress(for: item.id)
                progress.reset(for: item.id)
                status = "Cleared progress for \(item.seriesTitle ?? item.title)."
                progressReset = nil
            }
        } message: { Text("The saved resume position for \(progressReset?.seriesTitle ?? progressReset?.title ?? "this title") will be reset.") }
    }

    private func cleanupRow(_ item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                poster(item).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.seriesTitle ?? item.title)
                        .font(.appFont(19, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(Int((item.progressFraction.isFinite ? min(1, max(0, item.progressFraction)) : 0) * 100))% watched")
                        .font(.appFont(14)).monospacedDigit()
                    Text(LibraryCleanup.staleness(item))
                        .font(.appFont(14)).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 240 : 165), spacing: 12)], alignment: .leading, spacing: 12) {
                actionButton("Keep", icon: "checkmark", title: item.title, hint: "Leave this title and its progress unchanged.") {
                    kept.insert(item.id); status = "Kept \(item.seriesTitle ?? item.title)."
                }
                actionButton("Clear Progress", icon: "gobackward", title: item.title, hint: "Review before clearing the saved resume position.") { progressReset = item }
                actionButton("Hide", icon: "eye.slash", title: item.title, hint: "Find this title again in Library's Hidden filter.") {
                    library.setHidden(true, for: [item.id]); status = "Hidden \(item.seriesTitle ?? item.title)."
                }
                actionButton("Remove", icon: "trash", title: item.title, hint: "Review before removing this title from Library.", destructive: true) { removal = item }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.cardElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func poster(_ item: MediaItem) -> some View {
        CachedAsyncImage(url: item.posterURL, maxPixel: 240) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Theme.Colors.background.overlay(Image(systemName: "film").foregroundStyle(.secondary))
        }
        .frame(width: 52, height: 78)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous))
    }

    private func actionButton(_ label: String, icon: String, title: String, hint: String,
                              destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(role: destructive ? .destructive : nil, action: action) {
            Label(label, systemImage: icon)
                .font(.appFont(14, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(NovaChipButtonStyle(providesSurface: true))
        .accessibilityLabel("\(label): \(title)")
        .accessibilityHint(hint)
    }
}
