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
    @AppStorage(UnifiedQASettings.enabledKey) private var qaEnabled = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        if qaEnabled {
                            UnifiedQAReporter(app: "Nova", source: "nova-app", prefix: "NVA")
                                .padding(.trailing, 16)
                                .padding(.bottom, 82)
                        }
                    }
                }
            }
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
