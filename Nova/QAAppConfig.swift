// QAAppConfig.swift — Nova
import Foundation
import UIKit

enum QAAppSetup {

    static func configure() {
        let bundle  = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build   = Int(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0

        QA.configure(QAConfiguration(
            source:           "nova-app",
            ticketPrefix:     "NVA",
            workerBaseURL:    "https://worker.sowensstudios.com",
            appName:          "Nova",
            version:          version,
            buildNumber:      build,
            authorizeRequest: { req in
                req.setValue("Bearer \(QAWorkerToken.nova)", forHTTPHeaderField: "Authorization")
            },
            isOnline: { ConnectivityMonitor.shared.isOnline }
        ))

        QAChecklistView.checklistProvider = { NovaQAChecklist.sections }
        QARunLog.checkTitlesProvider      = { NovaQAChecklist.titleMap }
    }

    @MainActor
    static func attachBubble(to scene: UIWindowScene) {
#if DEBUG
        QAFloatingButtonWindow.attach(to: scene)
        QABackgroundRunner.shared.start()
#endif
    }
}

enum QAWorkerToken {
    static let nova = Bundle.main.object(forInfoDictionaryKey: "QAWorkerToken") as? String ?? ""
}
