//
//  NovaSpeedControl.swift
//  Nova
//
//  Playback speed picker for Nova's built-in players.
//  Persists the last-used speed in UserDefaults.
//  Wire to the player: observe NovaSpeedControl.shared.rate and
//  call player.rate = rate (AVPlayer) or vlcMediaPlayer.rate = Float(rate) (VLC).
//
//  In your player view, add:
//      NovaSpeedButton()
//  and observe:
//      @StateObject private var speedControl = NovaSpeedControl.shared
//      .onReceive(speedControl.$rate) { player.rate = Float($0) }
//

import SwiftUI
import Combine

// MARK: - Speed values

enum NovaPlaybackSpeed: Double, CaseIterable, Identifiable {
    case half        = 0.5
    case threeQuarter = 0.75
    case normal      = 1.0
    case oneAndQuarter = 1.25
    case oneAndHalf  = 1.5
    case oneAndThreeQuarter = 1.75
    case double      = 2.0

    var id: Double { rawValue }

    var label: String {
        switch self {
        case .half:               return "0.5×"
        case .threeQuarter:       return "0.75×"
        case .normal:             return "1×"
        case .oneAndQuarter:      return "1.25×"
        case .oneAndHalf:         return "1.5×"
        case .oneAndThreeQuarter: return "1.75×"
        case .double:             return "2×"
        }
    }

    var isNormal: Bool { self == .normal }
}

// MARK: - Manager

@MainActor
final class NovaSpeedControl: ObservableObject {
    static let shared = NovaSpeedControl()

    @Published var speed: NovaPlaybackSpeed = .normal {
        didSet {
            UserDefaults.standard.set(speed.rawValue, forKey: "nova.playbackSpeed")
        }
    }

    /// Convenience Float for VLC / AVPlayer.
    var rate: Float { Float(speed.rawValue) }

    private init() {
        let stored = UserDefaults.standard.double(forKey: "nova.playbackSpeed")
        speed = NovaPlaybackSpeed(rawValue: stored) ?? .normal
    }

    func cycleForward() {
        let all = NovaPlaybackSpeed.allCases
        let idx = all.firstIndex(of: speed) ?? 2
        speed = all[(idx + 1) % all.count]
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Speed button (compact, for player toolbar)

struct NovaSpeedButton: View {
    @StateObject private var control = NovaSpeedControl.shared
    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker = true
        } label: {
            Text(control.speed.label)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(control.speed.isNormal ? Color.secondary : Color.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(control.speed.isNormal ? .clear : Color.orange.opacity(0.15))
                )
        }
        .sheet(isPresented: $showPicker) {
            NovaSpeedPickerSheet()
        }
    }
}

// MARK: - Picker sheet

struct NovaSpeedPickerSheet: View {
    @StateObject private var control = NovaSpeedControl.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(NovaPlaybackSpeed.allCases) { speed in
                Button {
                    control.speed = speed
                    UISelectionFeedbackGenerator().selectionChanged()
                    dismiss()
                } label: {
                    HStack {
                        Text(speed.label)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.primary)
                        Spacer()
                        if speed == control.speed {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.orange)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .navigationTitle("Playback Speed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !control.speed.isNormal {
                        Button("Reset") {
                            control.speed = .normal
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                        .foregroundStyle(.orange)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Inline speed strip (optional larger control inside player)

struct NovaSpeedStrip: View {
    @StateObject private var control = NovaSpeedControl.shared

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NovaPlaybackSpeed.allCases) { speed in
                    Button {
                        control.speed = speed
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(speed.label)
                            .font(.footnote.weight(.medium).monospacedDigit())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(speed == control.speed
                                          ? Color.orange
                                          : Color.white.opacity(0.15))
                            )
                            .foregroundStyle(speed == control.speed ? .black : .white)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}
