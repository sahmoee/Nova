//
//  ExpandableText.swift
//  Astra
//
//  A description block that shows a few lines by default and expands to the full
//  text when tapped. Movie and show overviews are often several paragraphs, so this
//  keeps the hero compact while making the complete synopsis reachable. The visible
//  text is ALWAYS rendered (never hidden behind a measurement), so a description can
//  never vanish; only the "Read more / Read less" affordance is conditional.
//
//  Works on iOS, iPadOS and tvOS. On iOS/iPadOS the whole block is tappable; on
//  tvOS a focusable button toggles expansion (tvOS has no tap gesture).
//

import SwiftUI

struct ExpandableText: View {
    let text: String
    /// Lines shown while collapsed.
    var collapsedLineLimit: Int = 3
    var font: Font = .appFont(17)
    var color: Color = Theme.Colors.textSecondary
    var alignment: TextAlignment = .center

    @State private var expanded = false
    /// Set true once we detect the text is clipped at the collapsed limit. Starts
    /// false; the visible text renders regardless, so nothing is ever hidden.
    @State private var showsToggle = false

    var body: some View {
        VStack(alignment: railAlignment, spacing: Theme.Spacing.xs) {
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .multilineTextAlignment(alignment)
                .lineSpacing(4)
                .lineLimit(expanded ? nil : collapsedLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
                .background(clipDetector)
                .animation(.easeInOut(duration: 0.2), value: expanded)

            if showsToggle {
                toggleButton
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
        #if !os(tvOS)
        .contentShape(Rectangle())
        .onTapGesture { if showsToggle { withAnimation { expanded.toggle() } } }
        #endif
    }

    @ViewBuilder private var toggleButton: some View {
        #if os(tvOS)
        Button {
            withAnimation { expanded.toggle() }
        } label: {
            Label(expanded ? "Read less" : "Read more",
                  systemImage: expanded ? "chevron.up" : "chevron.down")
                .font(.appFont(15, weight: .semibold))
        }
        .buttonStyle(AstraChipButtonStyle())
        #else
        Button {
            withAnimation { expanded.toggle() }
        } label: {
            Text(expanded ? "Read less" : "Read more")
                .font(.appFont(15, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
        }
        .buttonStyle(.plain)
        #endif
    }

    /// Detects clipping by rendering the SAME text twice off-screen — once
    /// unconstrained and once at the collapsed line limit — and comparing heights.
    /// This overlay only ever influences `showsToggle`; it never affects the visible
    /// text, so the description is always shown even if measurement fails.
    private var clipDetector: some View {
        ZStack {
            Text(text)
                .font(font)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { full in
                    Color.clear.preference(key: FullHeightKey.self, value: full.size.height)
                })
            Text(text)
                .font(font)
                .lineSpacing(4)
                .lineLimit(collapsedLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { clip in
                    Color.clear.preference(key: ClippedHeightKey.self, value: clip.size.height)
                })
        }
        .hidden()
        .onPreferenceChange(FullHeightKey.self) { full in
            fullHeight = full
            updateToggle()
        }
        .onPreferenceChange(ClippedHeightKey.self) { clip in
            clippedHeight = clip
            updateToggle()
        }
    }

    @State private var fullHeight: CGFloat = 0
    @State private var clippedHeight: CGFloat = 0

    private func updateToggle() {
        // Only turn the toggle on; never render-hide the text. 2pt tolerance avoids
        // sub-pixel false positives.
        if fullHeight > 0, clippedHeight > 0, fullHeight - clippedHeight > 2 {
            if !showsToggle { showsToggle = true }
        }
    }

    private var railAlignment: HorizontalAlignment {
        switch alignment {
        case .leading:  return .leading
        case .trailing: return .trailing
        default:        return .center
        }
    }

    private var frameAlignment: Alignment {
        switch alignment {
        case .leading:  return .leading
        case .trailing: return .trailing
        default:        return .center
        }
    }
}

private struct FullHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ClippedHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
