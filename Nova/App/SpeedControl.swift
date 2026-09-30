//
//  NovaSpeedControl.swift
//  Nova
//
//  Playback speed controls. Every control edits SettingsStore.playbackSpeed, the value
//  both built-in players apply (PlayerModel.applyPlaybackSpeed / VLCPlayerModel).
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

// MARK: - Legacy migration

/// Earlier builds kept a second speed value (`nova.playbackSpeed`) that the players never
/// read. The players apply `SettingsStore.playbackSpeed`, so every control below edits
/// that value, and a non-default legacy choice is carried over once.
@MainActor
enum NovaSpeedControl {
    private static let legacyKey = "nova.playbackSpeed"

    static func migrateLegacy(into settings: SettingsStore) {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: legacyKey) != nil else { return }
        let legacy = defaults.double(forKey: legacyKey)
        if let speed = NovaPlaybackSpeed(rawValue: legacy), !speed.isNormal, settings.playbackSpeed == 1.0 {
            settings.playbackSpeed = speed.rawValue
        }
        defaults.removeObject(forKey: legacyKey)
    }

    static func label(for speed: Double) -> String {
        NovaPlaybackSpeed(rawValue: speed)?.label ?? String(format: "%g×", speed)
    }
}

// MARK: - Speed button (compact, for player toolbar)

struct NovaSpeedButton: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var showPicker = false

    var body: some View {
        let isNormal = settings.playbackSpeed == 1.0
        Button {
            showPicker = true
        } label: {
            Text(NovaSpeedControl.label(for: settings.playbackSpeed))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(isNormal ? Color.secondary : Theme.Colors.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(isNormal ? .clear : Theme.Colors.accent.opacity(0.15)))
        }
        .accessibilityLabel("Playback speed \(NovaSpeedControl.label(for: settings.playbackSpeed))")
        .sheet(isPresented: $showPicker) {
            NovaSpeedPickerSheet().environmentObject(settings)
        }
    }
}

// MARK: - Picker sheet

struct NovaSpeedPickerSheet: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(NovaPlaybackSpeed.allCases) { speed in
                        Button {
                            settings.playbackSpeed = speed.rawValue
                            #if os(iOS)
                            UISelectionFeedbackGenerator().selectionChanged()
                            #endif
                            dismiss()
                        } label: {
                            HStack {
                                Text(speed.label)
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(.primary)
                                Spacer()
                                if speed.rawValue == settings.playbackSpeed {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.Colors.accent)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .accessibilityAddTraits(speed.rawValue == settings.playbackSpeed ? .isSelected : [])
                    }
                } footer: {
                    Text("The default speed for Nova's built-in players. It is the same setting as Player → Playback Speed.")
                }
            }
            .navigationTitle("Playback Speed")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if settings.playbackSpeed != 1.0 {
                        Button("Reset") {
                            settings.playbackSpeed = 1.0
                            #if os(iOS)
                            UISelectionFeedbackGenerator().selectionChanged()
                            #endif
                        }
                    }
                }
            }
            .onAppear { NovaSpeedControl.migrateLegacy(into: settings) }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Inline speed strip (optional larger control inside player)

struct NovaSpeedStrip: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NovaPlaybackSpeed.allCases) { speed in
                    let selected = speed.rawValue == settings.playbackSpeed
                    Button {
                        settings.playbackSpeed = speed.rawValue
                        #if os(iOS)
                        UISelectionFeedbackGenerator().selectionChanged()
                        #endif
                    } label: {
                        Text(speed.label)
                            .font(.footnote.weight(.medium).monospacedDigit())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(selected ? Theme.Colors.accent : Color.white.opacity(0.15)))
                            .foregroundStyle(selected ? .black : .white)
                    }
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal)
        }
    }
}
