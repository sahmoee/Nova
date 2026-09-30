//
//  NovaSleepTimer.swift
//  Nova
//
//  Sleep timer that auto-pauses playback after a chosen number of minutes.
//  Wire to the player: inject NovaSleepTimerManager.shared and call
//  begin(minutes:onExpire:) passing a closure that pauses your AVPlayer/VLC.
//

import SwiftUI
import Combine

// MARK: - Manager

@MainActor
final class NovaSleepTimerManager: ObservableObject {
    static let shared = NovaSleepTimerManager()

    @Published private(set) var isActive = false
    @Published private(set) var remainingSeconds: Int = 0
    /// The preset last chosen, so the sheet can mark it while the timer runs.
    @Published private(set) var selectedMinutes: Int?

    private var task: Task<Void, Never>?
    private var onExpire: (() -> Void)?
    /// Wall-clock deadline. A 1-second counting loop drifted and stalled while the app
    /// was suspended, so the remaining time is always derived from this deadline.
    private var deadline: Date?

    private init() {}

    /// Starts (or restarts) the timer. Without an explicit handler, expiry pauses
    /// whichever Nova player is active, so the timer also works when started from Settings.
    func begin(minutes: Int, onExpire: (() -> Void)? = nil) {
        cancel()
        guard minutes > 0 else { return }
        self.onExpire = onExpire
        selectedMinutes = minutes
        deadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
        isActive = true
        refreshRemaining()
        startTicking()
    }

    /// Adds time to a running timer without resetting it.
    func extend(minutes: Int) {
        guard isActive, minutes > 0, let deadline else { return }
        self.deadline = deadline.addingTimeInterval(TimeInterval(minutes * 60))
        selectedMinutes = nil
        refreshRemaining()
    }

    func cancel() {
        task?.cancel()
        task = nil
        isActive = false
        remainingSeconds = 0
        selectedMinutes = nil
        deadline = nil
        onExpire = nil
    }

    private func startTicking() {
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.refreshRemaining()
                if self.remainingSeconds <= 0 {
                    self.expire()
                    return
                }
            }
        }
    }

    private func refreshRemaining() {
        guard let deadline else { remainingSeconds = 0; return }
        remainingSeconds = max(0, Int(deadline.timeIntervalSinceNow.rounded(.up)))
    }

    private func expire() {
        let handler = onExpire
        task = nil
        isActive = false
        remainingSeconds = 0
        selectedMinutes = nil
        deadline = nil
        onExpire = nil
        if let handler { handler() } else { PlaybackCoordinator.shared.pauseActive() }
    }

    var displayString: String {
        let h = remainingSeconds / 3600
        let m = (remainingSeconds % 3600) / 60
        let s = remainingSeconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - View

struct NovaSleepTimerSheet: View {
    @ObservedObject private var manager = NovaSleepTimerManager.shared
    @Environment(\.dismiss) private var dismiss

    /// Inject a closure that pauses the active player.
    var onPause: (() -> Void)?

    private let presets: [(label: String, minutes: Int)] = [
        ("5 min", 5), ("10 min", 10), ("15 min", 15),
        ("20 min", 20), ("30 min", 30), ("45 min", 45),
        ("1 hr", 60), ("1.5 hr", 90)
    ]

    var body: some View {
        NavigationStack {
            List {
                if manager.isActive {
                    Section {
                        HStack {
                            Image(systemName: "timer")
                                .foregroundStyle(.orange)
                                .font(.headline)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pausing in")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(manager.displayString)
                                    .font(.title2.monospacedDigit().weight(.semibold))
                            }
                            Spacer()
                            Button("Cancel", role: .destructive) {
                                manager.cancel()
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                        Button {
                            manager.extend(minutes: 10)
                        } label: {
                            Label("Add 10 minutes", systemImage: "plus.circle")
                        }
                    } header: {
                        Text("Active Timer")
                    } footer: {
                        Text("When the timer ends, Nova pauses whatever is playing and saves your place.")
                    }
                }

                Section {
                    ForEach(presets, id: \.minutes) { preset in
                        Button {
                            manager.begin(minutes: preset.minutes, onExpire: onPause)
                            #if os(iOS)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            #endif
                            dismiss()
                        } label: {
                            HStack {
                                Text(preset.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if manager.isActive, manager.selectedMinutes == preset.minutes {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                } header: {
                    Text(manager.isActive ? "Change Timer" : "Set Timer")
                }
            }
            .navigationTitle("Sleep Timer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Compact indicator (embed in player controls)

struct NovaSleepTimerIndicator: View {
    @ObservedObject private var manager = NovaSleepTimerManager.shared
    @State private var showSheet = false
    var onPause: (() -> Void)?

    var body: some View {
        Button {
            showSheet = true
        } label: {
            Label {
                Text(manager.isActive ? manager.displayString : "Sleep Timer")
                    .monospacedDigit()
            } icon: {
                Image(systemName: "timer")
            }
            .foregroundStyle(manager.isActive ? .orange : .secondary)
            .font(.subheadline)
        }
        .sheet(isPresented: $showSheet) {
            NovaSleepTimerSheet(onPause: onPause)
        }
    }
}
