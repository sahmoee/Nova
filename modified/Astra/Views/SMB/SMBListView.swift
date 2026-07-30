//
//  SMBListView.swift
//  Astra
//
//  Lists saved SMB shares and routes to add/browse. Persists share definitions
//  via a small JSON store; passwords go to the Keychain. Browsing uses the
//  MockSMBProvider in Phase 1/2 and the real provider in Phase 5.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif
import Combine

struct SMBListView: View {
    @StateObject private var model = SMBSharesModel()
    @State private var showingAdd = false
    // Share pending delete confirmation, so a stray tap can't remove it.
    @State private var pendingDelete: SMBShare?

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                ScreenHeader(title: "SMB Shares") {
                    HStack(spacing: Theme.Spacing.sm) {
                        // Per-share diagnostics live on each share row (stethoscope
                        // button), where a specific share is available to test.
                        FocusableButton(title: "Add Share", systemImage: "plus", prominent: true) {
                            showingAdd = true
                        }
                        .frame(maxWidth: Theme.isCompact ? .infinity : 280)
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.top, Theme.Spacing.lg)

                if model.shares.isEmpty {
                    EmptyStateView(
                        systemImage: "externaldrive.badge.plus",
                        title: "No SMB shares yet",
                        message: "Add a network share to browse and play your own video files.",
                        actionTitle: "Add Share",
                        action: { showingAdd = true }
                    )
                } else {
                    ScrollView {
                        VStack(spacing: Theme.Spacing.md) {
                            ForEach(model.shares) { share in
                                shareRow(share)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.edge)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            SMBAddView { newShare, password in
                model.add(newShare, password: password)
                showingAdd = false
                ToastCenter.shared.show("Added \(newShare.displayName)", systemImage: "externaldrive.fill.badge.plus")
            }
        }
        // Destructive confirmation before deleting a saved share (also clears its
        // Keychain password), so a stray tap on the trash icon is recoverable.
        .alert("Delete Share?",
               isPresented: Binding(get: { pendingDelete != nil },
                                    set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { share in
            Button("Delete “\(share.displayName)”", role: .destructive) {
                model.remove(share)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { share in
            Text("“\(share.displayName)” and its saved password will be removed.")
        }
    }

    private func shareRow(_ share: SMBShare) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            // Tapping the main area browses the share. Kept as its own NavigationLink
            // so it doesn't compete with the action buttons on the right.
            NavigationLink {
                SMBBrowseView(share: share)
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .font(.appFont(30))
                        .foregroundStyle(Theme.Colors.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(share.displayName)
                            .font(Theme.Font.cardTitle())
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(share.shareName.isEmpty ? "smb://\(share.host)" : "\(share.host)/\(share.shareName)")
                            .font(.appFont(18))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Diagnostics (stethoscope) and delete — separate buttons, clear tap areas.
            NavigationLink {
                SMBCheckerView(share: share)
            } label: {
                Image(systemName: "stethoscope")
                    .font(.appFont(22))
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(Theme.Spacing.sm)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                // Ask before deleting instead of removing immediately.
                pendingDelete = share
            } label: {
                Image(systemName: "trash")
                    .font(.appFont(22))
                    .foregroundStyle(Theme.Colors.error)
                    .padding(Theme.Spacing.sm)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.md)
        .refinedCardBackground()
    }
}

// MARK: - Add view

struct SMBAddView: View {
    let onSave: (SMBShare, String) -> Void
    @Environment(\.dismiss) private var dismiss

    // Single server field like the Files app, e.g. "smb://yourmac.local" or
    // "smb://yourmac.local/Media". Parsed once on save, never while typing, so
    // characters like "//" aren't eaten by live normalization.
    @State private var server = "smb://"
    @State private var connectAsGuest = false
    @State private var username = ""
    @State private var password = ""
    @State private var displayName = ""

    /// Lets a tap anywhere on a field's card focus the actual text field, instead of
    /// only the small text region being tappable.
    private enum Field: Hashable { case server, username, password, displayName }
    @FocusState private var focusedField: Field?

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Connect to Server")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)

                    // Server field.
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Server").font(.appFont(20, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        TextField("smb://yourcomputer.local", text: $server)
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: .server)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.URL)
                            .textSelection(.enabled)
                            #endif
                            .padding(Theme.Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .contentShape(Rectangle())
                            .onTapGesture { focusedField = .server }
                        Text("Enter your computer's name or IP, e.g. smb://yourcomputer.local. You'll see its shared folders next. You can also go straight to one: smb://yourcomputer.local/Media.")
                            .font(.appFont(15))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }

                    // Connect As (Guest / Registered User), like the Files app.
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Connect As").font(.appFont(20, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        VStack(spacing: 0) {
                            connectAsRow(title: "Guest", selected: connectAsGuest) {
                                connectAsGuest = true
                            }
                            Divider().overlay(Theme.Colors.separator)
                            connectAsRow(title: "Registered User", selected: !connectAsGuest) {
                                connectAsGuest = false
                            }
                        }
                        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    }

                    // Credentials only for Registered User.
                    if !connectAsGuest {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Name").font(.appFont(19))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .frame(width: 110, alignment: .leading)
                                TextField("Name", text: $username)
                                    .textFieldStyle(.plain)
                                    .focused($focusedField, equals: .username)
                                    #if os(iOS)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    #endif
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                            .padding(Theme.Spacing.md)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture { focusedField = .username }
                            Divider().overlay(Theme.Colors.separator)
                            HStack {
                                Text("Password").font(.appFont(19))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .frame(width: 110, alignment: .leading)
                                SecureField("Required", text: $password)
                                    .textFieldStyle(.plain)
                                    .focused($focusedField, equals: .password)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                            .padding(Theme.Spacing.md)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture { focusedField = .password }
                        }
                        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    }

                    // Optional friendly name.
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Display Name (optional)").font(.appFont(20, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        TextField("My Computer", text: $displayName)
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: .displayName)
                            .padding(Theme.Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .contentShape(Rectangle())
                            .onTapGesture { focusedField = .displayName }
                    }

                    FocusableButton(title: "Connect", systemImage: "checkmark", prominent: true) {
                        save()
                    }
                    .frame(maxWidth: Theme.isCompact ? .infinity : 360)
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.5)
                    .padding(.top, Theme.Spacing.sm)
                }
                .padding(Theme.Spacing.edge)
                .frame(maxWidth: Theme.contentMaxWidth(1000), alignment: .leading)
            }
        }
    }

    private func connectAsRow(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.appFont(19))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.appFont(18, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .padding(Theme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Can save when we have a host and, for a registered user, a name + password.
    private var canSave: Bool {
        guard let parsed = SMBURLParser.parse(server), !parsed.host.isEmpty else { return false }
        if connectAsGuest { return true }
        return !username.isEmpty && !password.isEmpty
    }

    /// Parse the single server string into host/share/path once, on save.
    private func save() {
        guard let parsed = SMBURLParser.parse(server), !parsed.host.isEmpty else { return }
        let user = connectAsGuest ? "" : username
        let pass = connectAsGuest ? "" : password
        let name = displayName.isEmpty
            ? (parsed.share ?? parsed.host)
            : displayName
        let share = SMBShare(
            displayName: name,
            host: parsed.host,
            shareName: parsed.share ?? "",
            username: user,
            path: parsed.path
        )
        onSave(share, pass)
    }
}

// MARK: - Shares model + persistence

@MainActor
final class SMBSharesModel: ObservableObject {
    @Published private(set) var shares: [SMBShare] = []

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cancellables = Set<AnyCancellable>()
    private static let cloudKey = "cloud.smbShares"

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("smb_shares.json")
        encoder.outputFormatting = [.prettyPrinted]
        load()
        mergeFromCloud()

        CloudSync.shared.externalChange
            .receive(on: RunLoop.main)
            .sink { [weak self] keys in
                if keys.contains(Self.cloudKey) { self?.mergeFromCloud() }
            }
            .store(in: &cancellables)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        shares = (try? decoder.decode([SMBShare].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? encoder.encode(shares) else { return }
        try? data.write(to: fileURL, options: [.atomic])
        // Share definitions sync via iCloud KVS. Passwords are NOT included here;
        // they sync separately through iCloud Keychain.
        CloudSync.shared.setData(data, forKey: Self.cloudKey)
    }

    private func mergeFromCloud() {
        guard let data = CloudSync.shared.data(forKey: Self.cloudKey),
              let cloudShares = try? decoder.decode([SMBShare].self, from: data) else { return }
        if cloudShares != shares {
            shares = cloudShares
            if let encoded = try? encoder.encode(shares) {
                try? encoded.write(to: fileURL, options: [.atomic])
            }
        }
    }

    func add(_ share: SMBShare, password: String) {
        shares.append(share)
        // Store password securely; never persisted in JSON. Surface a failure so a
        // silent keychain write error doesn't later look like a wrong password.
        if !password.isEmpty {
            do {
                try KeychainStore.shared.set(password, for: share.keychainAccount)
            } catch {
                AstraLog.network.error("Failed to save SMB password to Keychain: \(String(describing: error), privacy: .public)")
            }
        }
        persist()
    }

    func remove(_ share: SMBShare) {
        shares.removeAll { $0.id == share.id }
        try? KeychainStore.shared.delete(share.keychainAccount)
        persist()
    }
}
