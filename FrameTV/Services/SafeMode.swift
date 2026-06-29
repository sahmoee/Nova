//
//  SafeMode.swift
//  FrameTV
//
//  A lightweight global accessor for the Safe Mode flag, so services that don't hold
//  a SettingsStore reference (catalog/shelf/stream resolution) can cheaply check it.
//  Backed by the same UserDefaults key SettingsStore writes, so the two stay in sync.
//

import Foundation

enum SafeMode {
    static let key = "settings.safeMode"

    /// Whether Safe Mode is currently on. When on, addons, AI search, and external
    /// sources are skipped so the app stays responsive even with a misbehaving source.
    static var isOn: Bool {
        UserDefaults.standard.bool(forKey: key)
    }
}
