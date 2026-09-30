//
//  NovaQuickActions.swift
//  Nova
//
//  Home Screen Quick Actions (3D Touch / long-press icon shortcuts).
//  Also provides a "Recently Watched" Spotlight donation so Siri can suggest
//  resuming specific titles from the lock screen or Spotlight search.
//
//  Wire-up in NovaApp or UIApplicationDelegate:
//
//  // Register on launch:
//  NovaQuickActionsManager.shared.registerActions()
//
//  // Handle in scene(_:continue:) or UIApplicationDelegate:
//  NovaQuickActionsManager.shared.handle(shortcutItem: item)
//
//  // Donate after playback:
//  NovaQuickActionsManager.shared.donateRecentWatch(item: mediaItem)
//

import UIKit
import CoreSpotlight
import MobileCoreServices

// MARK: - Manager

@MainActor
final class NovaQuickActionsManager {
    static let shared = NovaQuickActionsManager()

    private init() {}

    // MARK: - Home screen quick actions

    func registerActions(lastWatched: MediaItem? = nil) {
        var actions: [UIApplicationShortcutItem] = []

        if let item = lastWatched {
            actions.append(UIApplicationShortcutItem(
                type: "nova.resume",
                localizedTitle: "Resume",
                localizedSubtitle: item.seriesTitle ?? item.title,
                icon: UIApplicationShortcutIcon(systemImageName: "play.fill"),
                userInfo: ["contentKey": item.contentKey as NSString,
                           "isShow": NSNumber(value: item.isSeries)]
            ))
        }

        actions.append(UIApplicationShortcutItem(
            type: "nova.continue",
            localizedTitle: "Continue Watching",
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: "play.circle"),
            userInfo: nil
        ))

        actions.append(UIApplicationShortcutItem(
            type: "nova.search",
            localizedTitle: "Search",
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: "magnifyingglass"),
            userInfo: nil
        ))

        actions.append(UIApplicationShortcutItem(
            type: "nova.library",
            localizedTitle: "Library",
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: "rectangle.stack.fill"),
            userInfo: nil
        ))

        UIApplication.shared.shortcutItems = actions
    }

    /// Call from the scene delegate with the shortcut item. Each action is routed as the
    /// equivalent nova:// link so it uses the same navigation as widgets and Shortcuts.
    @discardableResult
    func handle(shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let url = Self.url(for: shortcutItem.type, userInfo: shortcutItem.userInfo) else { return false }
        switch shortcutItem.type {
        case "nova.resume":
            NotificationCenter.default.post(name: .novaQuickActionResume, object: nil,
                                            userInfo: shortcutItem.userInfo?["contentKey"].map { ["contentKey": $0] })
        case "nova.search":
            NotificationCenter.default.post(name: .novaQuickActionSearch, object: nil)
        case "nova.library":
            NotificationCenter.default.post(name: .novaQuickActionLibrary, object: nil)
        default:
            break
        }
        // Give a cold-launched scene a moment to attach its URL handler.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            _ = await UIApplication.shared.open(url)
        }
        return true
    }

    /// The deep link for a quick action. Content keys can contain URL delimiters, so they
    /// are percent-encoded as a single path segment.
    static func url(for type: String, userInfo: [String: NSSecureCoding]?) -> URL? {
        switch type {
        case "nova.resume":
            guard let key = userInfo?["contentKey"] as? String, !key.isEmpty else { return URL(string: "nova://continue") }
            let isShow = (userInfo?["isShow"] as? NSNumber)?.boolValue ?? false
            var allowed = CharacterSet.urlPathAllowed
            allowed.remove(charactersIn: "/?#%")
            guard let encoded = key.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
            return URL(string: "nova://\(isShow ? "show" : "movie")/\(encoded)")
        case "nova.continue": return URL(string: "nova://continue")
        case "nova.search": return URL(string: "nova://discover")
        case "nova.library": return URL(string: "nova://library")
        default: return nil
        }
    }

    // MARK: - Spotlight donation

    func donateRecentWatch(item: MediaItem) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .movie)
        attributeSet.title = item.displayTitle
        attributeSet.contentDescription = item.metadata.year.map { "(\($0))" }
        attributeSet.thumbnailURL = item.posterURL

        if let progress = item.duration.map({ item.progressFraction * $0 }) {
            attributeSet.comment = "Watched \(Int(progress / 60)) min"
        }

        let searchItem = CSSearchableItem(
            uniqueIdentifier: "nova.watch.\(item.contentKey)",
            domainIdentifier: "com.sowens.Nova.watched",
            attributeSet: attributeSet
        )
        searchItem.expirationDate = Date().addingTimeInterval(60 * 60 * 24 * 7) // 1 week

        CSSearchableIndex.default().indexSearchableItems([searchItem])
    }

    func removeSpotlightEntry(for item: MediaItem) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: ["nova.watch.\(item.contentKey)"]
        )
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let novaQuickActionResume  = Notification.Name("nova.quickAction.resume")
    static let novaQuickActionSearch  = Notification.Name("nova.quickAction.search")
    static let novaQuickActionLibrary = Notification.Name("nova.quickAction.library")
}
