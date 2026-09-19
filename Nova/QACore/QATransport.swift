// QATransport.swift
// ─────────────────────────────────────────────────────────────────────────────
// Shared QACore — transport layer for QA reports and tickets.
//
// Uses QA.config for base URL and request authorization.
// Schema tag: `qa-report/v1` — apps may override the `source` field.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

// MARK: - QAReportTransport

nonisolated enum QAReportTransport {

    // MARK: POST

    /// POST a QA envelope to /qa/reports. Returns true when the bridge responds
    /// with HTTP 200 or 201. Throws on network error.
    static func post(_ payload: [String: Any]) async throws -> Bool {
        guard let base = URL(string: QA.config.workerBaseURL) else {
            throw QATransportError.notConfigured("workerBaseURL is empty")
        }
        let url = base.appendingPathComponent("qa/reports")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        QA.config.authorizeRequest(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return code == 200 || code == 201
    }

    // MARK: POST screenshot

    /// POST a JPEG screenshot to /qa/shots/<ticketNumber>.
    static func postShot(_ jpeg: Data, ticketNumber: String) async throws -> Bool {
        guard let base = URL(string: QA.config.workerBaseURL) else {
            throw QATransportError.notConfigured("workerBaseURL is empty")
        }
        let url = base.appendingPathComponent("qa/shots/\(ticketNumber)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        QA.config.authorizeRequest(&request)
        request.httpBody = jpeg

        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return code == 200 || code == 201
    }

    // MARK: GET device tickets

    /// Pull the device-ticket collection from the worker.
    static func fetchDeviceTickets() async throws -> [[String: Any]] {
        guard let base = URL(string: QA.config.workerBaseURL) else {
            throw QATransportError.notConfigured("workerBaseURL is empty")
        }
        let source = QA.config.source
        let url = base.appendingPathComponent("qa/tickets")
            .appending(queryItems: [URLQueryItem(name: "source", value: source)])
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        QA.config.authorizeRequest(&request)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw QATransportError.httpError(code) }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["tickets"] as? [[String: Any]]
        else { return [] }
        return rows
    }
}

// MARK: - Error

nonisolated enum QATransportError: LocalizedError {
    case notConfigured(String)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let msg): return "QA transport not configured: \(msg)"
        case .httpError(let code): return "QA bridge returned HTTP \(code)"
        }
    }
}
