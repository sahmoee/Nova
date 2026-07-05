//
//  BackupContentsPicker.swift
//  Astra
//
//  A sheet that lets the user choose which parts of a snapshot to include when
//  exporting, or which parts to apply when restoring. Secrets (logins, API keys)
//  are clearly marked and off by default, with a short warning, so sharing a
//  complete backup across a trusted household is an explicit, informed choice.
//

import SwiftUI

struct BackupContentsPicker: View {
    enum Mode { case export, restore }

    let mode: Mode
    /// Categories that are actually present/available; others are hidden.
    let available: BackupContents
    /// Called with the chosen categories when the user confirms.
    let onConfirm: (BackupContents) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: BackupContents

    init(mode: Mode,
         available: BackupContents,
         initialSelection: BackupContents? = nil,
         onConfirm: @escaping (BackupContents) -> Void) {
        self.mode = mode
        self.available = available
        self.onConfirm = onConfirm
        // Default: everything available except secrets (opt-in).
        let initial = initialSelection ?? available.subtracting(.secrets)
        _selection = State(initialValue: initial.intersection(available))
    }

    private var title: String { mode == .export ? "What to Include" : "What to Restore" }
    private var actionTitle: String { mode == .export ? "Export" : "Restore" }

    private var items: [BackupContents.Item] {
        BackupContents.catalog.filter { available.contains($0.option) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text(title)
                    .font(Theme.Font.screenTitle())
                    .screenTitleStyle()
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(mode == .export
                     ? "Choose which parts of your setup to put in the file. Logins are only included if you turn them on."
                     : "Choose which parts of this snapshot to apply to this device.")
                    .font(.appFont(18))
                    .foregroundStyle(Theme.Colors.textSecondary)

                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(items) { item in
                        row(item)
                    }
                }

                if selection.contains(.secrets) {
                    Label(mode == .export
                          ? "This file will contain passwords and API keys in readable form. Only share it with people you trust."
                          : "This will overwrite this device's saved passwords and API keys.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.appFont(16, weight: .medium))
                        .foregroundStyle(Theme.Colors.warning)
                        .padding(Theme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Colors.warning.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }

                HStack(spacing: Theme.Spacing.md) {
                    FocusableButton(title: "Cancel", systemImage: "xmark") { dismiss() }
                        .frame(maxWidth: .infinity)
                    FocusableButton(title: actionTitle,
                                    systemImage: mode == .export ? "square.and.arrow.up" : "checkmark",
                                    prominent: true) {
                        onConfirm(selection)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(selection.isEmpty)
                    .opacity(selection.isEmpty ? 0.5 : 1)
                }
                .padding(.top, Theme.Spacing.sm)
            }
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.vertical, Theme.Spacing.xl)
            .frame(maxWidth: Theme.contentMaxWidth(900), alignment: .leading)
        }
        .background(Theme.Colors.appBackground.ignoresSafeArea())
    }

    private func row(_ item: BackupContents.Item) -> some View {
        let isOn = selection.contains(item.option)
        return Button {
            if isOn { selection.remove(item.option) } else { selection.insert(item.option) }
        } label: {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: item.systemImage)
                    .font(.appFont(22))
                    .foregroundStyle(item.sensitive ? Theme.Colors.warning : Theme.Colors.accent)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.appFont(20, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(item.detail)
                        .font(.appFont(15))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Spacing.sm)

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.appFont(24))
                    .foregroundStyle(isOn ? Theme.Colors.accent : Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(FrameListRowStyle())
    }
}
