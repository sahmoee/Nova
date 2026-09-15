import Foundation

/// Bounded LRU cache. Expiry uses monotonic uptime, so wall-clock corrections
/// cannot extend a stream's lifetime or expire the entire metadata cache.
actor TTLCache<Key: Hashable & Sendable, Value: Sendable> {
    private struct Entry {
        let value: Value
        let expiry: TimeInterval
        var access: UInt64
    }
    private struct Flight {
        let id: UUID
        let task: Task<Value, Never>
    }
    private var store: [Key: Entry] = [:]
    private var inFlight: [Key: Flight] = [:]
    private var access: UInt64 = 0
    private let ttl: TimeInterval
    private let maxEntries: Int
    private let now: @Sendable () -> TimeInterval

    init(ttl: TimeInterval, maxEntries: Int = 200,
         now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.ttl = ttl.isFinite ? max(0, min(ttl, 31_536_000)) : 0
        self.maxEntries = max(1, min(maxEntries, 10_000))
        self.now = now
    }

    func value(for key: Key) -> Value? {
        guard var entry = store[key], entry.expiry > now() else { return nil }
        access &+= 1
        entry.access = access
        store[key] = entry
        return entry.value
    }

    /// Deliberately retained for stale-while-refresh callers; still bounded by LRU.
    func staleValue(for key: Key) -> Value? { store[key]?.value }

    /// Cache publication belongs to this flight, not to an awaiting consumer.
    /// A reset can cancel an old producer without letting it erase/cache over a new one.
    func coalesced(for key: Key,
                   shouldCache: @escaping @Sendable (Value) -> Bool = { _ in false },
                   loader: @escaping @Sendable () async -> Value) async -> Value {
        if let cached = value(for: key) { return cached }
        if let flight = inFlight[key] { return await flight.task.value }
        let id = UUID()
        let task = Task { await loader() }
        inFlight[key] = Flight(id: id, task: task)
        let result = await task.value
        guard inFlight[key]?.id == id else { return result }
        inFlight[key] = nil
        if !task.isCancelled, shouldCache(result) { set(result, for: key) }
        return result
    }

    func set(_ value: Value, for key: Key) {
        // Replacing an existing key must never evict an unrelated title.
        if store[key] == nil, store.count >= maxEntries,
           let victim = store.min(by: { $0.value.access < $1.value.access })?.key {
            store[victim] = nil
        }
        access &+= 1
        store[key] = Entry(value: value, expiry: now() + ttl, access: access)
    }

    func removeAll() {
        store.removeAll()
        inFlight.values.forEach { $0.task.cancel() }
        inFlight.removeAll()
    }
}
