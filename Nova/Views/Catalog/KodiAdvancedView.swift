import SwiftUI
#if os(iOS)
import UniformTypeIdentifiers

struct MediaIntegrationsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var playlistName = ""
    @State private var ruleValue = ""
    @State private var repositoryURL = ""
    @State private var showNFOImporter = false
    @State private var showNFOExporter = false
    @State private var selectedNFOItem: UUID?
    @State private var nfoExportDocument: NFOExportDocument?
    @State private var showExtensionImporter = false
    @State private var nfoMessage: String?

    private var store: MediaIntegrationStore { env.mediaIntegrations }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    intro
                    upnpSection
                    nfoSection
                    smartPlaylistSection
                    extensionSection
                    if let status = store.status ?? nfoMessage {
                        Label(status, systemImage: "info.circle")
                            .font(.appFont(14)).foregroundStyle(Theme.Colors.textSecondary).softCard()
                    }
                }
                .padding(Theme.Spacing.edge)
                .frame(maxWidth: Theme.contentMaxWidth(900), alignment: .leading)
            }
            .background(Theme.Colors.appBackground.ignoresSafeArea())
            .navigationTitle("Media Tools")
            .toolbar { Button("Done") { dismiss() } }
        }
        .fileImporter(isPresented: $showNFOImporter, allowedContentTypes: [.xml, .plainText]) { result in
            guard case .success(let url) = result else { return }
            importNFO(url)
        }
        .fileImporter(isPresented: $showExtensionImporter, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            importExtensions(url)
        }
        .fileExporter(
            isPresented: $showNFOExporter,
            document: nfoExportDocument,
            contentType: .xml,
            defaultFilename: selectedNFOItem.flatMap { id in env.library.items.first { $0.id == id }?.title } ?? "nova-item"
        ) { result in
            if case .failure(let error) = result { nfoMessage = error.localizedDescription }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Portable media tools").font(Theme.Font.screenTitle()).foregroundStyle(Theme.Colors.textPrimary)
            Text("Discover local media devices, exchange portable NFO metadata, build smart playlists, and install signed data-only providers. Nova never executes third-party code.")
                .font(.appFont(16)).foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var upnpSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionTitle("UPnP / DLNA", icon: "dot.radiowaves.left.and.right")
            FocusableButton(title: "Discover Devices", systemImage: "antenna.radiowaves.left.and.right") { Task { await store.discoverUPnP() } }
            ForEach(store.discoveredDevices) { device in VStack(alignment: .leading) { Text(device.server ?? "UPnP device").font(.appFont(16, weight: .semibold)); Text(device.location.absoluteString).font(.appFont(12)).foregroundStyle(Theme.Colors.textTertiary) }.softCard() }
        }
    }

    private var nfoSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionTitle("NFO sidecars", icon: "doc.text.magnifyingglass")
            Text("Import UTF-8 movie, show, or episode NFO metadata. Nova preserves IDs, year, episode numbers, genres and artwork without replacing watch state.").font(.appFont(14)).foregroundStyle(Theme.Colors.textSecondary)
            FocusableButton(title: "Import NFO", systemImage: "square.and.arrow.down") { showNFOImporter = true }
            if !env.library.items.isEmpty {
                Picker("Export library item", selection: $selectedNFOItem) {
                    Text("Choose an item").tag(UUID?.none)
                    ForEach(env.library.items) { item in Text(item.displayTitle).tag(Optional(item.id)) }
                }
                .pickerStyle(.menu)
                FocusableButton(title: "Export NFO", systemImage: "square.and.arrow.up") {
                    guard let id = selectedNFOItem,
                          let item = env.library.items.first(where: { $0.id == id }) else {
                        nfoMessage = "Choose a library item to export"; return
                    }
                    nfoExportDocument = NFOExportDocument(data: KodiNFOCodec.export(item))
                    showNFOExporter = true
                }
            }
        }
    }

    private var smartPlaylistSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionTitle("Smart playlists", icon: "line.3.horizontal.decrease.circle")
            ForEach(store.smartPlaylists) { list in Text("\(list.name) · \(env.library.items.filter(list.matches).count) matches").softCard() }
            HStack { TextField("Playlist name", text: $playlistName).fieldCard(); TextField("Title contains…", text: $ruleValue).fieldCard() }
            FocusableButton(title: "Create Smart Playlist", systemImage: "plus") {
                guard !playlistName.isEmpty, !ruleValue.isEmpty else { return }
                store.smartPlaylists.append(.init(name: playlistName, rules: [.init(field: .title, operation: .contains, value: ruleValue)])); playlistName = ""; ruleValue = ""
            }
        }
    }

    private var extensionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionTitle("Verified providers", icon: "checkmark.shield")
            Text("Signed declarative providers may return metadata, playlists, or subtitles only from allow-listed HTTPS hosts. They cannot execute code or read device files.").font(.appFont(14)).foregroundStyle(Theme.Colors.textSecondary)
            ForEach(store.extensions) { item in Label("\(item.name) · \(item.kind.rawValue)", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.Colors.success).softCard() }
            ForEach(store.repositoryURLs, id: \.self) { url in Text(url.absoluteString).font(.appFont(12)).foregroundStyle(Theme.Colors.textTertiary).softCard() }
            TextField("https://example.com/nova-repository.json", text: $repositoryURL).fieldCard().textInputAutocapitalization(.never).autocorrectionDisabled()
            FocusableButton(title: "Add Auto-Update Repository", systemImage: "arrow.triangle.2.circlepath") {
                guard let url = URL(string: repositoryURL), url.scheme == "https" else { store.status = "Repositories must use HTTPS"; return }
                store.addRepository(url); repositoryURL = ""
            }
            FocusableButton(title: "Import Signed Repository", systemImage: "signature") { showExtensionImporter = true }
        }
    }

    private func sectionTitle(_ text: String, icon: String) -> some View { Label(text, systemImage: icon).font(Theme.Font.sectionTitle()).foregroundStyle(Theme.Colors.textPrimary) }

    private func importNFO(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let record = try KodiNFOCodec.parse(Data(contentsOf: url))
            let candidates = ["mkv", "mp4", "mov", "avi", "m4v"].map { url.deletingPathExtension().appendingPathExtension($0) }
            guard let media = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { nfoMessage = "NFO parsed: \(record.title). Put it beside a matching video file to import playback."; return }
            env.library.add(KodiNFOCodec.mediaItem(from: record, mediaURL: media)); nfoMessage = "Imported \(record.title)"
        } catch { nfoMessage = error.localizedDescription }
    }

    private func importExtensions(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do { let repo = try JSONDecoder().decode(NovaExtensionRepository.self, from: Data(contentsOf: url)); store.installRepository(repo) } catch { store.status = error.localizedDescription }
    }
}

private struct NFOExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.xml, .plainText] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private extension View {
    func fieldCard() -> some View { self.textFieldStyle(.plain).padding(Theme.Spacing.md).background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button)) }
}
#endif
