//
//  DirectURLService.swift
//  Astra
//
//  Validates direct video URLs (structure + optional HEAD reachability check)
//  and builds MediaItems from them.
//

import Foundation

actor DirectURLService {

    private let session: URLSession

    init(session: URLSession = AppNetworking.shared) {
        self.session = session
    }

    /// Validates structure, then attempts a HEAD request to confirm reachability
    /// and (best-effort) content type. Network failures surface as errors, but a
    /// missing/ambiguous content type does NOT block — many servers misreport it.
    func validate(_ raw: String) async throws -> URL {
        let url = try URLValidation.validateStructure(raw)

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return url }

            // Reject obvious client/server errors.
            guard (200...399).contains(http.statusCode) else {
                throw URLValidationError.unreachable
            }

            // Best-effort content type check. If present and clearly not video,
            // we still allow it through (some CDNs lie), but we could warn later.
            _ = http.value(forHTTPHeaderField: "Content-Type")
            return url
        } catch let error as URLValidationError {
            throw error
        } catch {
            // Some servers reject HEAD outright (405). Fall back to allowing the URL;
            // the player will surface a real playback error if it truly fails.
            throw URLValidationError.unreachable
        }
    }

    /// Builds a MediaItem for a validated direct URL.
    func makeMediaItem(
        url: URL,
        title: String?,
        posterURL: URL?,
        legalAccessConfirmed: Bool
    ) -> MediaItem {
        let resolvedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = url.lastPathComponent
        let displayTitle = (resolvedTitle?.isEmpty == false ? resolvedTitle! : filename)

        return MediaItem(
            title: displayTitle,
            sourceType: .directURL,
            playbackURL: url,
            posterURL: posterURL,
            legalAccessConfirmed: legalAccessConfirmed,
            metadata: MediaMetadata(filename: filename)
        )
    }
}
