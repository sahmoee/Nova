//
//  MagnetView.swift
//  FrameTV
//
//  Submit a magnet link (that the user is authorized to access) to Real-Debrid,
//  poll for metadata, let the user pick the video file, and add it to the library.
//
//  No search, no source suggestions, no scraping. The magnet is only ever sent
//  to the user's own Real-Debrid account. A legal confirmation gate is required.
//

import SwiftUI

struct MagnetView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore

    @State private var magnetText = ""
    @State private var legalConfirmed = false
    @State private var phase: Phase = .input
    @State private var torrentID: String?
    @State private var files: [TorrentFile] = []
    @State private var selectedFileIDs: Set<Int> = []
    @State private var message: String?
    @State private var addedItem: MediaItem?
    @State private var navigate = false

    enum Phase: Equatable { case input, loadingMeta, selectFiles, finalizing, error(String) }

    private var hasToken: Bool { KeychainStore.shared.realDebridToken != nil }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Magnet Link")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)

                    if !hasToken {
                        noTokenNotice
                    }

                    switch phase {
                    case .input:        inputSection
                    case .loadingMeta:  LoadingView(message: "Fetching torrent details…").frame(height: 300)
                    case .selectFiles:  fileSelectionSection
                    case .finalizing:   LoadingView(message: "Preparing your file…").frame(height: 300)
                    case .error(let m): ErrorStateView(message: m, onRetry: { phase = .input })
                    }

                    if let message, phase == .input {
                        Label(message, systemImage: "info.circle")
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .font(.appFont(20))
                    }
                }
                .padding(Theme.Spacing.edge)
                .frame(maxWidth: Theme.contentMaxWidth(1100), alignment: .leading)
            }

            NavigationLink(isActive: $navigate) {
                if let addedItem { PlayerView(item: addedItem) }
            } label: { EmptyView() }.hidden()
        }
    }

    private var noTokenNotice: some View {
        Label("Connect your Real-Debrid account first (Sources ▸ Real-Debrid).",
              systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(Theme.Colors.warning)
            .font(.appFont(20))
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Paste a magnet link you own or are authorized to access. FrameTV sends it only to your Real-Debrid account.")
                .font(.appFont(20))
                .foregroundStyle(Theme.Colors.textSecondary)

            TextField("magnet:?xt=urn:btih:…", text: $magnetText)
                .textFieldStyle(.plain)
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                .foregroundStyle(Theme.Colors.textPrimary)

            // Legal confirmation is always shown for magnets, regardless of setting.
            LegalConfirmToggle(isOn: $legalConfirmed)

            FocusableButton(title: "Submit to Real-Debrid", systemImage: "arrow.up.circle", prominent: true) {
                Task { await submit() }
            }
            .frame(maxWidth: Theme.isCompact ? .infinity : 400)
            .disabled(!canSubmit)
        }
    }

    private var fileSelectionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Select the video to add")
                .font(Theme.Font.sectionTitle())
                .foregroundStyle(Theme.Colors.textPrimary)

            ForEach(files.filter { $0.isPlayableVideo }) { file in
                Button {
                    toggle(file)
                } label: {
                    HStack {
                        Image(systemName: selectedFileIDs.contains(file.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedFileIDs.contains(file.id) ? Theme.Colors.accent : Theme.Colors.textSecondary)
                            .font(.appFont(26))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.filename)
                                .font(.appFont(22, weight: .medium))
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(ByteCountFormatter.string(fromByteCount: file.bytes, countStyle: .file))
                                .font(.appFont(16))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        Spacer()
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            FocusableButton(title: "Add Selected", systemImage: "plus", prominent: true) {
                Task { await finalizeSelection() }
            }
            .frame(maxWidth: Theme.isCompact ? .infinity : 360)
            .disabled(selectedFileIDs.isEmpty)
        }
    }

    private var canSubmit: Bool {
        hasToken
        && URLValidation.isMagnetLink(magnetText)
        && legalConfirmed
    }

    // MARK: - Flow

    private func submit() async {
        guard LegalAccessGate.mayProceed(userConfirmed: legalConfirmed, requireConfirmation: true) else {
            message = "Please confirm you're authorized to access this content."
            return
        }
        phase = .loadingMeta
        do {
            let added = try await environment.realDebrid.addMagnet(magnetText)
            torrentID = added.id
            // Poll torrent info until files are listed / selection is needed.
            let info = try await pollUntilFilesAvailable(id: added.id)
            files = info.files ?? []
            // Preselect the largest video by default.
            if let biggest = files.filter({ $0.isPlayableVideo }).max(by: { $0.bytes < $1.bytes }) {
                selectedFileIDs = [biggest.id]
            }
            phase = .selectFiles
        } catch {
            phase = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func finalizeSelection() async {
        guard let torrentID else { return }
        phase = .finalizing
        do {
            try await environment.realDebrid.selectFiles(
                torrentID: torrentID,
                fileIDs: selectedFileIDs.map(String.init)
            )
            // Poll until the torrent is downloaded and links are ready.
            let ready = try await pollUntilReady(id: torrentID)
            guard let link = ready.links?.first else {
                phase = .error("No download link was produced. Try again shortly.")
                return
            }
            // Unrestrict the resolved link into a playable URL.
            let unrestricted = try await environment.realDebrid.unrestrictLink(link)
            guard let url = unrestricted.downloadURL else {
                phase = .error("Couldn't resolve a playable URL.")
                return
            }
            let name = unrestricted.filename ?? url.lastPathComponent
            let item = MediaItem(
                title: MetadataParser.cleanTitle(from: name),
                sourceType: .realDebrid,
                playbackURL: url,
                legalAccessConfirmed: true,
                metadata: MetadataParser.parse(filename: name, fileSize: unrestricted.filesize)
            )
            library.add(item)
            addedItem = item
            navigate = true
        } catch {
            phase = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - Polling helpers

    /// Polls torrent info until files are available or selection is needed.
    private func pollUntilFilesAvailable(id: String) async throws -> TorrentInfo {
        for _ in 0..<30 {
            let info = try await environment.realDebrid.torrentInfo(id: id)
            if let files = info.files, !files.isEmpty { return info }
            if info.needsFileSelection { return info }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw RealDebridError.notReady
    }

    /// Polls torrent info until status is downloaded and links exist.
    private func pollUntilReady(id: String) async throws -> TorrentInfo {
        for _ in 0..<60 {
            let info = try await environment.realDebrid.torrentInfo(id: id)
            if info.isReady, let links = info.links, !links.isEmpty { return info }
            try await Task.sleep(nanoseconds: 3_000_000_000)
        }
        throw RealDebridError.notReady
    }

    private func toggle(_ file: TorrentFile) {
        if selectedFileIDs.contains(file.id) { selectedFileIDs.remove(file.id) }
        else { selectedFileIDs.insert(file.id) }
    }
}
