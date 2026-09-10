import Foundation

@MainActor
final class MediaServerStore: ObservableObject {
    @Published private(set) var connections: [MediaServerConnection] = []
    @Published private(set) var syncingIDs: Set<UUID> = []
    @Published var statusMessage: String?

    private let defaultsKey = "media.servers.v1"
    private unowned let library: LibraryStore
    private let client = MediaServerClient()
    private var refreshTask: Task<Void, Never>?

    init(library: LibraryStore) {
        self.library = library
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? Coders.decoder.decode([MediaServerConnection].self, from: data) {
            connections = saved
        }
    }

    deinit { refreshTask?.cancel() }

    func save(_ connection: MediaServerConnection, secret: String) throws {
        try KeychainStore.shared.set(secret, for: connection.tokenAccount)
        if let index = connections.firstIndex(where: { $0.id == connection.id }) { connections[index] = connection }
        else { connections.append(connection) }
        persist()
    }

    func connect(_ draft: MediaServerConnection, password: String, token: String) async throws -> MediaServerConnection {
        let saved = KeychainStore.shared.get(draft.tokenAccount)
        let suppliedToken = token.isEmpty && password.isEmpty ? saved : (token.isEmpty ? nil : token)
        let credentials = try await client.authenticate(kind: draft.kind, baseURL: draft.baseURL,
            username: draft.username, password: password, token: suppliedToken)
        var connection = draft
        connection.userID = credentials.userID ?? draft.userID
        try save(connection, secret: credentials.token)
        try await sync(connection.id)
        return connections.first(where: { $0.id == connection.id }) ?? connection
    }

    func remove(_ connection: MediaServerConnection, removeIndexedItems: Bool) {
        refreshTask?.cancel()
        try? KeychainStore.shared.delete(connection.tokenAccount)
        connections.removeAll { $0.id == connection.id }
        if removeIndexedItems { library.reconcileMediaServer([], connectionID: connection.id) }
        persist()
    }

    func sync(_ id: UUID) async throws {
        guard let index = connections.firstIndex(where: { $0.id == id }), !syncingIDs.contains(id) else { return }
        guard let token = KeychainStore.shared.get(connections[index].tokenAccount), !token.isEmpty else {
            throw MediaServerError.missingCredential
        }
        syncingIDs.insert(id); defer { syncingIDs.remove(id) }
        do {
            let result = try await client.index(connection: connections[index], token: token)
            library.reconcileMediaServer(result.items, connectionID: id)
            guard let liveIndex = connections.firstIndex(where: { $0.id == id }) else { return }
            connections[liveIndex].availableLibraries = result.libraries
            if connections[liveIndex].selectedLibraryIDs.isEmpty {
                connections[liveIndex].selectedLibraryIDs = Set(result.libraries.map(\.id))
            }
            connections[liveIndex].lastIndexed = Date()
            connections[liveIndex].indexedItemCount = result.items.count
            connections[liveIndex].lastError = nil
            statusMessage = "Indexed \(result.items.count) items from \(connections[liveIndex].name)."
            persist()
        } catch {
            if let liveIndex = connections.firstIndex(where: { $0.id == id }) {
                connections[liveIndex].lastError = error.localizedDescription
                persist()
            }
            throw error
        }
    }

    func syncAll() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            for connection in self.connections where connection.autoRefresh {
                if Task.isCancelled { return }
                try? await self.sync(connection.id)
            }
        }
    }

    private func persist() {
        if let data = try? Coders.encoder.encode(connections) { UserDefaults.standard.set(data, forKey: defaultsKey) }
    }
}
