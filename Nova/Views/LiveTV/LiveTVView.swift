//
//  LiveTVView.swift
//  Nova
//
//  Lists live channels from any installed addon that exposes a tv/channel catalog,
//  and plays the selected channel. Channels stream as live HLS, so playback is not
//  resumed or scrobbled. If no live-TV addon is installed, explains how to add one.
//

import SwiftUI
#if os(iOS)
import WebKit
#elseif os(tvOS)
import CoreImage.CIFilterBuiltins
import UIKit
#endif

struct LiveTVView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var sources: [(addon: InstalledAddon, catalog: AddonCatalogRef)] = []
    @State private var channels: [String: [CatalogItem]] = [:]   // keyed by catalog id
    @State private var loadingKeys: Set<String> = []
    @State private var playable: MediaItem?
    @State private var resolving = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: Theme.Spacing.md)]

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()

            if sources.isEmpty && env.liveTVSources.allChannels.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.rowGap) {
                        HStack {
                            Text("Live TV")
                                .font(Theme.Font.screenTitle())
                                .screenTitleStyle()
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer()
                            NavigationLink { SportsProvidersView() } label: {
                                Label("Sports", systemImage: "sportscourt.fill")
                                    .font(.appFont(16, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .padding(.horizontal, Theme.Spacing.sm)
                                    .padding(.vertical, Theme.Spacing.xs)
                                    .background(Theme.Colors.card,
                                                in: Capsule(style: .continuous))
                            }
                            .buttonStyle(NovaChipButtonStyle())
                            .accessibilityHint("Open official sports providers")
                            NavigationLink { LiveTVSourcesView() } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.appFont(20, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .padding(Theme.Spacing.sm)
                                    .background(Theme.Colors.card, in: Circle())
                            }
                            .novaIconStyle()
                        }
                        .padding(.horizontal, Theme.Spacing.edge)

                        playlistChannelsSection

                        ForEach(sources, id: \.catalog.id) { source in
                            channelSection(source)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.lg)
                }
                #if os(iOS)
                // Pull-to-refresh reloads playlists and the programme guide (touch only).
                .refreshable {
                    await env.liveTVSources.refreshAll()
                    await loadEPG()
                }
                #endif
            }

            if resolving {
                LoadingView(message: "Tuning in…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.5))
            }
        }
        .fullScreenCover(item: $playable) { item in
            // Present the player as a full-screen cover so no tab bar, sidebar,
            // or mini-bar remains visible during playback on any platform.
            NavigationStack { PlayerView(item: item) }
        }
        .alert("Couldn't play channel", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear(perform: loadSources)
        .task {
            await env.liveTVSources.refreshAll()
            await loadEPG()
        }
    }

    @State private var channelFilter = ""
    /// tvg-id -> current programme title, refreshed when the screen loads guides.
    @State private var nowPlaying: [String: String] = [:]

    @ViewBuilder private var playlistChannelsSection: some View {
        let channels = env.liveTVSources.allChannels
        if !channels.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("From Your Sources")
                    .font(.appFont(22, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.horizontal, Theme.Spacing.edge)

                // A filter field appears once the playlist is big enough to need one.
                if channels.count > 12 {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Theme.Colors.textTertiary)
                        TextField("Filter channels", text: $channelFilter)
                            .font(.appFont(17))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        if !channelFilter.isEmpty {
                            Button { channelFilter = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.card,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .padding(.horizontal, Theme.Spacing.edge)
                }

                let filtered = channelFilter.isEmpty
                    ? channels
                    : channels.filter { $0.name.localizedCaseInsensitiveContains(channelFilter) }
                // Group channels by their M3U group-title so big playlists read as
                // organized sections (News, Sports, ...) instead of one endless grid.
                let grouped = Dictionary(grouping: filtered) { $0.group ?? "Channels" }
                let groupNames = grouped.keys.sorted()

                ForEach(groupNames, id: \.self) { group in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        if groupNames.count > 1 {
                            Text(group)
                                .font(.appFont(17, weight: .semibold))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .padding(.horizontal, Theme.Spacing.edge)
                        }
                        LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                            ForEach(grouped[group] ?? []) { channel in
                                channelCell(channel)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.edge)
                    }
                }
            }
        }
    }

    private func channelCell(_ channel: LiveTVChannel) -> some View {
        Button {
            playable = env.liveTVSources.makePlayable(channel)
        } label: {
            VStack(spacing: 6) {
                CachedAsyncImage(url: channel.logoURL, maxPixel: 300) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.Colors.card)
                        .overlay(Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.appFont(28)).foregroundStyle(Theme.Colors.textTertiary))
                }
                .frame(height: 90)
                .frame(maxWidth: .infinity)
                .background(Theme.Colors.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                Text(channel.name)
                    .font(.appFont(13, weight: .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                // Now-playing line from the source's XMLTV guide, when available.
                if let tvgID = channel.tvgID, let current = nowPlaying[tvgID] {
                    Text(current)
                        .font(.appFont(11))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(NovaListRowStyle())
    }

    /// Loads every enabled source's XMLTV guide and resolves the current programme
    /// for each channel that carries a tvg-id.
    private func loadEPG() async {
        let sources = env.liveTVSources.sources.filter { $0.isEnabled && $0.epgURL != nil }
        guard !sources.isEmpty else { return }
        for source in sources {
            if let raw = source.epgURL, let url = URL(string: raw) {
                await EPGService.shared.loadGuide(from: url)
            }
        }
        let ids = env.liveTVSources.allChannels.compactMap(\.tvgID)
        guard !ids.isEmpty else { return }
        nowPlaying = await EPGService.shared.nowPlaying(tvgIDs: ids)
    }

    private func channelSection(_ source: (addon: InstalledAddon, catalog: AddonCatalogRef)) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(source.catalog.name)
                    .font(Theme.Font.sectionTitle())
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(source.addon.name.uppercased())
                    .font(.appFont(12, weight: .bold))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
            .padding(.horizontal, Theme.Spacing.edge)

            let key = source.catalog.id
            if let list = channels[key] {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                    ForEach(list) { channel in
                        Button { play(channel) } label: { channelCard(channel) }
                            .buttonStyle(NovaListRowStyle())
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
            } else {
                ProgressView().tint(Theme.Colors.accent)
                    .padding(.horizontal, Theme.Spacing.edge)
                    .task { await loadChannels(source) }
            }
        }
    }

    private func channelCard(_ channel: CatalogItem) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Colors.card)
                CachedAsyncImage(url: channel.posterURL) { image in
                    image.resizable().aspectRatio(contentMode: .fit).padding(8)
                } placeholder: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.appFont(34))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .frame(height: 110)
            Text(channel.title)
                .font(.appFont(15, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            EmptyStateView(
                systemImage: "dot.radiowaves.left.and.right",
                title: "No Live TV yet",
                message: "Turn on a free channel source or add your own M3U or Xtream-codes playlist. You can also add a Stremio addon that provides live channels under Settings ▸ Addons."
            )
            NavigationLink { LiveTVSourcesView() } label: {
                Label("Choose Sources", systemImage: "slider.horizontal.3")
                    .font(.appFont(17, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.vertical, Theme.Spacing.md)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .background(Capsule().fill(.white))
            }
            .novaRowStyle()
        }
    }

    // MARK: - Loading

    private func loadSources() {
        sources = env.shelfLoader.liveTVCatalogs()
    }

    private func loadChannels(_ source: (addon: InstalledAddon, catalog: AddonCatalogRef)) async {
        let key = source.catalog.id
        guard channels[key] == nil, !loadingKeys.contains(key) else { return }
        loadingKeys.insert(key)
        let list = await env.catalog.liveChannels(addon: source.addon, catalog: source.catalog)
        channels[key] = list
        loadingKeys.remove(key)
    }

    private func play(_ channel: CatalogItem) {
        resolving = true
        Task {
            do {
                let item = try await env.catalog.makeLiveChannelPlayable(channel: channel)
                await MainActor.run { resolving = false; playable = item }
            } catch {
                await MainActor.run {
                    resolving = false
                    errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? "This channel couldn't be opened."
                }
            }
        }
    }
}

// MARK: - Official sports providers

/// A safe doorway to official sports services. Nova does not embed or resolve
/// third-party restreams: provider authentication and playback remain owned by
/// the service the user opens.
struct SportsProvidersView: View {
    private struct Provider: Identifiable, Hashable {
        let id: String
        let name: String
        let detail: String
        let systemImage: String
        let url: URL
    }

    private let providers: [Provider] = [
        .init(id: "espn", name: "ESPN", detail: "Live and upcoming sports", systemImage: "sportscourt", url: URL(string: "https://www.espn.com/watch/")!),
        .init(id: "apple", name: "Apple TV Sports", detail: "MLS and Apple sports coverage", systemImage: "appletv.fill", url: URL(string: "https://tv.apple.com/us/room/sports/edt.item.635f48fe-1355-44e5-81e5-26eb857f9823")!),
        .init(id: "peacock", name: "Peacock Sports", detail: "Premier League, golf, racing, and more", systemImage: "play.tv.fill", url: URL(string: "https://www.peacocktv.com/sports")!),
        .init(id: "paramount", name: "Paramount+ Sports", detail: "CBS Sports and soccer", systemImage: "star.circle.fill", url: URL(string: "https://www.paramountplus.com/sports/")!),
        .init(id: "nba", name: "NBA League Pass", detail: "NBA games and coverage", systemImage: "basketball.fill", url: URL(string: "https://www.nba.com/watch/league-pass-stream")!),
        .init(id: "nfl", name: "NFL+", detail: "NFL live and on-demand coverage", systemImage: "football.fill", url: URL(string: "https://www.nfl.com/plus/")!),
        .init(id: "ufc", name: "UFC Fight Pass", detail: "UFC and combat sports", systemImage: "figure.martial.arts", url: URL(string: "https://ufcfightpass.com/")!)
    ]

    @State private var tvProvider: Provider?
    @State private var showsCustomWebsite = false
    #if os(tvOS)
    @State private var pendingCustomWebsite: URL?
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                #if os(tvOS)
                TVPageHeading(title: "Sports", systemImage: "sportscourt.fill")
                #else
                NovaGradientPageHeader(title: "Sports",
                                       subtitle: "Open an official provider. Your subscription and sign-in stay with that service.",
                                       systemImage: "sportscourt.fill")
                #endif

                Button { showsCustomWebsite = true } label: {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "link")
                            .font(.appFont(28, weight: .semibold))
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Open Your Own Link").font(.appFont(18, weight: .semibold))
                            Text("Paste an unverified HTTPS website at your own risk")
                                .font(.appFont(13))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.card,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.card,
                                                     style: .continuous))
                }
                .buttonStyle(NovaArtworkButtonStyle())

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: Theme.Spacing.md)],
                          spacing: Theme.Spacing.md) {
                    ForEach(providers) { provider in
                        #if os(iOS)
                        NavigationLink(value: provider) { providerCard(provider) }
                            .buttonStyle(NovaArtworkButtonStyle())
                        #else
                        Button { tvProvider = provider } label: { providerCard(provider) }
                            .buttonStyle(NovaArtworkButtonStyle())
                        #endif
                    }
                }

                Text("Nova blocks new-window popups in its iPhone and iPad browser. Provider authentication, availability, subscriptions, and playback are controlled by each service.")
                    .font(.appFont(13))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(Theme.Spacing.edge)
        }
        .background(Theme.Colors.appBackground.ignoresSafeArea())
        .sheet(isPresented: $showsCustomWebsite,
               onDismiss: presentPendingTVWebsite) {
            CustomSportsWebsiteEntryView { url in
                #if os(tvOS)
                pendingCustomWebsite = url
                #endif
            }
        }
        #if os(iOS)
        .navigationDestination(for: Provider.self) { provider in
            SportsProviderBrowser(title: provider.name, url: provider.url)
        }
        #else
        .sheet(item: $tvProvider) { provider in
            SportsTVHandoffView(title: provider.name, payload: provider.url.absoluteString)
        }
        #endif
    }

    private func presentPendingTVWebsite() {
        #if os(tvOS)
        guard let url = pendingCustomWebsite else { return }
        pendingCustomWebsite = nil
        tvProvider = Provider(id: "custom-\(UUID().uuidString)",
                              name: url.host ?? "Website",
                              detail: "User-provided website",
                              systemImage: "link",
                              url: url)
        #endif
    }

    private func providerCard(_ provider: Provider) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: provider.systemImage)
                .font(.appFont(28, weight: .semibold))
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(provider.name).font(.appFont(18, weight: .semibold))
                Text(provider.detail).font(.appFont(13)).foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").foregroundStyle(Theme.Colors.textTertiary)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

private enum CustomSportsWebsitePolicy {
    static func normalizedURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: candidate),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil else { return nil }
        components.scheme = "https"
        return components.url
    }
}

private struct CustomSportsWebsiteEntryView: View {
    let onTVHandoff: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var errorMessage: String?
    #if os(iOS)
    @State private var openedURL: URL?
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.appFont(40, weight: .semibold))
                        .foregroundStyle(.orange)

                    Text("Open an Unverified Website")
                        .font(.appFont(28, weight: .bold))

                    Text("Nova does not verify, recommend, or control websites you paste. Continue only if you trust the address and have permission to view its content.")
                        .font(.appFont(16))
                        .foregroundStyle(Theme.Colors.textSecondary)

                    TextField("https://example.com", text: $address)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        #endif
                        .onSubmit(openWebsite)

                    Text("Only secure HTTPS addresses are accepted. On iPhone and iPad, Nova keeps the site inside its popup-blocking browser. Apple TV shows a QR code for handoff.")
                        .font(.appFont(13))
                        .foregroundStyle(Theme.Colors.textSecondary)

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.appFont(14, weight: .semibold))
                            .foregroundStyle(.red)
                    }

                    Button("Open at My Own Risk", action: openWebsite)
                        .buttonStyle(NovaRowButtonStyle())
                        .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(Theme.Spacing.edge)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.Colors.appBackground.ignoresSafeArea())
            .navigationTitle("Open Website")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            #if os(iOS)
            .navigationDestination(isPresented: Binding(
                get: { openedURL != nil },
                set: { if !$0 { openedURL = nil } }
            )) {
                if let openedURL {
                    SportsProviderBrowser(title: openedURL.host ?? "Website", url: openedURL)
                }
            }
            #endif
        }
    }

    private func openWebsite() {
        guard let url = CustomSportsWebsitePolicy.normalizedURL(from: address) else {
            errorMessage = "Enter a valid HTTPS website without an embedded username or password."
            return
        }
        errorMessage = nil
        #if os(iOS)
        openedURL = url
        #else
        onTVHandoff(url)
        dismiss()
        #endif
    }
}

#if os(tvOS)
private struct SportsTVHandoffView: View {
    let title: String
    let payload: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text(title).font(.appFont(34, weight: .bold))
            if let image = Self.qrImage(for: payload) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 420, height: 420)
                    .padding(Theme.Spacing.md)
                    .background(.white,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.card,
                                                     style: .continuous))
            }
            Text("Scan with a phone or tablet to open the official provider.")
                .font(.appFont(20))
                .foregroundStyle(Theme.Colors.textSecondary)
            Button("Done") { dismiss() }.buttonStyle(NovaRowButtonStyle())
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.appBackground.ignoresSafeArea())
    }

    private static func qrImage(for string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
#endif

#if os(iOS)
private struct SportsProviderBrowser: View {
    let title: String
    let url: URL
    var body: some View {
        PopupBlockingWebView(url: url)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .background(Theme.Colors.appBackground)
    }
}

private struct PopupBlockingWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad,
                                timeoutInterval: 30))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url == nil else { return }
        webView.load(URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad,
                                timeoutInterval: 30))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let target = navigationAction.targetFrame else {
                // Keep legitimate provider links in the current view while
                // refusing the extra window that advertising scripts request.
                if navigationAction.navigationType == .linkActivated,
                   let url = navigationAction.request.url,
                   ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    webView.load(navigationAction.request)
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) { completionHandler() }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) { completionHandler(false) }
    }
}
#endif
