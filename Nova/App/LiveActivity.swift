//
//  NovaLiveActivity.swift
//  Nova
//
//  Live Activity + Dynamic Island for the currently playing media item.
//  Shows title, progress, and poster art on the lock screen and Dynamic Island.
//
//  Setup required:
//  1. Add NSSupportsLiveActivities = true to Nova/Info.plist.
//  2. Add the ActivityKit framework (linked automatically via import).
//  3. Call NovaLiveActivityManager.shared.start(item:) when playback begins.
//  4. Call NovaLiveActivityManager.shared.update(progress:isPlaying:) periodically.
//  5. Call NovaLiveActivityManager.shared.end() when playback stops.
//

@preconcurrency import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Activity Attributes

struct NovaPlaybackAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var progressFraction: Double   // 0...1
        var isPlaying: Bool
        var elapsedSeconds: Int
        var totalSeconds: Int

        var elapsedDisplay: String {
            let m = elapsedSeconds / 60
            let s = elapsedSeconds % 60
            return String(format: "%d:%02d", m, s)
        }

        var remainingDisplay: String {
            let remaining = max(0, totalSeconds - elapsedSeconds)
            let m = remaining / 60
            let s = remaining % 60
            return String(format: "-%d:%02d", m, s)
        }
    }

    var mediaTitle: String
    var seriesTitle: String?
    var episodeLabel: String?
    var posterURLString: String?

    var displayTitle: String {
        if let series = seriesTitle, let ep = episodeLabel {
            return "\(series) · \(ep)"
        }
        return mediaTitle
    }
}

// MARK: - Manager

@MainActor
final class NovaLiveActivityManager {
    static let shared = NovaLiveActivityManager()

    private var activity: Activity<NovaPlaybackAttributes>?

    private init() {}

    func start(item: MediaItem, initialProgress: Double = 0, totalSeconds: Int = 0) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()

        let attributes = NovaPlaybackAttributes(
            mediaTitle: item.title,
            seriesTitle: item.seriesTitle,
            episodeLabel: item.episode?.label,
            posterURLString: item.posterURL?.absoluteString
        )
        let state = NovaPlaybackAttributes.ContentState(
            progressFraction: initialProgress,
            isPlaying: true,
            elapsedSeconds: Int(item.lastPlayedPosition),
            totalSeconds: totalSeconds
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: .now.addingTimeInterval(3600)),
                pushType: nil
            )
        } catch {
            // Live Activities are best-effort; silently ignore if unavailable.
        }
    }

    func update(
        progressFraction: Double,
        isPlaying: Bool,
        elapsedSeconds: Int,
        totalSeconds: Int
    ) {
        guard let activity else { return }
        let state = NovaPlaybackAttributes.ContentState(
            progressFraction: max(0, min(1, progressFraction)),
            isPlaying: isPlaying,
            elapsedSeconds: elapsedSeconds,
            totalSeconds: totalSeconds
        )
        Task {
            await activity.update(.init(state: state, staleDate: .now.addingTimeInterval(3600)))
        }
    }

    func end() {
        guard let activity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        self.activity = nil
    }
}

// MARK: - Lock Screen / Notification Widget

struct NovaLiveActivityView: View {
    let context: ActivityViewContext<NovaPlaybackAttributes>

    var body: some View {
        HStack(spacing: 12) {
            // Poster
            AsyncImage(url: URL(string: context.attributes.posterURLString ?? "")) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    Image(systemName: "film")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.2))
                            .frame(height: 3)
                        Capsule()
                            .fill(.orange)
                            .frame(
                                width: geo.size.width * context.state.progressFraction,
                                height: 3
                            )
                    }
                }
                .frame(height: 3)

                HStack {
                    Text(context.state.elapsedDisplay)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(context.state.remainingDisplay)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .foregroundStyle(.white)
        .background(.black)
    }
}

// MARK: - Dynamic Island Compact

struct NovaDynamicIslandCompact: View {
    let context: ActivityViewContext<NovaPlaybackAttributes>

    var body: some View {
        HStack(spacing: 6) {
            leadingView
            trailingView
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(context.attributes.displayTitle), \(context.state.remainingDisplay) remaining")
    }

    var leadingView: some View {
        Image(systemName: context.state.isPlaying ? "play.fill" : "pause.fill")
            .foregroundStyle(.orange)
            .font(.caption2)
    }

    var trailingView: some View {
        Text(context.state.remainingDisplay)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
    }
}
