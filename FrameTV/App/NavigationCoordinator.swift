//
//  NavigationCoordinator.swift
//  FrameTV
//
//  Coordinates tab selection and per-tab navigation paths so that tapping the
//  already-selected tab pops that tab's stack back to its root. Each tab binds
//  its NavigationStack to the matching path here.
//

import SwiftUI
import Combine

enum AppTab: Hashable, CaseIterable {
    case home, discover, library, settings

    /// Display name used by the tvOS menu and the iOS tab bar.
    var title: String {
        switch self {
        case .home:     return "Home"
        case .discover: return "Discover"
        case .library:  return "Library"
        case .settings: return "Settings"
        }
    }

    /// SF Symbol used by the tvOS menu and the iOS tab bar.
    var systemImage: String {
        switch self {
        case .home:     return "house.fill"
        case .discover: return "magnifyingglass"
        case .library:  return "rectangle.stack.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

@MainActor
final class NavigationCoordinator: ObservableObject {
    @Published var selection: AppTab = .home

    // One navigation path per tab.
    @Published var homePath = NavigationPath()
    @Published var discoverPath = NavigationPath()
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
        case .library:  return libraryPath.isEmpty
        case .settings: return settingsPath.isEmpty
        }
    }
}
