//
//  NavigationCoordinator.swift
//  Nova
//
//  Coordinates tab selection and per-tab navigation paths so that tapping the
//  already-selected tab pops that tab's stack back to its root. Each tab binds
//  its NavigationStack to the matching path here.
//

import SwiftUI
import Combine

enum AppTab: Hashable, CaseIterable {
    case home, discover, movies, series, library, ai, settings

    /// Primary destinations shown in the Omni-style sidebar (tvOS, iPad, Mac). AI
    /// remains an internal destination for older deep links and saved state, but is
    /// entered through Search.
    static let primaryTabs: [AppTab] = [.home, .discover, .movies, .series, .library, .settings]

    /// iPhone's tab bar keeps four destinations; Movies and Series are reached from
    /// the Home filter chips instead.
    static let phoneTabs: [AppTab] = [.home, .discover, .library, .settings]

    /// Display name used by the tvOS menu and the iOS tab bar.
    var title: String {
        switch self {
        case .home:     return "Home"
        case .discover: return "Search"
        case .movies:   return "Movies"
        case .series:   return "Series"
        case .ai:       return "Smart Search"
        case .library:  return "Library"
        case .settings: return "Settings"
        }
    }

    /// SF Symbol used by the tvOS menu and the iOS tab bar.
    var systemImage: String {
        switch self {
        case .home:     return "house.fill"
        case .discover: return "magnifyingglass"
        case .movies:   return "film.fill"
        case .series:   return "tv.fill"
        case .ai:       return "sparkles"
        case .library:  return "rectangle.stack.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

@MainActor
final class NavigationCoordinator: ObservableObject {
    @Published var selection: AppTab = .home

    /// Set when a deep link targets a specific library item; LibraryView observes this
    /// and opens the matching item's detail, then clears it.
    @Published var pendingSearchQuery: String?
    @Published var pendingContentKey: String?
    /// An addon manifest proposed by a stremio:// link, awaiting the user's OK.
    @Published var pendingAddonInstall: URL?

    // One navigation path per tab.
    @Published var homePath = NavigationPath()
    @Published var discoverPath = NavigationPath()
    @Published var moviesPath = NavigationPath()
    @Published var seriesPath = NavigationPath()
    @Published var aiPath = NavigationPath()
    @Published var libraryPath = NavigationPath()
    @Published var settingsPath = NavigationPath()

    /// A binding that, when set to an already-selected tab, pops that tab to root.
    /// Otherwise it just switches tabs.
    var selectionBinding: Binding<AppTab> {
        Binding(
            get: { self.selection },
            set: { newValue in
                if newValue == self.selection {
                    self.popToRoot(newValue)
                } else {
                    self.selection = newValue
                }
            }
        )
    }

    func popToRoot(_ tab: AppTab) {
        switch tab {
        case .home:     homePath = NavigationPath()
        case .discover: discoverPath = NavigationPath()
        case .movies:   moviesPath = NavigationPath()
        case .series:   seriesPath = NavigationPath()
        case .ai:       aiPath = NavigationPath()
        case .library:  libraryPath = NavigationPath()
        case .settings: settingsPath = NavigationPath()
        }
    }

    /// Whether the given tab's navigation stack is at its root (nothing pushed).
    /// Used on tvOS so the Menu button pops a pushed detail screen before it
    /// summons the section menu.
    func isAtRoot(_ tab: AppTab) -> Bool {
        switch tab {
        case .home:     return homePath.isEmpty
        case .discover: return discoverPath.isEmpty
        case .movies:   return moviesPath.isEmpty
        case .series:   return seriesPath.isEmpty
        case .ai:       return aiPath.isEmpty
        case .library:  return libraryPath.isEmpty
        case .settings: return settingsPath.isEmpty
        }
    }

    /// Pops a single level from the given tab's navigation stack (tvOS back).
    func popOne(_ tab: AppTab) {
        switch tab {
        case .home:     if !homePath.isEmpty { homePath.removeLast() }
        case .discover: if !discoverPath.isEmpty { discoverPath.removeLast() }
        case .movies:   if !moviesPath.isEmpty { moviesPath.removeLast() }
        case .series:   if !seriesPath.isEmpty { seriesPath.removeLast() }
        case .ai:       if !aiPath.isEmpty { aiPath.removeLast() }
        case .library:  if !libraryPath.isEmpty { libraryPath.removeLast() }
        case .settings: if !settingsPath.isEmpty { settingsPath.removeLast() }
        }
    }

    /// Routes a parsed deep link to the right place in the app.
    func handle(_ link: DeepLink) {
        switch link {
        case .tab(let tab):
            let destination = tab == .ai ? AppTab.discover : tab
            selection = destination
            popToRoot(destination)
        case .search(let query):
            selection = .discover
            popToRoot(.discover)
            pendingSearchQuery = query
        case .continueWatching:
            selection = .library
            popToRoot(.library)
        case .settingsSources:
            // Land on Settings; Sources is one tap away. (Auto-push would require
            // refactoring Settings to value-based navigation; deferred.)
            selection = .settings
            popToRoot(.settings)
        case .installAddon(let manifestURL):
            pendingAddonInstall = manifestURL
        case .content(let key, _):
            // Library holds the user's items; jump there and ask it to open the match.
            selection = .library
            popToRoot(.library)
            pendingContentKey = key
        }
    }

    /// Convenience: parse and handle a URL in one step. Returns true if handled.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard let link = DeepLink.parse(url) else { return false }
        handle(link)
        return true
    }
}
