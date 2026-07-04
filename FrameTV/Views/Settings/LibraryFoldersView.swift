//
//  LibraryFoldersView.swift
//  FrameTV
//

import SwiftUI

struct LibraryFoldersView: View {
    @EnvironmentObject private var env: AppEnvironment
    var body: some View { LibraryFoldersContent(store: env.libraryFolders) }
}

private struct LibraryFoldersContent: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var store: LibraryFolderStore
    @State private var showAdd = false
    @State private var lastResult: String?

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
                    Text("Add a folder on one of your SMB shares and its videos are added to your library. Rescan to pick up new files. Files already in your library are skipped.")
                        .font(.appFont(16)).foregroundStyle(Theme.Colors.textTertiary)
                    if store.folders.isEmpty { emptyState }
                    else { ForEach(store.folders) { folderCard($0) } }
                    if let lastResult {
                        Text(lastResult).font(.appFont(15)).foregroundStyle(Theme.Colors.accent)
                    }
                    FocusableButton(title: "Add Folder", systemImage: "plus", prominent: true) { showAdd = true }
                        .padding(.top, Theme.Spacing.sm)
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.bottom, Theme.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $showAdd) {
            AddLibraryFolderView { shareID, name, path in
                _ = store.addFolder(shareID: shareID, displayName: name, path: path)
                showAdd = false
            }.environmentObject(env)
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
                .buttonStyle(FrameChipButtonStyle()).disabled(scanning)
                Button(role: .destructive) { store.removeFolder(folder) } label: {
                    Label("Remove", systemImage: "trash").font(.appFont(15, weight: .semibold)).foregroundStyle(Theme.Colors.error)
                }
                .buttonStyle(FrameChipButtonStyle()).disabled(scanning)
            }
        }
        .padding(Theme.Spacing.md).refinedCardBackground()
    }
}

private struct AddLibraryFolderView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let onAdd: (UUID, String, String) -> Void
    @State private var selectedShareID: UUID?
    @State private var displayName = ""
    @State private var path = ""
    private var shares: [SMBShare] { env.libraryFolders.availableShares }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        if shares.isEmpty {
                            Text("No SMB shares are configured yet. Add a share under Sources first, then come back to add a folder from it.")
                                .font(.appFont(16)).foregroundStyle(Theme.Colors.textTertiary)
                        } else {
                            Text("Share").font(.appFont(15, weight: .semibold)).foregroundStyle(Theme.Colors.textSecondary)
                            ForEach(shares) { share in
                                Button {
                                    selectedShareID = share.id
                                    if displayName.isEmpty { displayName = share.displayName }
                                } label: {
                                    HStack {
                                        Image(systemName: selectedShareID == share.id ? "largecircle.fill.circle" : "circle")
                                            .foregroundStyle(Theme.Colors.accent)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(share.displayName).font(.appFont(16, weight: .medium)).foregroundStyle(Theme.Colors.textPrimary)
                                            Text("\(share.host)/\(share.shareName)").font(.appFont(13)).foregroundStyle(Theme.Colors.textTertiary)
                                        }
                                        Spacer()
                                    }.contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).padding(Theme.Spacing.md).refinedCardBackground()
                            }
                            Text("Folder path").font(.appFont(15, weight: .semibold)).foregroundStyle(Theme.Colors.textSecondary).padding(.top, Theme.Spacing.sm)
                            TextField("/Movies", text: $path)
                                .textFieldStyle(.plain).foregroundStyle(Theme.Colors.textPrimary).autocorrectionDisabled(true)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                                .padding(Theme.Spacing.md).refinedCardBackground(cornerRadius: Theme.Radius.button)
                            Text("Leave blank to scan the whole share. The folder and its subfolders are searched for video files.")
                                .font(.appFont(13)).foregroundStyle(Theme.Colors.textTertiary)
                            Text("Name").font(.appFont(15, weight: .semibold)).foregroundStyle(Theme.Colors.textSecondary).padding(.top, Theme.Spacing.sm)
                            TextField("Movies", text: $displayName)
                                .textFieldStyle(.plain).foregroundStyle(Theme.Colors.textPrimary)
                                .padding(Theme.Spacing.md).refinedCardBackground(cornerRadius: Theme.Radius.button)
                        }
                    }.padding(Theme.Spacing.edge)
                }
            }
            .navigationTitle("Add Folder")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let id = selectedShareID { onAdd(id, displayName.isEmpty ? "Folder" : displayName, path) }
                    }.disabled(selectedShareID == nil)
                }
            }
        }
    }
}
