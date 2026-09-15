import SwiftUI

/// Loading sheen stops when Reduce Motion changes or the app leaves the foreground.
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase: CGFloat = -1
    private var animating: Bool { !reduceMotion && scenePhase == .active }

    func body(content: Content) -> some View {
        content
            .overlay {
                if animating {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.08), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.6)
                            .offset(x: phase * geo.size.width * 1.6)
                            .blendMode(.plusLighter)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .task(id: animating) {
                phase = -1
                guard animating else { return }
                // Commit the resting frame before starting the repeat animation.
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 }
            }
            .clipped()
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}
