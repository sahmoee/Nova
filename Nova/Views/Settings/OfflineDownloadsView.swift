//
//  OfflineDownloadsView.swift
//  Nova
//

import SwiftUI

struct OfflineDownloadsView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        OfflineDownloadsContent(manager: env.downloads)
    }
}

private struct OfflineDownloadsContent: View {
    @ObservedObject var manager: DownloadManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ScreenHeader(
                    title: "Offline Downloads",
                    subtitle: ByteCountFormatter.string(fromByteCount: manager.storageBytes,
                                                        countStyle: .file)
                ) {
                    if manager.downloads.contains(where: { $0.state == .complete }) {
                        Button("Clean Up") { manager.cleanupCompleted() }
                            .font(.appFont(16, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }

                if manager.downloads.isEmpty {
                    EmptyStateView(systemImage: "arrow.down.circle",
                                   title: "Nothing downloaded",
                                   message: "Use Download on an authorized direct or local media item to keep it offline.")
                        .frame(minHeight: 320)
                } else {
                    ForEach(manager.downloads) { download in
                        row(download)
                    }
                }
            }
            .padding(Theme.Spacing.edge)
            .frame(maxWidth: Theme.contentMaxWidth(1000), alignment: .leading)
        }
        .background(Theme.Colors.appBackground.ignoresSafeArea())
    }

    private func row(_ download: OfflineDownload) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon(download.state))
                .font(.appFont(26))
                .foregroundStyle(color(download.state))
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 6) {
                Text(download.title)
                    .font(.appFont(19, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                if download.state == .downloading || download.state == .queued || download.state == .paused {
                    ProgressView(value: download.progress)
                        .tint(Theme.Colors.accent)
                }
                Text(detail(download))
                    .font(.appFont(14))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(2)
            }
            Spacer()
            if download.state == .downloading {
                Button("Pause") { manager.pause(download.id) }
            } else if download.state == .paused {
                Button("Resume") { manager.resume(download.id) }
            } else if download.state == .failed {
                Button("Retry") { manager.retry(download.id) }
            }
            Button(role: .destructive) { manager.remove(download.id) } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Remove \(download.title)")
        }
        .buttonStyle(.plain)
        .softCard()
    }

    private func detail(_ download: OfflineDownload) -> String {
        if let error = download.errorMessage { return error }
        let received = ByteCountFormatter.string(fromByteCount: download.receivedBytes, countStyle: .file)
        if let expected = download.expectedBytes {
            return "\(download.state.rawValue.capitalized) · \(received) of \(ByteCountFormatter.string(fromByteCount: expected, countStyle: .file))"
        }
        return "\(download.state.rawValue.capitalized) · \(received)"
    }

    private func icon(_ state: OfflineDownload.State) -> String {
        switch state {
        case .queued, .downloading: return "arrow.down.circle.fill"
        case .paused: return "pause.circle.fill"
        case .complete: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func color(_ state: OfflineDownload.State) -> Color {
        switch state {
        case .queued, .downloading: return Theme.Colors.accent
        case .paused: return Theme.Colors.warning
        case .complete: return Theme.Colors.success
        case .failed: return Theme.Colors.error
        }
    }
}
