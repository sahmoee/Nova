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

    private var task: Task<Void, Never>?
    private var onExpire: (() -> Void)?

    private init() {}

    func begin(minutes: Int, onExpire: @escaping () -> Void) {
        cancel()
        guard minutes > 0 else { return }
        self.onExpire = onExpire
        remainingSeconds = minutes * 60
        isActive = true
        task = Task { [weak self] in
            while let self, self.remainingSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await MainActor.run { self.remainingSeconds -= 1 }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.expire()
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isActive = false
        remainingSeconds = 0
        onExpire = nil
    }

    private func expire() {
        isActive = false
        let handler = onExpire
        onExpire = nil
        handler?()
    }

    var displayString: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - View

struct NovaSleepTimerSheet: View {
    @StateObject private var manager = NovaSleepTimerManager.shared
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
                    } header: {
                        Text("Active Timer")
                    }
                }

                Section {
                    ForEach(presets, id: \.minutes) { preset in
                        Button {
                            manager.begin(minutes: preset.minutes) {
                                onPause?()
                            }
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            dismiss()
                        } label: {
                            HStack {
                                Text(preset.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if manager.isActive,
                                   manager.remainingSeconds == preset.minutes * 60 {
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
            .navigationBarTitleDisplayMode(.inline)
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
    @StateObject private var manager = NovaSleepTimerManager.shared
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
