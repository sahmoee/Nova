// QAIdentity.swift
// ─────────────────────────────────────────────────────────────────────────────
// Shared QACore — tester identity, device fingerprint.
//
// Tickets know which tester filed them and from which device. Runs know too.
// "Unassigned" is a valid state (no tester selected) and the system still works.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import UIKit

// MARK: - Identity record

/// Everything about a tester + their device that rides on a ticket or run.
/// `nonisolated` + `Sendable` because it crosses to export paths off the main actor.
nonisolated struct QAReportIdentity: Codable, Sendable, Equatable {
    /// "Key · iPhone 16 Pro" or "Shalise · iPad Air (5th gen)"
    var label: String
    /// "iPhone" or "iPad"
    var deviceFamily: String
    /// "iPhone17,2" — the Mach identifier, not the marketing name
    var modelIdentifier: String
    /// Marketing name derived from the identifier: "iPhone 16 Pro"
    var modelName: String
    /// Stable per-install UUID stored in UserDefaults. Different from
    /// `UIDevice.identifierForVendor` which resets on reinstall.
    var installationID: String
    /// iOS/iPadOS version string
    var osVersion: String
    /// Tester name (from QAIdentityStore)
    var testerName: String

    static func sameOrigin(_ a: QAReportIdentity?, _ b: QAReportIdentity?) -> Bool {
        guard let a, let b else { return false }
        return a.installationID == b.installationID
    }
}

// MARK: - Store

@MainActor
@Observable
final class QAIdentityStore {
    static let shared = QAIdentityStore()

    private static let testerKey        = "qa.identity.tester"
    private static let installIDKey     = "qa.identity.installID"

    private(set) var testerName: String = ""

    var availableTesters: [String] = ["Key", "Shalise"]

    private init() {
        testerName = UserDefaults.standard.string(forKey: Self.testerKey) ?? ""
        if UserDefaults.standard.string(forKey: Self.installIDKey) == nil {
            UserDefaults.standard.set(UUID().uuidString, forKey: Self.installIDKey)
        }
    }

    var installationID: String {
        UserDefaults.standard.string(forKey: Self.installIDKey) ?? "unknown"
    }

    func setTester(_ name: String) {
        testerName = name
        UserDefaults.standard.set(name, forKey: Self.testerKey)
    }

    /// Snapshot for embedding in a ticket or run.
    func capture() -> QAReportIdentity? {
        let identifier = Self.modelIdentifier()
        return QAReportIdentity(
            label: testerName.isEmpty
                ? "\(Self.modelName(identifier))"
                : "\(testerName) · \(Self.modelName(identifier))",
            deviceFamily: UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone",
            modelIdentifier: identifier,
            modelName: Self.modelName(identifier),
            installationID: installationID,
            osVersion: UIDevice.current.systemVersion,
            testerName: testerName
        )
    }

    // MARK: Device model lookup

    nonisolated static func modelIdentifier() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { ptr in
            String(cString: ptr.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
    }

    nonisolated static func modelName(_ id: String) -> String {
        let table: [String: String] = [
            // iPhone 16
            "iPhone17,1": "iPhone 16 Pro",   "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16",        "iPhone17,4": "iPhone 16 Plus",
            // iPhone 15
            "iPhone16,1": "iPhone 15 Pro",   "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone15,4": "iPhone 15",        "iPhone15,5": "iPhone 15 Plus",
            // iPhone 14
            "iPhone15,2": "iPhone 14 Pro",   "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone14,7": "iPhone 14",        "iPhone14,8": "iPhone 14 Plus",
            // iPhone 13
            "iPhone14,2": "iPhone 13 Pro",   "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,4": "iPhone 13 mini",  "iPhone14,5": "iPhone 13",
            // iPhone 12
            "iPhone13,1": "iPhone 12 mini",  "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro",   "iPhone13,4": "iPhone 12 Pro Max",
            // iPhone SE
            "iPhone14,6": "iPhone SE (3rd gen)", "iPhone12,8": "iPhone SE (2nd gen)",
            // iPad Pro
            "iPad14,5": "iPad Pro 11\" (4th gen)", "iPad14,6": "iPad Pro 12.9\" (6th gen)",
            "iPad16,3": "iPad Pro 11\" (M4)",      "iPad16,4": "iPad Pro 13\" (M4)",
            // iPad Air
            "iPad13,16": "iPad Air 5",  "iPad14,8": "iPad Air 11\" (M2)",
            // iPad mini
            "iPad14,1": "iPad mini (6th gen)",
            // Simulator
            "x86_64": "Simulator (Intel)", "arm64": "Simulator (Apple Silicon)",
        ]
        return table[id] ?? id
    }
}
