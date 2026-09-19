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
                localizedSubtitle: item.title,
                icon: UIApplicationShortcutIcon(systemImageName: "play.fill"),
                userInfo: ["contentKey": item.contentKey as NSString]
            ))
        }

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

    /// Call from scene(_:continue:) with the shortcut item.
    func handle(shortcutItem: UIApplicationShortcutItem) {
        switch shortcutItem.type {
        case "nova.resume":
            let contentKey = shortcutItem.userInfo?["contentKey"] as? String
            NotificationCenter.default.post(
                name: .novaQuickActionResume,
                object: nil,
                userInfo: contentKey.map { ["contentKey": $0] }
            )
        case "nova.search":
            NotificationCenter.default.post(name: .novaQuickActionSearch, object: nil)
        case "nova.library":
            NotificationCenter.default.post(name: .novaQuickActionLibrary, object: nil)
        default:
            break
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
