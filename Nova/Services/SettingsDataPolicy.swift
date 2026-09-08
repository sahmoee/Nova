import Foundation

/// Additive deletion markers protect updated devices from stale cloud mirrors and
/// automatic setup backups. A device-only reset pauses that category's sync until
/// the user explicitly chooses Push or Pull.
enum SettingsDataDomain: String, CaseIterable, Identifiable {
    case history, preferences, library, addons
    var id: String { rawValue }
    var title: String {
        switch self {
        case .history: return "Watch History"
        case .preferences: return "Preferences"
        case .library: return "Library"
        case .addons: return "Addons"
        }
    }
    var deletionKey: String { "nova.data.deletedAt." + rawValue }
    var pausedKey: String { "nova.data.paused." + rawValue }
    var appliedKey: String { "nova.data.appliedDeletion." + rawValue }
}

enum SettingsDataPolicy {
    static let preferencePrefixes = ["settings.", "discover.", "player.", "home.", "ai.", "whatsNew."]

    static func domain(for key: String) -> SettingsDataDomain? {
        if ["stream.history.v1", "cloud.stream.history.v1"].contains(key) { return .history }
        if key == "cloud.addons" { return .addons }
        if ["cloud.library.v1", "cloud.library.revision", "cloud.collections.v1", "library.queue.v1"].contains(key) {
            return .library
        }
        if preferencePrefixes.contains(where: key.hasPrefix) || ["reco.feedback.v1", "cloud.reco.feedback.v1"].contains(key)
            || ["nova.tvFocusGlowEnabled", "nova.tvFocusGlowStrength"].contains(key) { return .preferences }
        return nil
    }

    static func cloudPreferenceKey(for key: String) -> String {
        key == "reco.feedback.v1" ? "cloud.reco.feedback.v1" : key
    }

    static func localPreferenceKey(for key: String) -> String {
        key == "cloud.reco.feedback.v1" ? "reco.feedback.v1" : key
    }

    static func accepts(revision: Double, deletedAt: Double, paused: Bool) -> Bool {
        !paused && (deletedAt <= 0 || (revision.isFinite && revision > deletedAt))
    }

    static func acceptsSnapshot(createdAt: Date, deletedAt: Double, paused: Bool) -> Bool {
        accepts(revision: createdAt.timeIntervalSince1970, deletedAt: deletedAt, paused: paused)
    }

    static func acceptsSnapshot(acknowledgedDeletion: Double, deletedAt: Double, paused: Bool) -> Bool {
        !paused && (deletedAt <= 0 || (acknowledgedDeletion.isFinite && acknowledgedDeletion >= deletedAt))
    }

    static func validSnapshotURL(_ value: String) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false, url.user == nil, url.password == nil,
              url.fragment == nil else { return nil }
        return url
    }

    static func sanitizeSnapshot(_ original: BackupSnapshot,
                                 deletedAt: [SettingsDataDomain: Double],
                                 paused: Set<SettingsDataDomain>) -> BackupSnapshot {
        var snapshot = original
        func allowed(_ domain: SettingsDataDomain) -> Bool {
            acceptsSnapshot(acknowledgedDeletion: original.deletionAcknowledgements[domain.rawValue] ?? 0,
                            deletedAt: deletedAt[domain] ?? 0, paused: paused.contains(domain))
        }
        snapshot.settings = snapshot.settings.filter { key, _ in
            guard let domain = domain(for: key), domain == .preferences || domain == .history else { return false }
            return allowed(domain)
        }
        if !allowed(.addons) { snapshot.addonsJSON = nil }
        return snapshot
    }

    static func preservingPausedCategories(in current: BackupSnapshot, previous: BackupSnapshot?,
                                           paused: Set<SettingsDataDomain>) -> BackupSnapshot {
        var result = current
        for domain in paused {
            result.settings = result.settings.filter { self.domain(for: $0.key) != domain }
            for (key, value) in previous?.settings ?? [:] where self.domain(for: key) == domain {
                result.settings[key] = value
            }
            if domain == .addons { result.addonsJSON = previous?.addonsJSON }
            result.deletionAcknowledgements[domain.rawValue] = previous?.deletionAcknowledgements[domain.rawValue]
        }
        return result
    }
}
