//
//  SMBListView.swift
//  FrameTV
//
//  Lists saved SMB shares and routes to add/browse. Persists share definitions
//  via a small JSON store; passwords go to the Keychain. Browsing uses the
//  MockSMBProvider in Phase 1/2 and the real provider in Phase 5.
//

import SwiftUI
import Combine

struct SMBListView: View {
    @StateObject private var model = SMBSharesModel()
    @State private var showingAdd = false

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                ScreenHeader(title: "SMB Shares") {
                    FocusableButton(title: "Add Share", systemImage: "plus", prominent: true) {
                        showingAdd = true
                    }
                    .frame(maxWidth: Theme.isCompact ? .infinity : 280)
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
                                NavigationLink {
                                    SMBBrowseView(share: share)
                                } label: {
                                    shareRow(share)
                                }
                                .buttonStyle(.plain)
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
    }

    private func shareRow(_ share: SMBShare) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.appFont(30))
                .foregroundStyle(Theme.Colors.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(share.displayName)
                    .font(Theme.Font.cardTitle())
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("\(share.host)/\(share.shareName)")
                    .font(.appFont(18))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Button {
                model.remove(share)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Theme.Colors.error)
            }
            .buttonStyle(.plain)
            Image(systemName: "chevron.right")
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

// MARK: - Add view

struct SMBAddView: View {
    let onSave: (SMBShare, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var host = ""
    @State private var shareName = ""
    @State private var username = ""
    @State private var password = ""
    @State private var path = ""

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text("Add SMB Share")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)

                    field("Display Name", text: $displayName, placeholder: "Living Room NAS")
                    field("Server (hostname or IP)", text: $host,
                          placeholder: "sowens.local  or  192.168.1.10")
                        .onChange(of: host) { _, newValue in normalizeHost(newValue) }
                    Text("You can enter a network name like sowens.local, an IP address, or paste a full path such as smb://sowens.local/Home.")
                        .font(.appFont(15))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    field("Share Name", text: $shareName, placeholder: "Home")
                    field("Username", text: $username, placeholder: "guest")
                    secureField("Password", text: $password)
                    field("Path (optional)", text: $path, placeholder: "/Movies")

                    FocusableButton(title: "Save Share", systemImage: "checkmark", prominent: true) {
                        let share = SMBShare(
                            displayName: displayName.isEmpty ? host : displayName,
                            host: host,
                            shareName: shareName,
                            username: username,
                            path: path.isEmpty ? nil : path
                        )
                        onSave(share, password)
                    }
                    .frame(maxWidth: Theme.isCompact ? .infinity : 360)
                    .disabled(host.isEmpty || shareName.isEmpty)
                    .padding(.top, Theme.Spacing.sm)
                }
                .padding(Theme.Spacing.edge)
                .frame(maxWidth: Theme.contentMaxWidth(1000), alignment: .leading)
            }
        }
    }

    /// Accepts a hostname, IP, or a pasted full path (with or without an smb://
    /// scheme) and splits it into the server, share, and path fields. Examples:
    ///   "smb://sowens.local/Home/Movies" -> host=sowens.local, share=Home, path=/Movies
    ///   "sowens.local/Home"              -> host=sowens.local, share=Home
    ///   "192.168.1.10"                   -> host unchanged
    private func normalizeHost(_ raw: String) {
        guard let parsed = SMBURLParser.parse(raw) else { return }
        host = parsed.host
        if let share = parsed.share, shareName.isEmpty { shareName = share }
        if let p = parsed.path, path.isEmpty { path = p }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label).font(.appFont(20, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    private func secureField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label).font(.appFont(20, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            SecureField("••••••••", text: text)
                .textFieldStyle(.plain)
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
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
        // Store password securely; never persisted in JSON.
        try? KeychainStore.shared.set(password, for: share.keychainAccount)
        persist()
    }

    func remove(_ share: SMBShare) {
        shares.removeAll { $0.id == share.id }
        try? KeychainStore.shared.delete(share.keychainAccount)
        persist()
    }
}
