//
//  AccentManager.swift
//  FrameTV
//
//  Apple TV style: the UI accent is drawn from the artwork the user is looking at.
//  When a detail screen or the player shows a poster, we extract a vivid dominant
//  color from it and publish it as the current accent. Views read `AccentManager`
//  for highlights, focus rings, and gradients so the whole app subtly takes on the
//  color of the content. Falls back to the brand violet when nothing is showing.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AccentManager: ObservableObject {
    static let shared = AccentManager()

    /// The brand fallback accent (matches Theme.Colors.accent). Nonisolated so it can
    /// be used as an EnvironmentKey default value (which runs outside the main actor).
    nonisolated static let fallback = Color(red: 0.49, green: 0.40, blue: 0.95)

    /// The current accent color, animated when it changes.
    @Published private(set) var accent: Color = AccentManager.fallback

    private var cache: [String: Color] = [:]
    private init() {}

    /// Derives an accent from a poster URL (using the already-cached, downsampled
    /// image) and publishes it. No-ops gracefully if the image isn't available.
    func deriveAccent(from url: URL?) {
        guard let url else { reset(); return }
        let key = url.absoluteString
        if let cached = cache[key] {
            set(cached)
            return
        }
        Task {
            // Reuse the small cached/downsampled image; cheap to analyze.
            guard let image = await ImageLoader.shared.image(for: url, maxPixel: 120) else { return }
            let color = AccentManager.dominantColor(from: image) ?? AccentManager.fallback
            cache[key] = color
            set(color)
        }
    }

    /// Resets to the brand accent (e.g. when leaving a detail screen).
    func reset() { set(AccentManager.fallback) }

    private func set(_ color: Color) {
        withAnimation(.easeInOut(duration: 0.6)) { accent = color }
    }

    // MARK: - Color extraction

    /// Extracts a vivid, sufficiently-saturated dominant color from an image by
    /// sampling a downscaled bitmap and bucketing hues. Avoids muddy greys/blacks.
    nonisolated static func dominantColor(from image: PlatformImage) -> Color? {
        #if canImport(UIKit)
        guard let cg = image.cgImage else { return nil }

        let width = 32, height = 32
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Accumulate the most saturated, reasonably bright pixels.
        var rTot = 0.0, gTot = 0.0, bTot = 0.0, count = 0.0
        for i in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let r = Double(pixels[i]) / 255.0
            let g = Double(pixels[i + 1]) / 255.0
            let b = Double(pixels[i + 2]) / 255.0
            let maxC = max(r, g, b), minC = min(r, g, b)
            let brightness = maxC
            let saturation = maxC == 0 ? 0 : (maxC - minC) / maxC
            // Skip near-black, near-white, and washed-out pixels so the accent pops.
            if brightness < 0.18 || saturation < 0.28 { continue }
            // Weight by saturation so vivid pixels dominate the average.
            let w = saturation
            rTot += r * w; gTot += g * w; bTot += b * w; count += w
        }
        guard count > 0 else { return nil }

        var r = rTot / count, g = gTot / count, b = bTot / count
        // Normalize toward a vivid, UI-friendly accent: lift saturation/brightness.
        (r, g, b) = AccentManager.vivify(r, g, b)
        return Color(red: r, green: g, blue: b)
        #else
        return nil
        #endif
    }

    /// Pushes a color toward a punchy, legible accent: ensures enough saturation and
    /// a brightness that reads on a dark background.
    nonisolated private static func vivify(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        #if canImport(UIKit)
        UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &br, alpha: &a)
        s = max(s, 0.55)            // ensure it's colorful
        br = min(max(br, 0.62), 0.92) // bright enough to show on near-black, not blinding
        let c = UIColor(hue: h, saturation: s, brightness: br, alpha: 1)
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        c.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
        return (Double(rr), Double(gg), Double(bb))
        #else
        return (r, g, b)
        #endif
    }
}
