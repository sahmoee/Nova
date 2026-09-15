import Foundation
import Combine

@MainActor
struct MediaServerCredentialAccess {
    var read: (String) throws -> String?
    var write: (String, String) throws -> Void
    var remove: (String) throws -> Void
    static var keychain: Self {
        Self(read: { account in
            switch KeychainStore.shared.getResult(account) {
            case .success(let value): return value
            case .failure(.itemNotFound): return nil
            case .failure(let error): throw error
            }
        }, write: { try KeychainStore.shared.set($0, for: $1) }, remove: { try KeychainStore.shared.delete($0) })
    }
}

@MainActor
final class MediaServerStore: ObservableObject {
    @Published private(set) var connections: [MediaServerConnection] = []
    @Published private(set) var syncingIDs: Set<UUID> = []
    @Published var statusMessage: String?

    private let defaultsKey = "media.servers.v1"
    private unowned let library: LibraryStore
    private let client: any MediaServerIndexing
    private let defaults: UserDefaults
    private let credentials: MediaServerCredentialAccess
    private var configurationUnreadable = false
    private var refreshTask: Task<Void, Never>?
    private var indexTasks: [UUID: Task<Void, Error>] = [:]
    private var indexOwners = MediaServerOperationGate()
    private var authOwners = MediaServerOperationGate()

    init(library: LibraryStore, client: any MediaServerIndexing = MediaServerClient(), defaults: UserDefaults = .standard,
         credentials: MediaServerCredentialAccess = .keychain) {
        self.library = library; self.client = client; self.defaults = defaults; self.credentials = credentials
        guard let data = defaults.data(forKey: defaultsKey) else { return }
        do {
            guard data.count <= 2 * 1024 * 1024 else { throw MediaServerError.unreadableConfiguration }
            let saved = try Coders.decoder.decode([MediaServerConnection].self, from: data)
            guard Set(saved.map(\.id)).count == saved.count else { throw MediaServerError.unreadableConfiguration }
            connections = saved
        } catch {
            configurationUnreadable = true
            statusMessage = MediaServerError.unreadableConfiguration.localizedDescription
        }
    }

    deinit { refreshTask?.cancel(); for task in indexTasks.values { task.cancel() } }

    private func encoded(_ values: [MediaServerConnection]) throws -> Data {
        guard !configurationUnreadable else { throw MediaServerError.unreadableConfiguration }
        let data = try Coders.encoder.encode(values)
        guard data.count <= 2 * 1024 * 1024 else { throw MediaServerError.unreadableConfiguration }
        return data
    }
    private func publish(_ values: [MediaServerConnection], data: Data) {
        defaults.set(data, forKey: defaultsKey)
        connections = values
    }
    private func retireIndex(_ id: UUID) {
        indexOwners.retire(id); indexTasks.removeValue(forKey: id)?.cancel(); syncingIDs.remove(id)
    }

    func save(_ connection: MediaServerConnection, secret: String) throws {
        var connection = connection
        connection.baseURL = try MediaServerIndexPolicy.normalizedBase(connection.baseURL)
        connection.name = connection.name.trimmingCharacters(in: .whitespacesAndNewlines)
        connection.username = connection.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !connection.name.isEmpty else { throw MediaServerError.invalidAddress }
        guard let secret = MediaServerIndexPolicy.token(secret) else { throw MediaServerError.missingCredential }
        var candidate = connections
        if let index = candidate.firstIndex(where: { $0.id == connection.id }) { candidate[index] = connection }
        else { candidate.append(connection) }
        let data = try encoded(candidate) // Validate settings before changing the Keychain credential.
        try credentials.write(secret, connection.tokenAccount)
        authOwners.retire(connection.id); retireIndex(connection.id)
        publish(candidate, data: data)
    }

    func connect(_ draft: MediaServerConnection, password: String, token: String) async throws -> MediaServerConnection {
        guard !configurationUnreadable else { throw MediaServerError.unreadableConfiguration }
        var draft = draft
        draft.baseURL = try MediaServerIndexPolicy.normalizedBase(draft.baseURL)
        draft.username = draft.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = connections.first { $0.id == draft.id }
        let suppliedToken: String?
        if MediaServerIndexPolicy.token(token) == nil && password.isEmpty {
            guard let existing, draft.mayReuseCredential(from: existing) else { throw MediaServerError.missingCredential }
            suppliedToken = try credentials.read(existing.tokenAccount)
        } else { suppliedToken = MediaServerIndexPolicy.token(token) }
        let operation = authOwners.begin(draft.id)
        retireIndex(draft.id)
        defer { authOwners.finish(operation, id: draft.id) }
        let authenticated = try await client.authenticate(kind: draft.kind, baseURL: draft.baseURL,
            username: draft.username, password: password, token: suppliedToken)
        try Task.checkCancellation()
        guard authOwners.owns(operation, id: draft.id) else { throw CancellationError() }
        // Never carry a previous endpoint's user ID into a newly authenticated server.
        draft.userID = authenticated.userID
        try save(draft, secret: authenticated.token)
        try await sync(draft.id)
        guard let current = connections.first(where: { $0.id == draft.id }) else { throw CancellationError() }
        return current
    }

    func remove(_ connection: MediaServerConnection, removeIndexedItems: Bool) {
        do {
            let candidate = connections.filter { $0.id != connection.id }
            let data = try encoded(candidate)
            authOwners.retire(connection.id); retireIndex(connection.id)
            if removeIndexedItems, !library.reconcileMediaServer([], connectionID: connection.id) { throw MediaServerError.localPersistence }
            try credentials.remove(connection.tokenAccount)
            publish(candidate, data: data)
            statusMessage = "Removed \(connection.name)."
        } catch { statusMessage = "The server could not be removed. " + error.localizedDescription }
    }

    func sync(_ id: UUID) async throws {
        guard !configurationUnreadable else { throw MediaServerError.unreadableConfiguration }
        try Task.checkCancellation()
        if let task = indexTasks[id] { try await task.value; try Task.checkCancellation(); return }
        guard let connection = connections.first(where: { $0.id == id }) else { throw CancellationError() }
        let operation = indexOwners.begin(id)
        syncingIDs.insert(id)
        let task = Task { [weak self] in
            guard let self else { throw CancellationError() }
            try await self.performSync(connection, operation: operation)
        }
        indexTasks[id] = task
        try await withTaskCancellationHandler {
            try await task.value
            try Task.checkCancellation()
        } onCancel: { [weak self] in
            task.cancel()
            Task { @MainActor in
                guard let self, self.indexOwners.owns(operation, id: id) else { return }
                self.retireIndex(id)
            }
        }
    }

    private func performSync(_ connection: MediaServerConnection, operation: UUID) async throws {
        let id = connection.id
        defer {
            if indexOwners.owns(operation, id: id) {
                indexTasks.removeValue(forKey: id); syncingIDs.remove(id); indexOwners.finish(operation, id: id)
            }
        }
        do {
            guard let token = MediaServerIndexPolicy.token(try credentials.read(connection.tokenAccount)) else { throw MediaServerError.missingCredential }
            let result = try await client.index(connection: connection, token: token)
            try Task.checkCancellation()
            guard indexOwners.owns(operation, id: id), let liveIndex = connections.firstIndex(where: { $0.id == id }) else { throw CancellationError() }
            var candidate = connections
            candidate[liveIndex].availableLibraries = result.libraries
            let supportedIDs = Set(result.libraries.map(\.id))
            candidate[liveIndex].selectedLibraryIDs = candidate[liveIndex].selectedLibraryIDs.isEmpty
                ? supportedIDs : candidate[liveIndex].selectedLibraryIDs.intersection(supportedIDs)
            candidate[liveIndex].lastIndexed = Date(); candidate[liveIndex].indexedItemCount = result.items.count; candidate[liveIndex].lastError = nil
            let data = try encoded(candidate)
            guard library.reconcileMediaServer(result.items, connectionID: id) else { throw MediaServerError.localPersistence }
            publish(candidate, data: data)
            statusMessage = "Indexed \(result.items.count) items from \(candidate[liveIndex].name)."
        } catch {
            if !Task.isCancelled, !(error is CancellationError), indexOwners.owns(operation, id: id),
               let index = connections.firstIndex(where: { $0.id == id }) {
                var candidate = connections; candidate[index].lastError = error.localizedDescription
                if let data = try? encoded(candidate) { publish(candidate, data: data) }
                statusMessage = "Couldn't refresh \(connection.name). " + error.localizedDescription
            }
            throw error
        }
    }

    func syncAll() {
        guard refreshTask == nil else { return }
        let ids = connections.filter(\.autoRefresh).map(\.id)
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.refreshTask = nil }
            for id in ids {
                if Task.isCancelled { return }
                // Recheck after each suspension; an editor may disable automatic refresh.
                guard self.connections.first(where: { $0.id == id })?.autoRefresh == true else { continue }
                try? await self.sync(id)
            }
        }
    }
}
