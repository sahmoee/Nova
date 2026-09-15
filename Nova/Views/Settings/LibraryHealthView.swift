//
//  LibraryHealthView.swift
//  Nova
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
        case tidy       = "Tidy Up"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .scan:       return "checkmark.seal"
            case .duplicates: return "arrow.triangle.merge"
            case .cleanup:    return "wand.and.stars"
            case .rules:      return "textformat.abc.dottedunderline"
            case .tidy:       return "checklist"
            }
        }
    }

    @State private var tab: Tab = .scan

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(Tab.allCases) { item in
                            Button { tab = item } label: {
                                Label(item.rawValue, systemImage: tab == item ? "checkmark.circle.fill" : item.systemImage)
                                    .font(.appFont(16, weight: .semibold))
                            }
                            .buttonStyle(NovaChipButtonStyle(selected: tab == item, providesSurface: true))
                            .accessibilityAddTraits(tab == item ? .isSelected : [])
                            .accessibilityHint("Show \(item.rawValue.lowercased()) tools")
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.edge)
                    .padding(.vertical, Theme.Spacing.sm)
                }
                .scrollClipDisabled()

                switch tab {
                case .scan:       LibraryQualityView()
                case .duplicates: DuplicatesView()
                case .cleanup:    LibraryEnrichView()
                case .rules:      TitleCleanupRulesView()
                case .tidy:       LibraryCleanupView()
                }
            }
        }
        .navigationTitle("Library Health")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
