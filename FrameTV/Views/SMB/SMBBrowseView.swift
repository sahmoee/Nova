//
//  SMBBrowseView.swift
//  FrameTV
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

    enum ViewState: Equatable { case loading, loaded, error(String) }

    init(share: SMBShare) {
        self.share = share
        _path = State(initialValue: share.path ?? "/")
        _activeShareName = State(initialValue: share.shareName)
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

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

                    if !folders.isEmpty {
                        sectionHeader("Folders")
                        ForEach(folders) { folder in
                            Button { Task { await open(folder) } } label: {
                                row(icon: "folder.fill", title: folder.name, accent: Theme.Colors.accent)
                            }.buttonStyle(.plain)
                        }
                    }

                    if !files.isEmpty {
                        sectionHeader("Videos")
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
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
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
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
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
}
