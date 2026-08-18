//
//  SMBURLParser.swift
//  Nova
//
//  Pure parsing for SMB server input: accepts a hostname, IP, or full path (with
//  or without an smb:// scheme) and splits it into server / share / path. Kept
//  separate from the view so it can be unit tested.
//

import Foundation
import Darwin

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

/// Prefers a Tailscale MagicDNS identity while retaining the entered host as a
/// reconnect-safe fallback. Reverse DNS never runs on the UI thread.
enum SMBHostResolver {
    static func preferredHost(for host: String) async -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isIPAddress(trimmed) else { return trimmed.lowercased() }
        return await Task.detached(priority: .utility) {
            reverseTailscaleName(for: trimmed) ?? trimmed
        }.value
    }

    static func isTailscaleName(_ host: String) -> Bool {
        host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")).hasSuffix(".ts.net")
    }

    private static func isIPAddress(_ host: String) -> Bool {
        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        return host.withCString { inet_pton(AF_INET, $0, &ipv4) == 1 || inet_pton(AF_INET6, $0, &ipv6) == 1 }
    }

    private static func reverseTailscaleName(for host: String) -> String? {
        var storage = sockaddr_storage()
        var length: socklen_t = 0
        if host.withCString({ pointer in
            withUnsafeMutablePointer(to: &storage) { rawStorage in
                rawStorage.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { address in
                    address.pointee.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                    address.pointee.sin_family = sa_family_t(AF_INET)
                    length = socklen_t(MemoryLayout<sockaddr_in>.size)
                    return inet_pton(AF_INET, pointer, &address.pointee.sin_addr)
                }
            }
        }) != 1 {
            guard host.withCString({ pointer in
                withUnsafeMutablePointer(to: &storage) { rawStorage in
                    rawStorage.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { address in
                        address.pointee.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
                        address.pointee.sin6_family = sa_family_t(AF_INET6)
                        length = socklen_t(MemoryLayout<sockaddr_in6>.size)
                        return inet_pton(AF_INET6, pointer, &address.pointee.sin6_addr)
                    }
                }
            }) == 1 else { return nil }
        }

        var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &storage) { rawStorage in
            rawStorage.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                getnameinfo(address, length, &name, socklen_t(name.count), nil, 0, NI_NAMEREQD)
            }
        }
        guard result == 0 else { return nil }
        let resolved = String(cString: name).trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return isTailscaleName(resolved) ? resolved : nil
    }
}
