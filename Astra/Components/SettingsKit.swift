//
//  SettingsKit.swift
//  Astra
//
//  Reusable building blocks for the redesigned, iOS-Settings-style settings screens:
//  colored icon tiles, grouped rounded cards with hairline dividers, and consistent
//  navigation / toggle / picker rows. Shared by the settings directory and every
//  category screen so the look stays identical across iOS, iPadOS, and tvOS.
//

import SwiftUI

// MARK: - Metrics

/// Platform-tuned sizing. iPhone/iPad use standard iOS Settings proportions; tvOS
/// scales everything up for the 10-foot living-room layout.
enum SettingsMetrics {
    #if os(tvOS)
    static let title: CGFloat = 31
    static let detail: CGFloat = 27
    static let header: CGFloat = 22
    static let symbol: CGFloat = 26
    static let tile: CGFloat = 54
    static let tileRadius: CGFloat = 13
    static let chevron: CGFloat = 22
    static let rowVPad: CGFloat = 16
    static let rowSpacing: CGFloat = 18
    static let groupRadius: CGFloat = 22
    static let dividerInset: CGFloat = 86
    #else
    static let title: CGFloat = 17
    static let detail: CGFloat = 16
    static let header: CGFloat = 13
    static let symbol: CGFloat = 15
    static let tile: CGFloat = 30
    static let tileRadius: CGFloat = 7
    static let chevron: CGFloat = 14
    static let rowVPad: CGFloat = 11
    static let rowSpacing: CGFloat = 12
    static let groupRadius: CGFloat = 16
    static let dividerInset: CGFloat = 58
    #endif
}

enum SettingsStyle {
    /// The elevated gray each grouped card sits on (iOS Settings cell color over black).
    static let groupBackground = Color(white: 0.11)
    static let divider = Color.white.opacity(0.08)
}

// MARK: - Icon tile

/// A colored rounded-square with a white SF Symbol, matching iOS Settings row icons.
struct SettingsIconTile: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.appFont(SettingsMetrics.symbol, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: SettingsMetrics.tile, height: SettingsMetrics.tile)
            .background(color, in: RoundedRectangle(cornerRadius: SettingsMetrics.tileRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Grouped card

/// A rounded, elevated card that renders its rows with inset hairline dividers, like
/// an iOS Settings group. Rows are passed as an array so dividers can be placed
/// between them automatically (and omitted after the last row).
struct SettingsGroup: View {
    var header: String? = nil
    var footer: String? = nil
    let rows: [AnyView]

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing * 0.6) {
            if let header, !header.isEmpty {
                Text(header.uppercased())
                    .font(.appFont(SettingsMetrics.header, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.leading, SettingsMetrics.rowSpacing + 4)
            }
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { i in
                    rows[i]
                    if i != rows.indices.last {
                        Rectangle()
                            .fill(SettingsStyle.divider)
                            .frame(height: 0.5)
                            .padding(.leading, SettingsMetrics.dividerInset)
                    }
                }
            }
            .background(SettingsStyle.groupBackground)
            .clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.groupRadius, style: .continuous))
            if let footer, !footer.isEmpty {
                Text(footer)
                    .font(.appFont(SettingsMetrics.header))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.horizontal, SettingsMetrics.rowSpacing + 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Rows

/// A tappable row: icon tile + title, an optional right-aligned value / status dot,
/// and (by default) a trailing chevron. Wrap in a `NavigationLink` or `Button`.
struct SettingsRow: View {
    let icon: String
    let color: Color
    let title: String
    var detail: String? = nil
    var status: Color? = nil
    var showsChevron: Bool = true
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: SettingsMetrics.rowSpacing) {
            SettingsIconTile(systemImage: icon, color: color)
            Text(title)
                .font(.appFont(SettingsMetrics.title))
                .foregroundStyle(tint ?? Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            if let status {
                Circle().fill(status)
                    .frame(width: SettingsMetrics.header * 0.7, height: SettingsMetrics.header * 0.7)
                    .accessibilityHidden(true)
            }
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.appFont(SettingsMetrics.detail))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.appFont(SettingsMetrics.chevron, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, SettingsMetrics.rowSpacing + 2)
        .padding(.vertical, SettingsMetrics.rowVPad)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        [title, detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// An in-place toggle row (icon tile + title + switch), styled to sit inside a group.
struct SettingsToggleRow: View {
    let icon: String
    let color: Color
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: SettingsMetrics.rowSpacing) {
            SettingsIconTile(systemImage: icon, color: color)
            Toggle(isOn: $isOn) {
                Text(title)
                    .font(.appFont(SettingsMetrics.title))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .tint(Theme.Colors.accent)
        }
        .padding(.horizontal, SettingsMetrics.rowSpacing + 2)
        .padding(.vertical, SettingsMetrics.rowVPad * 0.7)
        .accessibilityElement(children: .combine)
    }
}

/// An in-place menu-picker row (icon tile + title + trailing menu picker).
struct SettingsPickerRow<T: Hashable>: View {
    let icon: String
    let color: Color
    let title: String
    @Binding var selection: T
    let options: [T]
    let label: (T) -> String

    var body: some View {
        HStack(spacing: SettingsMetrics.rowSpacing) {
            SettingsIconTile(systemImage: icon, color: color)
            Text(title)
                .font(.appFont(SettingsMetrics.title))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { opt in
                    Text(label(opt)).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, SettingsMetrics.rowSpacing + 2)
        .padding(.vertical, SettingsMetrics.rowVPad * 0.5)
    }
}

/// Free-form explanatory text shown beneath a group (like an iOS footer), but placed
/// as a row so it can live inside a group when helpful.
struct SettingsNote: View {
    let text: String
    var tint: Color? = nil
    init(_ text: String, tint: Color? = nil) { self.text = text; self.tint = tint }

    var body: some View {
        Text(text)
            .font(.appFont(SettingsMetrics.detail))
            .foregroundStyle(tint ?? Theme.Colors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, SettingsMetrics.rowSpacing + 2)
            .padding(.vertical, SettingsMetrics.rowVPad * 0.6)
    }
}

// MARK: - Screen scaffold

/// The scaffold for a pushed category screen on iOS/iPadOS: a scrolling column of
/// groups over the app background, with a large navigation title.
struct SettingsScreen<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing + 6) {
                content
            }
            .padding(.horizontal, Theme.isCompact ? Theme.Spacing.sm : Theme.Spacing.edge)
            .padding(.vertical, Theme.Spacing.lg)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.Colors.appBackground.ignoresSafeArea())
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
}
