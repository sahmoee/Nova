//
//  PlaybackDiagnostics.swift
//  Nova
//
//  A compact diagnostics overlay for the player, useful for debugging VLC vs.
//  AVPlayer behavior. Shows the active engine, source type, container/format, host,
//  position/duration, and buffering state — all from data the app reliably has,
//  without risky low-level player introspection.
//

import SwiftUI

struct PlaybackDiagnostics: View {
    let item: MediaItem
    let engine: PlaybackEngine
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isBuffering: Bool
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Label("Diagnostics", systemImage: "waveform.path.ecg")
                    .font(.appFont(20, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.7))
                        .font(.appFont(22))
                }
                .buttonStyle(.plain)
            }

            row("Engine", engine == .vlc ? "VLCKit" : "AVPlayer")
            row("Source", item.sourceType.displayName)
            row("Format", container)
            if let host = item.playbackURL.host { row("Host", host) }
            row("Position", "\(timeLabel(currentTime)) / \(timeLabel(duration))")
            row("Buffering", isBuffering ? "Yes" : "No")
            if duration > 0 {
                row("Progress", "\(Int((currentTime / duration) * 100))%")
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: 460, alignment: .leading)
        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.appFont(15, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.appFont(15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// The container/format inferred from the playback URL extension.
    private var container: String {
        let ext = item.playbackURL.pathExtension.uppercased()
        if ext.isEmpty {
            // Debrid/addon links often have no extension; check the SMB bridge path.
            if item.playbackURL.host == "127.0.0.1" {
                let last = (item.playbackURL.lastPathComponent as NSString).pathExtension.uppercased()
                return last.isEmpty ? "Unknown" : last
            }
            return "Unknown"
        }
        return ext
    }

    private func timeLabel(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "--:--" }
        let total = Int(t)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
}
