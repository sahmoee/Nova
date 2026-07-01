//
//  DebugReportView.swift
//  FrameTV
//
//  Builds a plain-text diagnostic report with NO secrets (no tokens, passwords, or
//  full source URLs), useful for testing on real devices and for support. On iPhone
//  and iPad it can be shared; on Apple TV it's shown on screen to read or photograph.
//

import SwiftUI

struct DebugReportView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var env: AppEnvironment

    @State private var report: String = ""
    #if os(iOS)
    @State private var showShare = false
    #endif

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Debug Report")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("A snapshot for troubleshooting. It contains no passwords, tokens, or full source links.")
                        .font(.appFont(18))
                        .foregroundStyle(Theme.Colors.textSecondary)

                    Text(report)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .textSelection(.enabled)
                        .padding(Theme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                    #if os(iOS)
                    HStack(spacing: Theme.Spacing.md) {
                        FocusableButton(title: "Copy", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = report
                            ToastCenter.shared.show("Copied", systemImage: "checkmark")
                        }
                        FocusableButton(title: "Share", systemImage: "square.and.arrow.up") {
                            showShare = true
                        }
                    }
                    #else
                    Text("On Apple TV, read the report above or open Debug Report on your iPhone to share it.")
                        .font(.appFont(15))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    #endif
                }
                .padding(Theme.Spacing.edge)
                .frame(maxWidth: Theme.contentMaxWidth(1000), alignment: .leading)
            }
        }
        .onAppear { report = buildReport() }
        #if os(iOS)
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [report])
        }
        #endif
    }

    private func buildReport() -> String {
        var lines: [String] = []
        func kv(_ k: String, _ v: String) { lines.append("\(k): \(v)") }

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"

        lines.append("=== FrameTV Debug Report ===")
        kv("Generated", Date().formatted(date: .abbreviated, time: .shortened))
        kv("App version", "\(version) (\(build))")
        #if os(tvOS)
        kv("Platform", "tvOS")
        #else
        kv("Platform", "iOS/iPadOS")
        #endif

        lines.append("")
        lines.append("--- Sources (configured, no secrets) ---")
        kv("TMDB key set", env.tmdb.hasKey ? "yes" : "no")
        kv("OMDb key set", env.omdb.hasKey ? "yes" : "no")
        kv("Real-Debrid connected", KeychainStore.shared.realDebridToken != nil ? "yes" : "no")
        kv("Trakt connected", AppConfig.shared.value(for: .traktAccessToken)?.isEmpty == false ? "yes" : "no")

        lines.append("")
        lines.append("--- Playback preferences ---")
        kv("Preferred engine", settings.builtInPlayer.rawValue)
        kv("Require cached streams", settings.requireCachedStreams ? "yes" : "no")
        kv("Max stream size (GB)", "\(settings.maxStreamSizeGB)")
        kv("Min seeders", "\(settings.minSeeders)")
        kv("Bandwidth saver", settings.bandwidthSaver ? "on" : "off")
        kv("Safe mode", settings.safeMode ? "on" : "off")

        lines.append("")
        lines.append("--- Library ---")
        kv("Total items", "\(library.items.count)")
        let missingPosters = library.items.filter { $0.posterURL == nil }.count
        let unmatched = library.items.filter { $0.contentID?.tmdb == nil }.count
        kv("Missing posters", "\(missingPosters)")
        kv("Unmatched (no TMDB id)", "\(unmatched)")
        let sourceCounts = Dictionary(grouping: library.items, by: { $0.sourceType.displayName })
            .mapValues { $0.count }
        for (name, count) in sourceCounts.sorted(by: { $0.key < $1.key }) {
            kv("  by source \(name)", "\(count)")
        }

        return lines.joined(separator: "\n")
    }
}
