//
//  LibraryHealthView.swift
//  Astra
//
//  One hub for keeping the library clean: quality scan, duplicate cleanup,
//  title/image enrichment, and regex cleanup rules — previously four separate
//  Settings rows, now segmented tabs on a single screen.
//

import SwiftUI

struct LibraryHealthView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case scan       = "Scan"
        case duplicates = "Duplicates"
        case cleanup    = "Clean Up"
        case rules      = "Rules"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .scan:       return "checkmark.seal"
            case .duplicates: return "arrow.triangle.merge"
            case .cleanup:    return "wand.and.stars"
            case .rules:      return "textformat.abc.dottedunderline"
            }
        }
    }

    @State private var tab: Tab = .scan

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                Picker("Section", selection: $tab) {
                    ForEach(Tab.allCases) { t in
                        Label(t.rawValue, systemImage: t.systemImage).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.vertical, Theme.Spacing.sm)

                switch tab {
                case .scan:       LibraryQualityView()
                case .duplicates: DuplicatesView()
                case .cleanup:    LibraryEnrichView()
                case .rules:      TitleCleanupRulesView()
                }
            }
        }
        .navigationTitle("Library Health")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
