import Foundation

/// Orders subtitle intent independently of downloads and VLC's asynchronous registration.
/// Only the currently pending request may apply a track or publish a completion.
struct SubtitleSelectionGate {
    private(set) var revision = UUID()
    private(set) var pendingID: String?

    mutating func begin(_ id: String) -> UUID {
        revision = UUID(); pendingID = id
        return revision
    }
    mutating func cancel() { revision = UUID(); pendingID = nil }
    func accepts(_ request: UUID) -> Bool { revision == request && pendingID != nil }
    @discardableResult mutating func finish(_ request: UUID) -> Bool {
        guard accepts(request) else { return false }
        pendingID = nil
        return true
    }
}

enum SubtitleScalePolicy {
    static let range = 0.5...2.5
    static func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return (min(range.upperBound, max(range.lowerBound, value)) * 10).rounded() / 10
    }
}
