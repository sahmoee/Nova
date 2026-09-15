import Foundation
import Combine
@preconcurrency import WatchConnectivity

/// The delegate only moves bounded data across its queue; app state stays on MainActor.
@MainActor
final class NovaWatchConnectivity: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var reachable = false
    @Published private(set) var available = false
    @Published private(set) var status = "Connecting to companion…"
    var onCommand: ((Data, @escaping (Data) -> Void) -> Void)?
    var onEnvelope: ((Data) -> Void)?
    var onReady: (() -> Void)?
    var onFailure: ((UUID) -> Void)?
    private nonisolated let deliveries = NovaWatchDeliveryCounter()
    var pendingDeliveries: Int { deliveries.count }
    private var session: WCSession?
    var hasPendingContent: Bool { session?.hasContentPending ?? false }

    func activate() {
        guard WCSession.isSupported() else { status = "Watch connectivity is unavailable."; return }
        let session = WCSession.default; self.session = session
        session.delegate = self; session.activate()
    }
    func send(_ command: NovaWatchCommand, durable: Bool) throws {
        guard let session, session.activationState == .activated else { throw NovaWatchFailure.disconnected }
        let data = try NovaWatchCodec.encode(command)
        if session.isReachable {
            session.sendMessage(["nova.command": data], replyHandler: { [weak self] reply in
                guard let data = reply["nova.envelope"] as? Data, data.count <= NovaWatchCodec.maximumMessageBytes else { return }
                Task { @MainActor in self?.onEnvelope?(data) }
            }, errorHandler: { [weak self] _ in
                Task { @MainActor in
                    self?.status = "Could not reach iPhone. Pending changes are kept."
                    self?.onFailure?(command.id)
                    if durable { self?.enqueue(command, data: data) }
                }
            })
        } else if durable { enqueue(command, data: data) }
        else { throw NovaWatchFailure.disconnected }
    }
    private func enqueue(_ command: NovaWatchCommand, data: Data) {
        guard let session, !session.outstandingUserInfoTransfers.contains(where: { ($0.userInfo["nova.id"] as? String) == command.id.uuidString }) else { return }
        session.transferUserInfo(["nova.command": data, "nova.id": command.id.uuidString])
    }
    func cancelPendingCommands() {
        for transfer in session?.outstandingUserInfoTransfers ?? [] where transfer.userInfo["nova.command"] != nil { transfer.cancel() }
    }
    func publish(_ data: Data) {
        guard let session, session.activationState == .activated, data.count <= NovaWatchCodec.maximumMessageBytes else { return }
        do { try session.updateApplicationContext(["nova.envelope": data]) }
        catch { status = "Snapshot is waiting for the watch." }
    }
    func receipt(_ data: Data) {
        guard let session, data.count <= NovaWatchCodec.maximumMessageBytes else { return }
        session.transferUserInfo(["nova.envelope": data])
    }
    private func updateState() {
        guard let session else { return }
        reachable = session.isReachable
        #if os(iOS)
        available = session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
        #else
        available = session.activationState == .activated
        #endif
        status = reachable ? "Companion reachable" : "Offline · changes wait for iPhone"
        if let data = session.receivedApplicationContext["nova.envelope"] as? Data { onEnvelope?(data) }
        onReady?()
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        Task { @MainActor [weak self] in self?.updateState() }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.updateState() }
    }
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.updateState() }
    }
    #endif
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let data = context["nova.envelope"] as? Data, data.count <= NovaWatchCodec.maximumMessageBytes else { return }
        deliveries.begin()
        Task { @MainActor [weak self, deliveries] in defer { deliveries.end() }; self?.onEnvelope?(data) }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if let data = userInfo["nova.envelope"] as? Data, data.count <= NovaWatchCodec.maximumMessageBytes {
            deliveries.begin()
        Task { @MainActor [weak self, deliveries] in defer { deliveries.end() }; self?.onEnvelope?(data) }
        } else if let data = userInfo["nova.command"] as? Data, data.count <= NovaWatchCodec.maximumMessageBytes {
            deliveries.begin()
            Task { @MainActor [weak self, deliveries] in defer { deliveries.end() }; self?.onCommand?(data, { [weak self] result in self?.receipt(result) }) }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let reply = NovaWatchReply(replyHandler)
        guard let data = message["nova.command"] as? Data, data.count <= NovaWatchCodec.maximumMessageBytes else { reply.send([:]); return }
        Task { @MainActor [weak self] in
            guard let self, let onCommand = self.onCommand else { reply.send([:]); return }
            onCommand(data) { reply.send(["nova.envelope": $0]) }
        }
    }
}

/// WC owns the escaping reply callback; invoking it from the receiving actor is supported.
private final class NovaWatchReply: @unchecked Sendable {
    private let callback: ([String: Any]) -> Void
    init(_ callback: @escaping ([String: Any]) -> Void) { self.callback = callback }
    func send(_ value: [String: Any]) { callback(value) }
}

private final class NovaWatchDeliveryCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return pending }
    func begin() { lock.lock(); pending += 1; lock.unlock() }
    func end() { lock.lock(); pending -= 1; lock.unlock() }
}
