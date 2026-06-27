//
//  URLValidation.swift
//  FrameTV
//
//  Helpers for validating user-pasted URLs before adding them to the library.
//

import Foundation

enum URLValidationError: LocalizedError {
    case empty
    case malformed
    case unsupportedScheme
    case unreachable
    case notPlayable

    var errorDescription: String? {
        switch self {
        case .empty:             return "Please enter a URL."
        case .malformed:         return "That doesn't look like a valid URL."
        case .unsupportedScheme: return "Only http and https URLs are supported."
        case .unreachable:       return "Couldn't reach that URL. Check the link and your connection."
        case .notPlayable:       return "That URL doesn't appear to point to a playable video."
        }
    }
}

enum URLValidation {
    /// Performs basic, synchronous structural validation.
    /// Network reachability is checked separately by DirectURLService.
    static func validateStructure(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw URLValidationError.empty }
        guard let url = URL(string: trimmed) else { throw URLValidationError.malformed }
        guard let scheme = url.scheme?.lowercased() else { throw URLValidationError.malformed }
        guard scheme == "http" || scheme == "https" else {
            throw URLValidationError.unsupportedScheme
        }
        guard url.host != nil else { throw URLValidationError.malformed }
        return url
    }

    /// Content types we consider directly playable from a HEAD response.
    static let playableContentTypes: Set<String> = [
        "video/mp4", "video/x-m4v", "video/quicktime",
        "video/x-matroska", "video/x-msvideo", "video/webm",
        "application/octet-stream" // many servers send this for video files
    ]

    static func isPlayableContentType(_ value: String?) -> Bool {
        guard let value = value?.lowercased() else { return false }
        // Take only the part before any "; charset=..." suffix.
        let base = value.split(separator: ";").first.map(String.init) ?? value
        return playableContentTypes.contains(base.trimmingCharacters(in: .whitespaces))
    }

    /// True if a magnet string is at least structurally a magnet URI.
    static func isMagnetLink(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("magnet:?")
    }
}
