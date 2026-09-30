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

    /// Supplies a scene delegate only for Home Screen quick actions; SwiftUI still owns
    /// the window and content.
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = NovaSceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // NovaAppDelegate is main-actor isolated. Supplying no queue lets
        // BGTaskScheduler invoke this closure on a worker queue, which violates
        // that isolation and traps in Swift 6 before the refresh can begin.
        // The refresh itself is still asynchronous inside `handle`.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: episodeRefreshTaskID,
                                        using: .main) { task in
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
/// Receives Home Screen quick actions, both at cold launch and while running.
@MainActor
final class NovaSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let shortcut = connectionOptions.shortcutItem {
            NovaQuickActionsManager.shared.handle(shortcutItem: shortcut)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(NovaQuickActionsManager.shared.handle(shortcutItem: shortcutItem))
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
                    .studioAgeGate()
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
                .novaThemeBoundary()
        }
        .onChange(of: scenePhase) { _, phase in
            #if os(iOS)
            NovaPhoneWatchBridge.shared.sceneChanged()
            #endif
            if phase == .active {
                environment.episodeNotifier.requestAuthorization()
                Task { await environment.episodeNotifier.checkForNewStreamableEpisodes() }
            } else if phase == .background {
                #if os(iOS)
                NovaAppDelegate.scheduleEpisodeRefresh()
                // Keep the Home Screen "Resume" shortcut pointed at the latest title.
                NovaQuickActionsManager.shared.registerActions(
                    lastWatched: environment.library.continueWatching.first ?? environment.library.recentlyWatched.first)
                #endif
            }
        }
    }
}
