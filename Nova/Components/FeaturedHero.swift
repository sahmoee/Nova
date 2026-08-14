//
//  FeaturedHero.swift
//  Nova
//
//  An Apple TV-style featured banner for the top of the Home screen. It spotlights a
//  single item with a large backdrop, a gradient scrim, the title and a short line of
//  metadata, and a Play button. While shown, it tints the app accent with the item's
//  artwork color so the whole dashboard takes on its mood.
//

import SwiftUI

struct FeaturedHero: View {
    let item: MediaItem
    /// Optional explicit height override. When nil, the platform default is used.
    var height: CGFloat? = nil
    /// Optional why-am-I-seeing-this chip above the title (e.g. "Continue Watching").
    var badge: String? = nil
    /// When set, a bordered More Info button appears next to Play and opens detail.
    var onMoreInfo: ((MediaItem) -> Void)? = nil
    /// tvOS: pass the Home focus scope so the Play button is the default focus target.
    var playFocusNamespace: Namespace.ID? = nil
    var onPlay: (MediaItem) -> Void

    @Environment(\.dynamicAccent) private var accent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var library: LibraryStore
    @State private var details: CatalogItem?

    var body: some View {
        GeometryReader { geo in
            heroContent(width: geo.size.width)
        }
        // A tall, cinematic height that scales with the platform so the artwork fills
        // the top of the screen instead of leaving blank space beneath it.
        .frame(height: heroHeight)
        .task(id: item.contentKey) {
            details = await env.catalog.hydrate(item.asCatalogItem())
        }
    }

    /// Hero height tuned per platform, unless the caller passed an explicit height.
    /// iPhone/iPad get a tall cinematic banner; tvOS gets the full cinematic height.
    private var heroHeight: CGFloat {
        if let height { return height }
        #if os(tvOS)
        return 560
        #else
        if dynamicTypeSize.isAccessibilitySize { return Theme.isCompact ? 520 : 560 }
        return Theme.isCompact ? 420 : 500
        #endif
    }

    private func heroContent(width: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop (falls back to poster).
            CachedAsyncImage(url: item.backdropURL ?? item.posterURL, maxPixel: 1600) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                // Shimmer while the backdrop loads, matching the app's other skeletons.
                Rectangle().fill(Theme.Colors.card).shimmering()
            }
            .frame(width: width, height: heroHeight)
            .clipped()

            // Scrims + artwork-driven ambient wash. The reference lets the selected
            // artwork color the entire header rather than placing it on a neutral card.
            Theme.Colors.heroGradient
            LinearGradient(
                colors: [Theme.Colors.background.opacity(0.92), Theme.Colors.background.opacity(0.08), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            LinearGradient(
                colors: [accent.opacity(0.58), accent.opacity(0.18), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .blendMode(.plusLighter)

            // Foreground content.
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if let badge {
                    Text(badge.uppercased())
                        .font(.appFont(13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(accent.opacity(0.85), in: Capsule())
                        .shadow(color: .black.opacity(0.4), radius: 4)
                }
                Text(item.displayTitle)
                    .font(.appFont(PlatformCapabilities.platform == .appleTV ? 58 : 44, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)

                if !heroMetadata.isEmpty {
                    Text(heroMetadata)
                        .font(.appFont(18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                #if os(tvOS)
                if let overview = details?.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.appFont(20, weight: .regular))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(3)
                        .frame(maxWidth: min(width * 0.42, 760), alignment: .leading)
                }
                #endif

                ViewThatFits(in: .horizontal) {
                    heroActions
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) { heroActions }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.bottom, PlatformCapabilities.platform == .appleTV ? 72 : Theme.Spacing.md)
            // On tvOS the hero image bleeds into the overscan region; pad the text and
            // Play button by the safe area so they stay fully on-screen and focusable.
            #if os(tvOS)
            .safeAreaPadding(.horizontal)
            .safeAreaPadding(.bottom)
            #endif
        }
        .frame(width: width, height: heroHeight)
        .clipped()
        .onAppear { AccentManager.shared.deriveAccent(from: item.posterURL ?? item.backdropURL) }
    }

    private var heroMetadata: String {
        var values = details?.genres.prefix(3).map { $0 } ?? []
        if values.isEmpty, !item.subtitleLine.isEmpty {
            values = [item.subtitleLine]
        }
        return values.joined(separator: " · ")
    }

    private var heroActions: some View {
        HStack(spacing: Theme.Spacing.sm) {
            playButton
            #if os(tvOS)
            Button {
                if library.isQueued(item) {
                    library.removeFromQueue(item)
                    ToastCenter.shared.show("Removed from Up Next")
                } else {
                    library.add(item)
                    library.addToQueue(item)
                    ToastCenter.shared.show("Added to Up Next")
                }
            } label: {
                Image(systemName: library.isQueued(item) ? "checkmark" : "plus")
                    .font(.appFont(26, weight: .semibold))
                    .frame(width: 58, height: 48)
            }
            .buttonStyle(HeroIconButtonStyle())
            .accessibilityLabel(library.isQueued(item) ? "Remove from Up Next" : "Add to Up Next")
            #endif
            if let onMoreInfo {
                Button { onMoreInfo(item) } label: {
                    #if os(tvOS)
                    Image(systemName: "info.circle")
                        .font(.appFont(26, weight: .semibold))
                        .frame(width: 58, height: 48)
                    #else
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "info.circle")
                                Text("More Info").fontWeight(.semibold)
                            }
                            .font(.appFont(18))
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs)
                    #endif
                }
                #if os(tvOS)
                .buttonStyle(HeroIconButtonStyle())
                #else
                .buttonStyle(HeroInfoButtonStyle())
                #endif
                .accessibilityLabel("More info about \(item.title)")
            }
            #if os(tvOS)
            if let onMoreInfo {
                Button { onMoreInfo(item) } label: {
                    Image(systemName: "chevron.right")
                        .font(.appFont(27, weight: .semibold))
                        .frame(width: 58, height: 48)
                }
                .buttonStyle(HeroIconButtonStyle())
                .accessibilityLabel("Open \(item.title)")
            }
            #endif
        }
    }

    /// The Play/Resume button. On tvOS it registers as the preferred default focus
    /// within the Home focus scope, so the screen opens with Play focused.
    @ViewBuilder
    private var playButton: some View {
        let button = Button { onPlay(item) } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "play.fill")
                Text(item.hasResumePoint ? "Resume" : "Play")
                    .fontWeight(.semibold)
            }
            .font(.appFont(18))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
        }
        .buttonStyle(HeroPlayButtonStyle(accent: accent))
        .accessibilityLabel("\(item.hasResumePoint ? "Resume" : "Play") \(item.title)")
        .accessibilityHint(item.hasResumePoint ? "Continue from the saved position" : "Start playback")

        #if os(tvOS)
        if let ns = playFocusNamespace {
            button.prefersDefaultFocus(true, in: ns)
        } else {
            button
        }
        #else
        button
        #endif
    }
}

private struct HeroIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HeroIconButtonBody(configuration: configuration)
    }

    private struct HeroIconButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .foregroundStyle(isFocused ? Theme.Colors.background : .white)
                .background(isFocused ? Color.white : Color.white.opacity(0.12), in: Circle())
                .scaleEffect(isFocused && !Theme.isReduceMotion ? 1.12 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.45 : 0), radius: 18, y: 8)
                .animation(Theme.isReduceMotion ? nil : .easeOut(duration: 0.16), value: isFocused)
        }
    }
}

/// Bordered secondary style for the hero's More Info button.
private struct HeroInfoButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HeroInfoBody(configuration: configuration)
    }

    private struct HeroInfoBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused

        private var active: Bool {
            #if os(tvOS)
            return isFocused
            #else
            return configuration.isPressed
            #endif
        }

        var body: some View {
            configuration.label
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(active ? 0.9 : 0.35), lineWidth: 1))
                .foregroundStyle(.white)
                .scaleEffect(active && !Theme.isReduceMotion ? 1.06 : 1.0)
                .animation(Theme.isReduceMotion ? nil : .easeOut(duration: 0.18), value: active)
        }
    }
}

/// The hero Play/Resume button style. Implemented as a ButtonStyle reading isFocused
/// so on tvOS it fully replaces the system white focus card with an accent capsule.
private struct HeroPlayButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        HeroPlayBody(configuration: configuration, accent: accent)
    }

    private struct HeroPlayBody: View {
        let configuration: ButtonStyleConfiguration
        let accent: Color
        @Environment(\.isFocused) private var isFocused

        private var active: Bool {
            #if os(tvOS)
            return isFocused
            #else
            return configuration.isPressed
            #endif
        }

        var body: some View {
            configuration.label
                .background(active ? .white : Theme.Colors.accent, in: Capsule())
                .foregroundStyle(Theme.Colors.background)
                .scaleEffect(active && !Theme.isReduceMotion ? 1.06 : 1.0)
                .shadow(color: active ? accent.opacity(0.5) : .clear,
                        radius: active ? 20 : 0, y: 6)
                .animation(Theme.isReduceMotion ? nil : .easeOut(duration: 0.18), value: active)
        }
    }
}
