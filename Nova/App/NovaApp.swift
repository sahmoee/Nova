//
//  NovaApp.swift
//  Nova
//
//  App entry point. Builds the shared environment and shows the root tab view.
//

import SwiftUI

@main
struct NovaApp: App {
    @StateObject private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(environment.library)
                .environmentObject(environment.progress)
                .environmentObject(environment.settings)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                environment.episodeNotifier.requestAuthorization()
                Task { await environment.episodeNotifier.checkForNewStreamableEpisodes() }
            }
        }
    }
}
