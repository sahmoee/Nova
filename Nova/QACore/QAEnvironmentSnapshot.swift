// QAEnvironmentSnapshot.swift
// ─────────────────────────────────────────────────────────────────────────────
// Shared QACore — verbatim from Stocked Build 74 (IMPROVEMENT 4).
//
// Captures the settings that decide whether a layout bug reproduces:
// text size, appearance, orientation, screen geometry, accessibility switches,
// battery, locale, uptime — all stable for the length of a session.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import UIKit

@MainActor
enum QAEnvironmentSnapshot {

    static func lines() -> [String] {
        var out: [String] = []
        out.append("text size: \(contentSizeLabel)")
        out.append("appearance: \(appearanceLabel) · \(orientationLabel)")
        out.append("screen: \(screenLabel)")
        let a11y = accessibilityFlags
        out.append("accessibility: " + (a11y.isEmpty ? "nothing on" : a11y.joined(separator: ", ")))
        out.append("battery: \(batteryLabel)")
        out.append("locale: \(localeLabel)")
        out.append("uptime: \(uptimeLabel)")
        if let scene = QAScreenshot.appWindow()?.windowScene {
            out.append("scene: \(sceneLabel(scene))")
        }
        return out
    }

    static func summaryLine() -> String {
        "\(contentSizeLabel) · \(appearanceLabel) · \(orientationLabel) · " +
        (accessibilityFlags.isEmpty ? "no a11y overrides" : accessibilityFlags.joined(separator: ", "))
    }

    // MARK: Pieces

    static var contentSizeLabel: String {
        switch UIApplication.shared.preferredContentSizeCategory {
        case .extraSmall:                        return "XS"
        case .small:                             return "S"
        case .medium:                            return "M"
        case .large:                             return "L (default)"
        case .extraLarge:                        return "XL"
        case .extraExtraLarge:                   return "XXL"
        case .extraExtraExtraLarge:              return "XXXL"
        case .accessibilityMedium:               return "AX M"
        case .accessibilityLarge:                return "AX L"
        case .accessibilityExtraLarge:           return "AX XL"
        case .accessibilityExtraExtraLarge:      return "AX XXL"
        case .accessibilityExtraExtraExtraLarge: return "AX XXXL"
        default:                                 return "unknown"
        }
    }

    static var isAccessibilityTextSize: Bool {
        UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory
    }

    static var appearanceLabel: String {
        switch UITraitCollection.current.userInterfaceStyle {
        case .dark:  return "dark"
        case .light: return "light"
        default:     return "unspecified"
        }
    }

    static var orientationLabel: String {
        guard let scene = QAScreenshot.appWindow()?.windowScene else { return "orientation unknown" }
        let o: UIInterfaceOrientation
        if #available(iOS 26.0, *) {
            o = scene.effectiveGeometry.interfaceOrientation
        } else {
            o = scene.interfaceOrientation
        }
        switch o {
        case .portrait:           return "portrait"
        case .portraitUpsideDown: return "portrait upside down"
        case .landscapeLeft:      return "landscape left"
        case .landscapeRight:     return "landscape right"
        default:                  return "orientation unknown"
        }
    }

    static var screenLabel: String {
        guard let window = QAScreenshot.appWindow() else { return "no window" }
        let b = window.bounds
        let scale = window.traitCollection.displayScale
        let insets = window.safeAreaInsets
        return String(format: "%.0f×%.0f @%.0fx · safe area top %.0f bottom %.0f",
                      b.width, b.height, scale, insets.top, insets.bottom)
    }

    static var accessibilityFlags: [String] {
        var on: [String] = []
        if UIAccessibility.isVoiceOverRunning          { on.append("VoiceOver") }
        if UIAccessibility.isSwitchControlRunning      { on.append("Switch Control") }
        if UIAccessibility.isReduceMotionEnabled       { on.append("Reduce Motion") }
        if UIAccessibility.isReduceTransparencyEnabled { on.append("Reduce Transparency") }
        if UIAccessibility.isBoldTextEnabled           { on.append("Bold Text") }
        if UIAccessibility.isDarkerSystemColorsEnabled { on.append("Increase Contrast") }
        if UIAccessibility.isInvertColorsEnabled       { on.append("Invert Colours") }
        if UIAccessibility.isGrayscaleEnabled          { on.append("Grayscale") }
        if UIAccessibility.isSpeakScreenEnabled        { on.append("Speak Screen") }
        if UIAccessibility.isGuidedAccessEnabled       { on.append("Guided Access") }
        if isAccessibilityTextSize                     { on.append("accessibility text size") }
        return on
    }

    static var batteryLabel: String {
        let device = UIDevice.current
        if !device.isBatteryMonitoringEnabled { device.isBatteryMonitoringEnabled = true }
        let level = device.batteryLevel
        let pct = level < 0 ? "unknown" : "\(Int((level * 100).rounded()))%"
        let state: String
        switch device.batteryState {
        case .charging:  state = "charging"
        case .full:      state = "full"
        case .unplugged: state = "on battery"
        default:         state = "state unknown"
        }
        return "\(pct) · \(state)"
    }

    static var localeLabel: String {
        let l = Locale.current
        let lang   = l.language.languageCode?.identifier ?? "??"
        let region = l.region?.identifier ?? "??"
        let cal    = l.calendar.identifier
        return "\(lang)-\(region) · \(cal) · 24h: \(uses24Hour ? "yes" : "no")"
    }

    private static var uses24Hour: Bool {
        let fmt = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        return !fmt.contains("a")
    }

    static var uptimeLabel: String {
        let seconds = ProcessInfo.processInfo.systemUptime
        let hours = Int(seconds) / 3600
        let mins  = (Int(seconds) % 3600) / 60
        return hours > 0 ? "\(hours)h \(mins)m since boot" : "\(mins)m since boot"
    }

    private static func sceneLabel(_ scene: UIWindowScene) -> String {
        let windows = scene.windows.count
        let state: String
        switch scene.activationState {
        case .foregroundActive:   state = "active"
        case .foregroundInactive: state = "inactive"
        case .background:         state = "background"
        default:                  state = "unattached"
        }
        return "\(state) · \(windows) window\(windows == 1 ? "" : "s")"
    }
}
