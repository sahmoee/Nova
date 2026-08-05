//
//  PlayFromLinkView.swift
//  Nova
//
//  One entry point for playing from any pasted link. Detects what was pasted —
//  a direct video URL or a magnet link — and routes to the right flow, replacing
//  the separate "Play from URL" and "Play from Magnet" screens in Settings.
//

import SwiftUI

struct PlayFromLinkView: View {
    @EnvironmentObject private var settings: SettingsStore

    private enum LinkKind { case direct, magnet }
    @State private var kind: LinkKind = .direct

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                if !settings.reviewSafeMode {
                    Picker("Type", selection: $kind) {
                        Label("Direct URL", systemImage: "link").tag(LinkKind.direct)
                        Label("Magnet", systemImage: "scope").tag(LinkKind.magnet)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.Spacing.edge)
                    .padding(.vertical, Theme.Spacing.sm)
                }

                switch kind {
                case .direct: DirectURLView()
                case .magnet: MagnetView()
                }
            }
        }
        .navigationTitle("Play from Link")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
