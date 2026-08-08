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

    var body: some View {
        GeometryReader { geo in
            heroContent(width: geo.size.width)
        }
        // A tall, cinematic height that scales with the platform so the artwork fills
        // the top of the screen instead of leaving blank space beneath it.
        .frame(height: heroHeight)
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

            // Scrims + accent wash.
            LinearGradient(
                colors: [.clear, Theme.Colors.background.opacity(0.55), Theme.Colors.background],
                startPoint: .top, endPoint: .bottom
            )
            LinearGradient(
                colors: [Theme.Colors.background.opacity(0.85), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            LinearGradient(
                colors: [accent.opacity(0.32), .clear],
                startPoint: .bottomLeading, endPoint: .topTrailing
            )
            .blendMode(.plusLighter)

            // Foreground content.
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if let badge {
                    Text(badge.uppercased())
                        .font(.appFont(13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(accent.opacity(0.85), in: Capsule())
                        .shadow(color: .black.opacity(0.4), radius: 4)
                }
                Text(item.displayTitle)
                    .font(.appFont(44, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)

                if !item.subtitleLine.isEmpty {
                    Text(item.subtitleLine)
                        .font(.appFont(18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                ViewThatFits(in: .horizontal) {
                    heroActions
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) { heroActions }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.bottom, Theme.Spacing.md)
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

    private var heroActions: some View {
        HStack(spacing: Theme.Spacing.sm) {
            playButton
            if let onMoreInfo {
                Button { onMoreInfo(item) } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "info.circle")
                                Text("More Info").fontWeight(.semibold)
                            }
                            .font(.appFont(18))
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs)
                }
                .buttonStyle(HeroInfoButtonStyle())
                .accessibilityLabel("More info about \(item.title)")
            }
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
                .background(active ? accent : .white, in: Capsule())
                .foregroundStyle(active ? .white : .black)
                .scaleEffect(active && !Theme.isReduceMotion ? 1.06 : 1.0)
                .shadow(color: active ? accent.opacity(0.5) : .clear,
                        radius: active ? 20 : 0, y: 6)
                .animation(Theme.isReduceMotion ? nil : .easeOut(duration: 0.18), value: active)
        }
    }
}
