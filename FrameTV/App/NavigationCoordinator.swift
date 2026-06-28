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

enum AppTab: Hashable {
    case home, discover, library, settings
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
}
