//
//  Shimmer.swift
//  Astra
//
//  A subtle shimmer effect for skeleton/loading placeholders so grids fade in
//  gracefully instead of showing blank boxes or spinners.
//

import SwiftUI

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    let width = geo.size.width
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: width * 0.6)
                    .offset(x: phase * width * 1.6)
                    .blendMode(.plusLighter)
                }
                .allowsHitTesting(false)
            )
            .onAppear {
                guard !Theme.isReduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
            .clipped()
    }
}

extension View {
    /// Applies an animated shimmer, used on skeleton placeholders.
    func shimmering() -> some View { modifier(Shimmer()) }
}
