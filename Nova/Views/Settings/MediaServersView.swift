import SwiftUI

struct MediaServersView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var editing: MediaServerConnection?
    @State private var addingKind: MediaServerKind?
    @State private var pendingRemoval: MediaServerConnection?

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    ScreenHeader(title: "Media Servers",
                        subtitle: "Index personal libraries from Jellyfin, Plex, or Emby into Nova.")

                    if env.mediaServers.connections.isEmpty { emptyState }
                    ForEach(env.mediaServers.connections) { connection in serverCard(connection) }

                    Menu {
                        ForEach(MediaServerKind.allCases) { kind in
                            Button { addingKind = kind } label: { Label(kind.title, systemImage: kind.symbol) }
                        }
                    } label: {
                        Label("Add Media Server", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NovaRowButtonStyle())

                    if let message = env.mediaServers.statusMessage {
                        Text(message).font(.appFont(15)).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.bottom, Theme.Spacing.xl)
                .frame(maxWidth: Theme.contentMaxWidth(1100), alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Media Servers")
        .sheet(item: $addingKind) { kind in MediaServerEditor(kind: kind) }
        .sheet(item: $editing) { connection in MediaServerEditor(kind: connection.kind, existing: connection) }
        .alert("Remove Media Server?", isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("Remove Server and Items", role: .destructive) {
                if let pendingRemoval { env.mediaServers.remove(pendingRemoval, removeIndexedItems: true) }
                pendingRemoval = nil
            }
            Button("Remove Server Only") {
                if let pendingRemoval { env.mediaServers.remove(pendingRemoval, removeIndexedItems: false) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { Text("The server credentials will be removed from Keychain.") }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "play.tv").font(.appFont(42)).foregroundStyle(Theme.Colors.accent)
            Text("Bring your server library into Nova").font(Theme.Font.sectionTitle()).foregroundStyle(Theme.Colors.textPrimary)
            Text("Nova keeps a fast local index for Home, Search, Library, Spotlight, and offline browsing. Your server remains the source of the media.")
                .font(.appFont(16)).foregroundStyle(Theme.Colors.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(Theme.Spacing.lg).refinedCardBackground()
    }

    private func serverCard(_ connection: MediaServerConnection) -> some View {
        let syncing = env.mediaServers.syncingIDs.contains(connection.id)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: connection.kind.symbol).foregroundStyle(Theme.Colors.accent).font(.appFont(26))
                VStack(alignment: .leading, spacing: 3) {
                    Text(connection.name).font(.appFont(19, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                    Text(connection.baseURL.host ?? connection.baseURL.absoluteString)
                        .font(.appFont(14)).foregroundStyle(Theme.Colors.textTertiary).lineLimit(1)
                }
                Spacer()
                if syncing { ProgressView().tint(Theme.Colors.accent) }
                else { Text("\(connection.indexedItemCount)").font(.appFont(17, weight: .semibold)).foregroundStyle(Theme.Colors.textSecondary) }
            }
            if let date = connection.lastIndexed {
                Text("Indexed \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.appFont(13)).foregroundStyle(Theme.Colors.textTertiary)
            }
            if let error = connection.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.appFont(14)).foregroundStyle(Theme.Colors.error)
            }
            HStack {
                Button { Task { try? await env.mediaServers.sync(connection.id) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }.buttonStyle(NovaChipButtonStyle()).disabled(syncing)
                Button { editing = connection } label: { Label("Edit", systemImage: "slider.horizontal.3") }
                    .buttonStyle(NovaChipButtonStyle()).disabled(syncing)
                Button(role: .destructive) { pendingRemoval = connection } label: { Label("Remove", systemImage: "trash") }
                    .buttonStyle(NovaChipButtonStyle()).disabled(syncing)
            }
        }
        .padding(Theme.Spacing.md).refinedCardBackground()
    }
}

private struct MediaServerEditor: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let existing: MediaServerConnection?
    @State private var kind: MediaServerKind
    @State private var name: String
    @State private var address: String
    @State private var username: String
    @State private var password = ""
    @State private var token = ""
    @State private var selectedLibraries: Set<String>
    @State private var autoRefresh: Bool
    @State private var working = false
    @State private var error: String?

    init(kind: MediaServerKind, existing: MediaServerConnection? = nil) {
        self.existing = existing
        _kind = State(initialValue: existing?.kind ?? kind)
        _name = State(initialValue: existing?.name ?? kind.title)
        _address = State(initialValue: existing?.baseURL.absoluteString ?? "http://")
        _username = State(initialValue: existing?.username ?? "")
        _selectedLibraries = State(initialValue: existing?.selectedLibraryIDs ?? [])
        _autoRefresh = State(initialValue: existing?.autoRefresh ?? true)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Picker("Server", selection: $kind) {
                            ForEach(MediaServerKind.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).disabled(existing != nil)
                        field("Name", text: $name, content: .name)
                        field("Server address", text: $address, content: .URL)
                        if kind != .plex { field("Username", text: $username, content: .username) }
                        if kind == .plex {
                            secureField("Plex token", text: $token)
                            Text("Use an access token from your own Plex account. Nova stores it in Keychain.")
                                .font(.appFont(13)).foregroundStyle(Theme.Colors.textTertiary)
                        } else if existing == nil {
                            secureField("Password", text: $password)
                        } else {
                            secureField("New token or password (optional)", text: $token)
                        }
                        Toggle("Refresh this server automatically", isOn: $autoRefresh).tint(Theme.Colors.accent)

                        if let existing, !existing.availableLibraries.isEmpty {
                            Text("Libraries").font(Theme.Font.sectionTitle()).foregroundStyle(Theme.Colors.textPrimary)
                            ForEach(existing.availableLibraries) { library in
                                Toggle(isOn: Binding(get: { selectedLibraries.contains(library.id) }, set: { on in
                                    if on { selectedLibraries.insert(library.id) } else { selectedLibraries.remove(library.id) }
                                })) { Text(library.name).foregroundStyle(Theme.Colors.textPrimary) }
                                    .tint(Theme.Colors.accent)
                            }
                        }
                        if let error { Text(error).font(.appFont(14)).foregroundStyle(Theme.Colors.error) }
                    }
                    .padding(Theme.Spacing.edge)
                }
            }
            .navigationTitle(existing == nil ? "Add \(kind.title)" : "Edit \(kind.title)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(working ? "Connecting…" : "Save & Index") { Task { await save() } }
                        .disabled(working || URL(string: address)?.host == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func field(_ prompt: String, text: Binding<String>, content: UITextContentType?) -> some View {
        TextField(prompt, text: text).textContentType(content).textInputAutocapitalization(.never)
            .autocorrectionDisabled().padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
    }
    private func secureField(_ prompt: String, text: Binding<String>) -> some View {
        SecureField(prompt, text: text).textContentType(.password)
            .padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
    }

    private func save() async {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        working = true; error = nil; defer { working = false }
        var draft = existing ?? MediaServerConnection(kind: kind, name: name, baseURL: url)
        draft.kind = kind; draft.name = name; draft.baseURL = url; draft.username = username
        draft.selectedLibraryIDs = selectedLibraries; draft.autoRefresh = autoRefresh
        do {
            _ = try await env.mediaServers.connect(draft, password: password, token: token)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
