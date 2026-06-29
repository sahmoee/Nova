//
//  GeneratedPoster.swift
//  FrameTV
//
//  A deterministic placeholder poster for items without artwork (e.g. when the TMDB
//  key is missing or a lookup fails). Shows the title's initials over a gradient
//  seeded from the title, plus an optional year, so the library still looks intentional
//  instead of showing a row of generic film icons.
//

import SwiftUI

struct GeneratedPoster: View {
    let title: String
    var year: Int? = nil

    var body: some View {
        ZStack {
            LinearGradient(colors: gradientColors,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 8) {
                Text(initials)
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                if let year {
                    Text(String(year))
                        .font(.appFont(16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding()
            .minimumScaleFactor(0.5)
            .multilineTextAlignment(.center)
        }
    }

    /// Up to two initials from the title's words.
    private var initials: String {
        let words = title
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        let letters = words.prefix(2).compactMap { $0.first }
        let result = String(letters).uppercased()
        return result.isEmpty ? "?" : result
    }

    /// A stable two-color gradient seeded from the title, so the same title always
    /// gets the same colors.
    private var gradientColors: [Color] {
        let hash = abs(title.hashValue)
        let hue = Double(hash % 360) / 360.0
        let base = Color(hue: hue, saturation: 0.55, brightness: 0.45)
        let accent = Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1.0),
                           saturation: 0.6, brightness: 0.30)
        return [base, accent]
    }
}
