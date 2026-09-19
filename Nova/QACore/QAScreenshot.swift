// QAScreenshot.swift
// ─────────────────────────────────────────────────────────────────────────────
// Shared QACore — screenshot capture and window access helpers.
// ─────────────────────────────────────────────────────────────────────────────

import UIKit
import SwiftUI

@MainActor
enum QAScreenshot {

    /// The app's primary UIWindow — not a QA overlay window.
    /// QA overlay windows sit at `.alert + 0.5`, so anything at or below
    /// `.alert` is the app's real content.
    static func appWindow() -> UIWindow? {
        UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { $0.windowLevel <= .alert }
            .last(where: \.isKeyWindow)
            ?? UIApplication.shared
                .connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .filter { $0.windowLevel <= .alert && !$0.isHidden }
                .last
    }

    /// Capture the current screen, excluding QA overlay windows.
    /// Returns nil if capture is unavailable (background, no scene, etc.).
    static func capture() async -> UIImage? {
        guard let window = appWindow() else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { ctx in
            window.layer.render(in: ctx.cgContext)
        }
        return image
    }

    /// Write a screenshot to the QA screenshots directory.
    /// Returns the filename (not full path) on success.
    static func save(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.82) else { return nil }
        let dir = screenshotsDirectory()
        let filename = "\(UUID().uuidString).jpg"
        let url = dir.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    static func screenshotsDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("QAScreenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func image(named filename: String) -> UIImage? {
        let url = screenshotsDirectory().appendingPathComponent(filename)
        return UIImage(contentsOfFile: url.path)
    }

    static func delete(named filename: String) {
        let url = screenshotsDirectory().appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Mockups directory

    static func mockupsDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("QAMockups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func mockup(named filename: String) -> UIImage? {
        let url = mockupsDirectory().appendingPathComponent(filename)
        return UIImage(contentsOfFile: url.path)
    }
}
