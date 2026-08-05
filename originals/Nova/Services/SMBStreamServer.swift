//
//  SMBStreamServer.swift
//  Nova
//
//  A minimal local HTTP server (127.0.0.1) that bridges SMB files to AVPlayer.
//  AVPlayer requests byte ranges over HTTP; this server fulfills each range by
//  reading the corresponding bytes from the SMB file via AMSMB2. Nothing is
//  written to disk — bytes are streamed on demand — and the server only serves
//  the single file the user chose to play.
//

import Foundation
import Network
import AMSMB2

actor SMBStreamServer {
    static let shared = SMBStreamServer()

    private var listener: NWListener?
    private var port: UInt16 = 0

    // The currently-served file.
    private var client: SMB2Manager?
    private var smbPath: String = ""
    private var fileName: String = ""
    private var fileSize: Int64 = 0

    /// Begins serving the given SMB file and returns a local URL for AVPlayer.
    func serve(client: SMB2Manager, smbPath: String, fileName: String, shareID: UUID) async throws -> URL {
        // Resolve the file size up front (needed for range responses).
        let attrs = try await client.attributesOfItem(atPath: smbPath)
        let size: Int64
        if let n = attrs[.fileSizeKey] as? Int64 { size = n }
        else if let n = attrs[.fileSizeKey] as? Int { size = Int64(n) }
        else if let n = attrs[.fileSizeKey] as? NSNumber { size = n.int64Value }
        else { size = 0 }
        guard size > 0 else { throw SMBError.streamingUnavailable }

        self.client = client
        self.smbPath = smbPath
        self.fileName = fileName
        self.fileSize = size

        try startListenerIfNeeded()

        // Percent-encode the filename so AVPlayer/HTTP handles spaces etc.
        let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "video"
        guard let url = URL(string: "http://127.0.0.1:\(port)/\(encoded)") else {
            throw SMBError.streamingUnavailable
        }
        return url
    }

    // MARK: - Listener

    private func startListenerIfNeeded() throws {
        if listener != nil { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Bind to loopback only.
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .global(qos: .userInitiated))
            Task { await self?.handle(conn) }
        }
        listener.stateUpdateHandler = { _ in }
        listener.start(queue: .global(qos: .userInitiated))
        // Capture the assigned port.
        self.listener = listener
        // Wait briefly for the port to be assigned.
        for _ in 0..<50 {
            if let p = listener.port?.rawValue, p != 0 { self.port = p; break }
            usleep(10_000)
        }
        if port == 0 { throw SMBError.streamingUnavailable }
    }

    // MARK: - Connection handling

    private func handle(_ conn: NWConnection) async {
        // Read the HTTP request headers.
        guard let request = await readRequest(conn) else { conn.cancel(); return }

        // Parse a Range header if present.
        let (start, end) = parseRange(request, fileSize: fileSize)
        let length = end - start + 1

        await sendResponse(conn, start: start, end: end, length: length)
    }

    private func readRequest(_ conn: NWConnection) async -> String? {
        await withCheckedContinuation { cont in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                if let data, let s = String(data: data, encoding: .utf8) {
                    cont.resume(returning: s)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func parseRange(_ request: String, fileSize: Int64) -> (Int64, Int64) {
        // Default: whole file.
        var start: Int64 = 0
        var end: Int64 = fileSize - 1
        for line in request.split(separator: "\r\n") {
            if line.lowercased().hasPrefix("range:") {
                // e.g. "Range: bytes=12345-" or "bytes=0-1023"
                if let eq = line.firstIndex(of: "=") {
                    let spec = line[line.index(after: eq)...]
                    let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
                    if let s = parts.first, let sv = Int64(s.trimmingCharacters(in: .whitespaces)) {
                        start = sv
                    }
                    if parts.count > 1, let ev = Int64(parts[1].trimmingCharacters(in: .whitespaces)) {
                        end = ev
                    }
                }
            }
        }
        start = max(0, min(start, fileSize - 1))
        end = max(start, min(end, fileSize - 1))
        return (start, end)
    }

    private func sendResponse(_ conn: NWConnection, start: Int64, end: Int64, length: Int64) async {
        guard let client else { conn.cancel(); return }

        // HTTP headers: 206 Partial Content with the requested range.
        let header = """
        HTTP/1.1 206 Partial Content\r
        Content-Type: video/mp4\r
        Accept-Ranges: bytes\r
        Content-Length: \(length)\r
        Content-Range: bytes \(start)-\(end)/\(fileSize)\r
        Connection: close\r
        \r

        """
        conn.send(content: header.data(using: .utf8), completion: .contentProcessed { _ in })

        // Stream the requested byte range from SMB. AMSMB2 returns an async stream
        // of Data chunks; forward each chunk to the HTTP connection as it arrives.
        let upperExclusive = end + 1
        let byteRange = Int64(start)..<Int64(upperExclusive)
        do {
            for try await chunk in client.contents(atPath: smbPath, range: byteRange) {
                if chunk.isEmpty { continue }
                await sendData(conn, chunk)
            }
        } catch {
            NovaLog.network.error("SMB stream read failed: \(error.localizedDescription, privacy: .public)")
        }
        conn.cancel()
    }

    private func sendData(_ conn: NWConnection, _ data: Data) async {
        await withCheckedContinuation { cont in
            conn.send(content: data, completion: .contentProcessed { _ in cont.resume() })
        }
    }
}
