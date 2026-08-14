//
//  NovaApp.swift
//  Nova
//
//  App entry point. Builds the shared environment and shows the root tab view.
//

import SwiftUI
#if os(iOS)
import UIKit
import BackgroundTasks

private let episodeRefreshTaskID = "com.nova.ios.episode-refresh"

@MainActor
private final class NovaAppDelegate: NSObject, UIApplicationDelegate {
    static var environment: AppEnvironment?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: episodeRefreshTaskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            Self.handle(refresh)
        }
        return true
    }

    static func scheduleEpisodeRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: episodeRefreshTaskID)
        let request = BGAppRefreshTaskRequest(identifier: episodeRefreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3 * 60 * 60)
        do { try BGTaskScheduler.shared.submit(request) }
        catch { NovaLog.sync.error("Episode refresh scheduling failed: \(error.localizedDescription, privacy: .public)") }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        scheduleEpisodeRefresh()
        let work = Task { @MainActor in
            guard let environment else { task.setTaskCompleted(success: false); return }
            await environment.episodeNotifier.checkForNewStreamableEpisodes()
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }
}
#endif

@main
struct NovaApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(NovaAppDelegate.self) private var appDelegate
    #endif
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
                            UnifiedQAReporter(app: "Nova", source: "nova-app", prefix: "NVA",
                                              diagnostics: { environment.qaDiagnostics() })
                                .padding(.trailing, 16)
                                .padding(.bottom, 82)
                        }
                    }
                }
            }
                .onAppear {
                    #if os(iOS)
                    NovaAppDelegate.environment = environment
                    #endif
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
            } else if phase == .background {
                #if os(iOS)
                NovaAppDelegate.scheduleEpisodeRefresh()
                #endif
            }
        }
    }
}
