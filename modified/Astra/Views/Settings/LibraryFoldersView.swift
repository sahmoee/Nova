//
//  LibraryFoldersView.swift
//  Astra
//
//  Manage folder locations whose videos are scanned into the library. Folders are
//  chosen with a browser (pick a share, then drill into folders) rather than typed.
//

import SwiftUI

struct LibraryFoldersView: View {
    @EnvironmentObject private var env: AppEnvironment
    var body: some View { LibraryFoldersContent(store: env.libraryFolders) }
}

private struct LibraryFoldersContent: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var store: LibraryFolderStore
    @State private var showPicker = false
    @State private var lastResult: String?
    // Folder pending remove confirmation, so a stray tap can't remove it.
    @State private var pendingDelete: LibraryFolder?

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Library Folders")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(.top, Theme.Spacing.lg)
                    Text("Add a folder from one of your SMB shares and its videos are added to your library. Rescan to pick up new files. Files already in your library are skipped.")
                        .font(.appFont(16)).foregroundStyle(Theme.Colors.textTertiary)
                    if store.folders.isEmpty { emptyState }
                    else { ForEach(store.folders) { folderCard($0) } }
                    if let lastResult {
                        Text(lastResult).font(.appFont(15)).foregroundStyle(Theme.Colors.accent)
                    }
                    FocusableButton(title: "Add Folder", systemImage: "folder.badge.plus", prominent: true) {
                        showPicker = true
                    }
                    .padding(.top, Theme.Spacing.sm)
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.bottom, Theme.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $showPicker) {
            SMBFolderPickerView { shareID, name, path in
                _ = store.addFolder(shareID: shareID, displayName: name, path: path)
                showPicker = false
            }
            .environmentObject(env)
        }
        // Destructive confirmation before removing a scanned folder.
        .alert("Remove Folder?",
               isPresented: Binding(get: { pendingDelete != nil },
                                    set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { folder in
            Button("Remove “\(folder.displayName)”", role: .destructive) {
                store.removeFolder(folder)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { folder in
            Text("“\(folder.displayName)” will no longer be scanned. Items already in your library stay.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "folder.badge.plus").font(.system(size: 40)).foregroundStyle(Theme.Colors.textTertiary)
            Text("No folders yet").font(.appFont(18, weight: .semibold)).foregroundStyle(Theme.Colors.textSecondary)
            Text("Add a folder to scan its videos into your library.")
                .font(.appFont(15)).foregroundStyle(Theme.Colors.textTertiary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.xl).refinedCardBackground()
    }

    private func folderCard(_ folder: LibraryFolder) -> some View {
        let scanning = store.scanningFolderID == folder.id
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: "folder.fill").foregroundStyle(Theme.Colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.displayName).font(.appFont(18, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                    Text(folder.path.isEmpty ? "Share root" : folder.path)
                        .font(.appFont(14)).foregroundStyle(Theme.Colors.textTertiary).lineLimit(1)
                }
                Spacer()
            }
            if let last = folder.lastScanned {
                Text("Last scan added \(folder.lastAddedCount) — \(last.formatted(date: .abbreviated, time: .shortened))")
                    .font(.appFont(13)).foregroundStyle(Theme.Colors.textTertiary)
            }
            if scanning, let status = store.scanStatus {
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView().tint(Theme.Colors.accent)
                    Text(status).font(.appFont(14)).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    Task {
                        let n = await store.rescan(folder, using: env)
                        lastResult = "Added \(n) item\(n == 1 ? "" : "s") from \(folder.displayName)."
                    }
                } label: { Label("Rescan", systemImage: "arrow.clockwise").font(.appFont(15, weight: .semibold)) }
                .buttonStyle(AstraChipButtonStyle()).disabled(scanning)
                // Ask before removing instead of deleting immediately.
                Button(role: .destructive) { pendingDelete = folder } label: {
                    Label("Remove", systemImage: "trash").font(.appFont(15, weight: .semibold)).foregroundStyle(Theme.Colors.error)
                }
                .buttonStyle(AstraChipButtonStyle()).disabled(scanning)
            }
        }
        .padding(Theme.Spacing.md).refinedCardBackground()
    }
}

/// Browses SMB shares and their folders so the user can pick a folder to add, instead
/// of typing a path. Choosing a share lists its folders; drilling in updates the path;
/// "Use This Folder" adds the current location.
private struct SMBFolderPickerView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    /// shareID, display name, path
    let onPick: (UUID, String, String) -> Void

    @State private var shares: [SMBShare] = []
    @State private var selectedShare: SMBShare?
    @State private var path = "/"
    @State private var folders: [RemoteFileItem] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()
                content
            }
            .navigationTitle(selectedShare == nil ? "Choose Share" : "Choose Folder")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(selectedShare == nil ? "Cancel" : "Back") {
                        if selectedShare == nil { dismiss() }
                        else { selectedShare = nil; folders = []; path = "/" }
                    }
                }
                if selectedShare != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use This Folder") {
                            if let share = selectedShare {
                                let leaf = path == "/" ? share.displayName
                                    : (path as NSString).lastPathComponent
                                onPick(share.id, leaf, path == "/" ? "" : path)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { shares = env.libraryFolders.availableShares }
    }

    @ViewBuilder private var content: some View {
        if selectedShare == nil {
            shareList
        } else {
            folderBrowser
        }
    }

    private var shareList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if shares.isEmpty {
                    Text("No SMB shares are configured yet. Add a share under Sources first, then come back to pick a folder from it.")
                        .font(.appFont(16)).foregroundStyle(Theme.Colors.textTertiary)
                } else {
                    ForEach(shares) { share in
                        Button {
                            selectedShare = share
                            path = "/"
                            Task { await browse(share, "/") }
                        } label: {
                            HStack {
                                Image(systemName: "externaldrive.connected.to.line.below")
                                    .foregroundStyle(Theme.Colors.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(share.displayName).font(.appFont(16, weight: .medium)).foregroundStyle(Theme.Colors.textPrimary)
                                    Text("\(share.host)/\(share.shareName)").font(.appFont(13)).foregroundStyle(Theme.Colors.textTertiary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Theme.Colors.textTertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).padding(Theme.Spacing.md).refinedCardBackground()
                    }
                }
            }
            .padding(Theme.Spacing.edge)
        }
    }

    private var folderBrowser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Image(systemName: "folder").foregroundStyle(Theme.Colors.accent)
                    Text(path).font(.appFont(14, weight: .medium)).foregroundStyle(Theme.Colors.textSecondary).lineLimit(1)
                    Spacer()
                }
                .padding(.bottom, Theme.Spacing.xs)

                if path != "/" {
                    Button {
                        let parent = ("/" + (path as NSString).deletingLastPathComponent)
                            .replacingOccurrences(of: "//", with: "/")
                        Task { await browse(selectedShare!, parent.isEmpty ? "/" : parent) }
                    } label: {
                        Label("Up one level", systemImage: "arrow.up.left")
                            .font(.appFont(15)).foregroundStyle(Theme.Colors.accent)
                    }
                    .buttonStyle(.plain).padding(Theme.Spacing.md).refinedCardBackground()
                }

                if loading {
                    HStack { ProgressView().tint(Theme.Colors.accent); Text("Loading…").foregroundStyle(Theme.Colors.textSecondary) }
                        .padding(Theme.Spacing.md)
                } else if folders.isEmpty {
                    Text("No subfolders here. You can still use this folder.")
                        .font(.appFont(14)).foregroundStyle(Theme.Colors.textTertiary).padding(Theme.Spacing.md)
                } else {
                    ForEach(folders, id: \.path) { folder in
                        Button {
                            Task { await browse(selectedShare!, folder.path) }
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill").foregroundStyle(Theme.Colors.accent)
                                Text(folder.name).font(.appFont(16)).foregroundStyle(Theme.Colors.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Theme.Colors.textTertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).padding(Theme.Spacing.md).refinedCardBackground()
                    }
                }

                if let error {
                    Text(error).font(.appFont(14)).foregroundStyle(Theme.Colors.warning)
                }
            }
            .padding(Theme.Spacing.edge)
        }
    }

    private func browse(_ share: SMBShare, _ newPath: String) async {
        loading = true; error = nil
        defer { loading = false }
        do {
            try await env.smb.connect(to: share)
            let entries = try await env.smb.listDirectory(newPath)
            folders = entries.filter { $0.isDirectory }
            path = newPath
        } catch {
            self.error = "Couldn't open this folder."
        }
    }
}
