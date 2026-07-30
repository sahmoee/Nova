//
//  PersonView.swift
//  Astra
//
//  A cast/crew member's page: their photo, name, and a grid of their filmography
//  (movies + TV) from TMDB, most popular first. Tapping a title opens its detail
//  screen through the surrounding NavigationStack's CatalogItem destination.
//

import SwiftUI

struct PersonView: View {
    let member: CastMember
    @EnvironmentObject private var env: AppEnvironment

    @State private var credits: [CatalogItem] = []
    @State private var loading = true

    private let columns = [GridItem(.adaptive(minimum: Theme.CardSize.posterWidth * 0.95),
                                    spacing: Theme.Spacing.md)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header

                if loading {
                    // Use the shared LoadingView so loading states look consistent app-wide.
                    LoadingView(message: "Loading filmography…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if credits.isEmpty {
                    EmptyStateView(systemImage: "person.crop.rectangle",
                                   title: "No titles found",
                                   message: "We couldn't find a filmography for \(member.name).")
                        .frame(minHeight: 240)
                } else {
                    Text("Known For")
                        .font(Theme.Font.sectionTitle())
                        .foregroundStyle(Theme.Colors.textPrimary)
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                        ForEach(credits) { item in
                            NavigationLink(value: item) { posterCard(item) }
                                .buttonStyle(AstraListRowStyle())
                        }
                    }
                }
            }
            .padding(Theme.Spacing.edge)
            .frame(maxWidth: Theme.contentMaxWidth(1500), alignment: .leading)
        }
        .background(Theme.Colors.appBackground.ignoresSafeArea())
        .navigationTitle(member.name)
        .task {
            credits = (try? await env.tmdb.personCredits(personID: member.id)) ?? []
            loading = false
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.lg) {
            CachedAsyncImage(url: member.profileURL, maxPixel: 400) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle().fill(Theme.Colors.card)
                    .overlay(Image(systemName: "person.fill")
                        .font(.appFont(40)).foregroundStyle(Theme.Colors.textTertiary))
            }
            .frame(width: Theme.scaled(120, min: 96), height: Theme.scaled(120, min: 96))
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(member.name)
                    .font(Theme.Font.screenTitle())
                    .screenTitleStyle()
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let character = member.character, !character.isEmpty {
                    Text("as \(character)")
                        .font(.appFont(18))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func posterCard(_ item: CatalogItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            PosterImage(url: item.posterURL,
                        width: Theme.CardSize.posterWidth * 0.95,
                        height: Theme.CardSize.posterWidth * 0.95 * 1.5)
            Text(item.title)
                .font(.appFont(17, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Image(systemName: item.contentID.type == .movie ? "film" : "tv")
                if let year = item.year { Text(String(year)) }
            }
            .font(.appFont(14))
            .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: Theme.CardSize.posterWidth * 0.95)
        // Accessibility: read poster, title, and year as one element per card.
        .accessibilityElement(children: .combine)
    }
}
