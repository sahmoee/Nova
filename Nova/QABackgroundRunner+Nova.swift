// QABackgroundRunner+Nova.swift
import Foundation

@MainActor
final class QABackgroundRunner {
    static let shared = QABackgroundRunner()
    private init() {}
    private var task: Task<Void, Never>?

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runChecks()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    private func runChecks() async {
        await NovaQAInvariants.runAll()
        await autoFileBlockers()
        QATriage.shared.refresh()
    }

    private func autoFileBlockers() async {
        for v in QARecorder.shared.openViolations {
            let filed = QATicketStore.shared.tickets.contains {
                $0.origin == .automatic && $0.title.contains(v) && !$0.status.isClosed
            }
            guard !filed else { continue }
            _ = QATicketStore.shared.open(
                title: v, body: "Auto-filed: invariant violation.",
                severity: .blocker, requiresManualReview: false,
                context: QAContextCapture.current(), origin: .automatic,
                automaticCheckID: nil, screenshot: nil
            )
        }
    }
}
