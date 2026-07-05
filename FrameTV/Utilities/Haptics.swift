//
//  Haptics.swift
//  FrameTV
//
//  Small wrapper around haptic feedback so call sites stay tidy and platform-guarded.
//  No-ops on tvOS and macOS where the generators are unavailable.
//

import Foundation
#if os(iOS)
import UIKit
#endif

enum Haptics {
    enum Impact { case light, medium, rigid, soft }

    static func impact(_ style: Impact = .light) {
        #if os(iOS)
        let mapped: UIImpactFeedbackGenerator.FeedbackStyle
        switch style {
        case .light: mapped = .light
        case .medium: mapped = .medium
        case .rigid: mapped = .rigid
        case .soft: mapped = .soft
        }
        UIImpactFeedbackGenerator(style: mapped).impactOccurred()
        #endif
    }

    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func warning() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    static func error() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }

    static func selection() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}
