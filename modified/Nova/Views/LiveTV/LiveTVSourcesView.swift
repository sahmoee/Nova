//
//  LiveTVSourcesView.swift
//  Nova
//

import SwiftUI

struct LiveTVSourcesView: View {
    @EnvironmentObject private var env: AppEnvironment
    var body: some View { LiveTVSourcesContent(store: env.liveTVSources) }
}

private struct LiveTVSourcesContent: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var store: LiveTVSourceStore
    @State private var showAdd = false
    // Playlist pending delete confirmation, so a stray tap can't remove it.
    @State private var pendingDelete: LiveTVSource?

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Live TV Sources")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(.top, Theme.Spacing.lg)
                    Text("Turn on the free channel sources you want, or add your own M3U or Xtream-codes playlist. Enabled sources' channels show up under Live TV.")
                        .font(.appFont(16)).foregroundStyle(Theme.Colors.textTertiary)

                    let builtIns = store.sources.filter(\.isBuiltIn)
                    if !builtIns.isEmpty {
                        Text("Free Channels").font(.appFont(18, weight: .semibold)).foregroundStyle(Theme.Colors.textSecondary)
                        ForEach(builtIns) { sourceRow($0) }
                    }
                    let custom = store.sources.filter { !$0.isBuiltIn }
                    if !custom.isEmpty {
                        Text("My Playlists").font(.appFont(18, weight: .semibold)).foregroundStyle(Theme.Colors.textSecondary).padding(.top, Theme.Spacing.sm)
                        ForEach(custom) { sourceRow($0) }
                    }
                    if let err = store.lastError {
                        Text(err).font(.appFont(14)).foregroundStyle(Theme.Colors.warning)
                    }
                    FocusableButton(title: "Add Playlist", systemImage: "plus", prominent: true) { showAdd = true }
                        .padding(.top, Theme.Spacing.sm)
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.bottom, Theme.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $showAdd) {
            AddLiveTVSourceView { name, url, kind, user, pass, epg, hours in
                store.addCustom(name: name, url: url, kind: kind, username: user, password: pass,
                                epgURL: epg, refreshHours: hours)
                showAdd = false
                // Confirm the silent add so the user knows the playlist was saved.
                ToastCenter.shared.show("Playlist added", systemImage: "dot.radiowaves.left.and.right")
            }.environmentObject(env)
        }
        // Destructive confirmation before removing a custom playlist.
        .alert("Remove Playlist?",
               isPresented: Binding(get: { pendingDelete != nil },
                                    set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { source in
            Button("Remove “\(source.name)”", role: .destructive) {
                store.remove(source)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { source in
            Text("“\(source.name)” and its channels will be removed from Live TV.")
        }
    }

    private func sourceRow(_ source: LiveTVSource) -> some View {
        let channelCount = store.channelsBySource[source.id]?.count
        return HStack(spacing: Theme.Spacing.md) {
            Image(systemName: source.kind == .xtream ? "server.rack" : "dot.radiowaves.left.and.right")
                .foregroundStyle(Theme.Colors.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name).font(.appFont(17, weight: .medium)).foregroundStyle(Theme.Colors.textPrimary)
                if source.isEnabled, let n = channelCount {
                    Text("\(n) channels").font(.appFont(13)).foregroundStyle(Theme.Colors.textTertiary)
                } else if !source.isBuiltIn {
                    Text(source.url).font(.appFont(13)).foregroundStyle(Theme.Colors.textTertiary).lineLimit(1)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { source.isEnabled }, set: { store.setEnabled($0, for: source) }))
                .labelsHidden().tint(Theme.Colors.accent)
            if !source.isBuiltIn {
                // Ask before deleting instead of removing immediately.
                Button(role: .destructive) { pendingDelete = source } label: {
                    Image(systemName: "trash").foregroundStyle(Theme.Colors.error)
                }.buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.md).refinedCardBackground()
    }
}

private struct AddLiveTVSourceView: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (String, String, LiveTVSource.Kind, String?, String?, String?, Int?) -> Void
    @State private var kind: LiveTVSource.Kind = .m3u
    @State private var name = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var epgURL = ""
    @State private var refreshHours = 12

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        Picker("Type", selection: $kind) {
                            Text("M3U Playlist").tag(LiveTVSource.Kind.m3u)
                            Text("Xtream Codes").tag(LiveTVSource.Kind.xtream)
                        }.pickerStyle(.segmented)
                        field("Name", text: $name, placeholder: "My Playlist")
                        field(kind == .xtream ? "Server URL" : "Playlist URL", text: $url,
                              placeholder: kind == .xtream ? "http://host:port" : "https://…/playlist.m3u")
                        if kind == .xtream {
                            field("Username", text: $username, placeholder: "username")
                            secureField("Password", text: $password)
                        }
                        field("EPG URL (optional)", text: $epgURL,
                              placeholder: "https://…/guide.xml")
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Auto-refresh")
                                .font(.appFont(15, weight: .semibold))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Picker("Auto-refresh", selection: $refreshHours) {
                                Text("Every 6 hours").tag(6)
                                Text("Every 12 hours").tag(12)
                                Text("Daily").tag(24)
                                Text("Weekly").tag(168)
                            }
                            .pickerStyle(.segmented)
                        }
                        Text("Only add playlists you have the right to use, such as your own IPTV subscription or a free public FAST feed.")
                            .font(.appFont(13)).foregroundStyle(Theme.Colors.textTertiary)
                    }.padding(Theme.Spacing.edge)
                }
            }
            .navigationTitle("Add Playlist")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(name, url, kind,
                              kind == .xtream ? username : nil,
                              kind == .xtream ? password : nil,
                              epgURL.trimmingCharacters(in: .whitespaces).isEmpty ? nil : epgURL,
                              refreshHours)
                    }.disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label).font(.appFont(15, weight: .semibold)).foregroundStyle(Theme.Colors.textSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain).foregroundStyle(Theme.Colors.textPrimary).autocorrectionDisabled(true)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .padding(Theme.Spacing.md).refinedCardBackground(cornerRadius: Theme.Radius.button)
        }
    }

    private func secureField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label).font(.appFont(15, weight: .semibold)).foregroundStyle(Theme.Colors.textSecondary)
            SecureField("password", text: text)
                .textFieldStyle(.plain).foregroundStyle(Theme.Colors.textPrimary)
                .padding(Theme.Spacing.md).refinedCardBackground(cornerRadius: Theme.Radius.button)
        }
    }
}
