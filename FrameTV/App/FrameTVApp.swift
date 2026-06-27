//
//  FrameTVApp.swift
//  FrameTV
//
//  App entry point. Builds the shared environment and shows the root tab view.
//

import SwiftUI

@main
struct FrameTVApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(environment.library)
                .environmentObject(environment.progress)
                .environmentObject(environment.settings)
                .preferredColorScheme(.dark)
        }
    }
}
