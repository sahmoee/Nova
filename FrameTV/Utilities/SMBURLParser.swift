//
//  SMBURLParser.swift
//  FrameTV
//
//  Pure parsing for SMB server input: accepts a hostname, IP, or full path (with
//  or without an smb:// scheme) and splits it into server / share / path. Kept
//  separate from the view so it can be unit tested.
//

import Foundation

enum SMBURLParser {

    struct Parsed: Equatable {
        var host: String
        var share: String?
        var path: String?
    }

    /// Parses a raw server string into host / share / path. Accepts a bare host,
    /// a host with a scheme (smb://host), and a full path (smb://host/share/sub).
    /// Returns nil only when there's no usable host at all.
    static func parse(_ raw: String) -> Parsed? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        // Strip a scheme if present.
        for scheme in ["smb://", "smb:\\\\", "cifs://", "//"] {
            if s.lowercased().hasPrefix(scheme.lowercased()) {
                s = String(s.dropFirst(scheme.count))
                break
            }
        }

        // Trim any leading/trailing slashes left over (e.g. "smb://host/").
        while s.hasPrefix("/") { s.removeFirst() }
        while s.hasSuffix("/") { s.removeLast() }
        guard !s.isEmpty else { return nil }

        guard s.contains("/") else {
            // Host only — always return it (the scheme/slashes are stripped).
            return Parsed(host: s, share: nil, path: nil)
        }

        let parts = s.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let server = parts.first, !server.isEmpty else { return nil }
        let share = parts.count >= 2 ? parts[1] : nil
        let path = parts.count >= 3 ? "/" + parts[2...].joined(separator: "/") : nil
        return Parsed(host: server, share: share, path: path)
    }
}
