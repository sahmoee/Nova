//
//  NetworkConditionMonitor.swift
//  Astra
//
//  Observes the current network path (cellular, expensive, constrained) so the app can
//  suggest bandwidth-saving choices when appropriate: prefer smaller/cached streams and
//  warn before very large files. Purely advisory; it never changes settings on its own.
//

import Foundation
import Network
import Combine

@MainActor
final class NetworkConditionMonitor: ObservableObject {
    static let shared = NetworkConditionMonitor()

    @Published private(set) var isCellular = false
    @Published private(set) var isExpensive = false
    @Published private(set) var isConstrained = false
    @Published private(set) var isOnline = true

    /// Posted when connectivity returns after an offline period, so sources
    /// (Live TV playlists, SMB shares) can reconnect or refresh themselves.
    static let networkRestored = Notification.Name("astra.networkRestored")

    /// True when the network looks limited and the user would benefit from smaller,
    /// cached streams (cellular, metered, or Low Data Mode).
    var shouldSuggestBandwidthSaver: Bool { isCellular || isExpensive || isConstrained }

    /// A short reason string for a UI banner, or nil when the network is unconstrained.
    var suggestionReason: String? {
        guard shouldSuggestBandwidthSaver else { return nil }
        if isConstrained { return "Low Data Mode is on" }
        if isCellular { return "You're on cellular" }
        if isExpensive { return "This network may be metered" }
        return nil
    }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.frametv.network.monitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let cellular = path.usesInterfaceType(.cellular)
            let expensive = path.isExpensive
            let constrained = path.isConstrained
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                self.isCellular = cellular
                self.isExpensive = expensive
                self.isConstrained = constrained
                let wasOnline = self.isOnline
                self.isOnline = online
                if online && !wasOnline {
                    NotificationCenter.default.post(name: Self.networkRestored, object: nil)
                }
            }
        }
        monitor.start(queue: queue)
    }
}
