//
//  SMBBrowseView.swift
//  Nova
//
//  Browses an SMB share's folders/files, separates them, lets the user add a
//  video to the library or play it. Uses SMBService (mock in Phase 1/2).
//

import SwiftUI

struct SMBBrowseView: View {
    let share: SMBShare

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var path: String
    @State private var items: [RemoteFileItem] = []
    @State private var state: ViewState = .loading
    @State private var selectedItem: MediaItem?
    @State private var shares: [String] = []          // server's shares when none chosen yet
    @State private var activeShareName: String        // the share we're browsing
    @State private var importing = false              // Add All in progress
    @State private var pathInput = ""                 // quick path-jump field
    @FocusState private var pathFieldFocused: Bool

    enum ViewState: Equatable { case loading, loaded, error(String) }

    init(share: SMBShare) {
        self.share = share
        _path = State(initialValue: share.path ?? "/")
        _activeShareName = State(initialValue: share.shareName)
    }

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()

            switch state {
            case .loading:
                LoadingView(message: activeShareName.isEmpty
                            ? "Connecting to \(share.host)…"
                            : "Loading \(activeShareName)…")
            case .error(let message):
                ErrorStateView(message: message, onRetry: { Task { await load() } }, onBack: { dismiss() })
            case .loaded:
                content
            }
        }
        .navigationDestination(item: $selectedItem) { item in
            PlayerView(item: item)
        }
        .task { await load() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(share.displayName)
                    .font(Theme.Font.screenTitle())
                    .screenTitleStyle()
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(activeShareName.isEmpty ? "smb://\(share.host)" : path)
                    .font(.appFont(20))
                    .foregroundStyle(Theme.Colors.textSecondary)

                // Browsing the server's shares (no share chosen yet).
                if activeShareName.isEmpty {
                    if shares.isEmpty {
                        Text("No shared folders found on this server.")
                            .font(.appFont(20))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .padding(.top, Theme.Spacing.lg)
                    } else {
                        sectionHeader("Shared Folders")
                        ForEach(shares, id: \.self) { name in
                            Button { Task { await selectShare(name) } } label: {
                                row(icon: "externaldrive.fill", title: name, accent: Theme.Colors.accent)
                            }.buttonStyle(.plain)
                        }
                    }
                } else {
                    let folders = items.filter { $0.isDirectory }
                    let files = items.filter { !$0.isDirectory && $0.isPlayableVideo }

                    // Quick path jump: type or paste a folder path and go straight there,
                    // instead of clicking through each folder.
                    pathJumpField

                    if !folders.isEmpty {
                        sectionHeader("Folders")
                        ForEach(folders) { folder in
                            Button { Task { await open(folder) } } label: {
                                row(icon: "folder.fill", title: folder.name, accent: Theme.Colors.accent)
                            }.buttonStyle(.plain)
                        }
                    }

                    if !files.isEmpty {
                        HStack {
                            sectionHeader("Videos")
                            Spacer()
                            // Add every video in this folder to the library in one tap.
                            FocusableButton(title: importing ? "Adding…" : "Add All (\(files.count))",
                                            systemImage: "plus.rectangle.on.folder") {
                                Task { await addAll(files) }
                            }
                            .frame(maxWidth: 260)
                            .disabled(importing)
                        }
                        ForEach(files) { file in
                            fileRow(file)
                        }
                    }

                    if folders.isEmpty && files.isEmpty {
                        Text("No playable videos in this folder.")
                            .font(.appFont(20))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .padding(.top, Theme.Spacing.lg)
                    }
                }
            }
            .padding(Theme.Spacing.edge)
        }
    }

    private var pathJumpField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Go to folder path")
                .font(.appFont(16, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(Theme.Colors.textTertiary)
                TextField("/Movies/Action", text: $pathInput)
                    .textFieldStyle(.plain)
                    .focused($pathFieldFocused)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    #endif
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .onSubmit { Task { await jumpToPath() } }
                if !pathInput.isEmpty {
                    Button { pathInput = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Colors.textTertiary)
                    }.buttonStyle(.plain)
                }
                Button { Task { await jumpToPath() } } label: {
                    Text("Go").font(.appFont(16, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.accent)
                .disabled(pathInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity)
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { pathFieldFocused = true }
        }
        .padding(.bottom, Theme.Spacing.sm)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.sectionTitle())
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.top, Theme.Spacing.md)
    }

    private func fileRow(_ file: RemoteFileItem) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "film.fill")
                .font(.appFont(26))
                .foregroundStyle(Theme.Colors.accentSecondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(.appFont(22, weight: .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let size = file.size {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.appFont(16))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            Spacer()
            FocusableButton(title: "Play", systemImage: "play.fill", prominent: true) {
                Task { await playFile(file) }
            }
            .frame(maxWidth: Theme.isCompact ? .infinity : 200)
            FocusableButton(title: "Add", systemImage: "plus") {
                Task { await addFile(file) }
            }
            .frame(maxWidth: Theme.isCompact ? .infinity : 180)
        }
        .padding(Theme.Spacing.md)
        .refinedCardBackground()
    }

    private func row(icon: String, title: String, accent: Color) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon).font(.appFont(26)).foregroundStyle(accent)
            Text(title).font(.appFont(22, weight: .medium))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.md)
        .refinedCardBackground()
    }

    // MARK: - Actions

    private func load() async {
        state = .loading
        do {
            // No share chosen yet -> list the server's shares to pick from.
            if activeShareName.isEmpty {
                shares = try await environment.smb.listShares(
                    host: share.host,
                    username: share.username,
                    keychainAccount: share.keychainAccount
                )
                state = .loaded
                return
            }
            // A share is active -> connect and browse its files.
            let active = SMBShare(
                id: share.id,
                displayName: share.displayName,
                host: share.host,
                shareName: activeShareName,
                username: share.username,
                path: share.path
            )
            try await environment.smb.connect(to: active)
            items = try await environment.smb.listDirectory(path)
            state = .loaded
        } catch {
            state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func selectShare(_ name: String) async {
        activeShareName = name
        path = "/"
        await load()
    }

    private func open(_ folder: RemoteFileItem) async {
        path = folder.path
        await load()
    }

    private func makeItem(for file: RemoteFileItem) async throws -> MediaItem {
        let url = try await environment.smb.streamURL(for: file)
        let meta = MetadataParser.parse(filename: file.name, fileSize: file.size)
        return MediaItem(
            title: MetadataParser.cleanTitle(from: file.name),
            sourceType: .smb,
            playbackURL: url,
            legalAccessConfirmed: true, // user owns their own network files
            metadata: meta
        )
    }

    private func playFile(_ file: RemoteFileItem) async {
        do {
            let item = try await makeItem(for: file)
            library.add(item)
            selectedItem = item
        } catch {
            state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func addFile(_ file: RemoteFileItem) async {
        do {
            let item = try await makeItem(for: file)
            library.add(item)
        } catch {
            state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Adds every playable video in the current folder to the library at once.
    /// Skips files already present (by stable content key) so re-running is safe.
    private func addAll(_ files: [RemoteFileItem]) async {
        guard !importing else { return }
        importing = true
        defer { importing = false }

        var added = 0
        for file in files {
            do {
                let item = try await makeItem(for: file)
                let key = item.contentKey
                if !library.items.contains(where: { $0.contentKey == key }) {
                    library.add(item)
                    added += 1
                }
            } catch {
                // Skip a file that can't be resolved; keep importing the rest.
                continue
            }
        }
        ToastCenter.shared.show(
            added > 0 ? "Added \(added) video\(added == 1 ? "" : "s") to your library"
                      : "Everything here is already in your library",
            systemImage: "checkmark.circle.fill"
        )
    }

    /// Jumps directly to a typed/pasted folder path within the active share.
    private func jumpToPath() async {
        let raw = pathInput.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        // Accept "Movies/Action", "/Movies/Action", or a full
        // "smb://host/share/Movies/Action" and reduce to a share-relative path.
        var p = raw
        if let range = p.range(of: "smb://", options: .caseInsensitive) {
            p.removeSubrange(p.startIndex..<range.upperBound)
            // Drop host and share segments if a full URL was pasted.
            let parts = p.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            if parts.count >= 2 { p = "/" + parts.dropFirst(2).joined(separator: "/") }
            else { p = "/" }
        }
        if !p.hasPrefix("/") { p = "/" + p }
        pathFieldFocused = false
        path = p
        await load()
    }
}
