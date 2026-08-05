//
//  ViewingProfileStore.swift
//  Nova
//
//  Lightweight, synced viewing profiles and Apple TV experience preferences.
//  Profiles personalize ordering and smart rails without duplicating credentials or
//  source configuration. The shared library remains the source of truth.
//

import Foundation
import Combine

struct ViewingProfile: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var systemImage: String
    var preferredTags: [String]
    var isKidsProfile: Bool
    var createdAt: Date

    init(id: UUID = UUID(),
         name: String,
         systemImage: String = "person.crop.circle.fill",
         preferredTags: [String] = [],
         isKidsProfile: Bool = false,
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.systemImage = systemImage
        self.preferredTags = preferredTags
        self.isKidsProfile = isKidsProfile
        self.createdAt = createdAt
    }
}

struct AppleTVExperiencePreferences: Codable, Hashable {
    var autoAdvanceHero = true
    var showQuickAccess = true
    var showSourceHub = true
    var showSmartCollections = true
    var showWatchHistory = true
    var showBecauseYouWatched = true
    var reduceArtworkMotion = false
}

private struct ViewingProfileState: Codable {
    var profiles: [ViewingProfile]
    var activeProfileID: UUID
    var preferences: AppleTVExperiencePreferences
}

@MainActor
final class ViewingProfileStore: ObservableObject {
    static let shared = ViewingProfileStore()

    @Published private(set) var profiles: [ViewingProfile]
    @Published var activeProfileID: UUID {
        didSet { persist() }
    }
    @Published var preferences: AppleTVExperiencePreferences {
        didSet { persist() }
    }

    private let backing = CloudBackedStore<ViewingProfileState>(key: PrefKey.viewingProfiles)
    private var applyingRemote = false
    private var cancellable: AnyCancellable?

    private init() {
        if let saved = backing.load(), !saved.profiles.isEmpty {
            profiles = saved.profiles
            activeProfileID = saved.profiles.contains(where: { $0.id == saved.activeProfileID })
                ? saved.activeProfileID
                : saved.profiles[0].id
            preferences = saved.preferences
        } else {
            let primary = ViewingProfile(name: "My Profile", systemImage: "person.crop.circle.fill")
            profiles = [primary]
            activeProfileID = primary.id
            preferences = AppleTVExperiencePreferences()
        }

        cancellable = backing.externalChange
            .sink { [weak self] state in
                guard let self, !state.profiles.isEmpty else { return }
                self.applyingRemote = true
                self.profiles = state.profiles
                self.activeProfileID = state.profiles.contains(where: { $0.id == state.activeProfileID })
                    ? state.activeProfileID
                    : state.profiles[0].id
                self.preferences = state.preferences
                self.applyingRemote = false
            }
    }

    var activeProfile: ViewingProfile {
        profiles.first(where: { $0.id == activeProfileID }) ?? profiles[0]
    }

    func select(_ profile: ViewingProfile) {
        activeProfileID = profile.id
    }

    @discardableResult
    func addProfile(name: String, systemImage: String, isKidsProfile: Bool = false) -> ViewingProfile? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, profiles.count < 6 else { return nil }
        let profile = ViewingProfile(name: clean,
                                     systemImage: systemImage,
                                     preferredTags: isKidsProfile ? ["kids", "family", "animation"] : [],
                                     isKidsProfile: isKidsProfile)
        profiles.append(profile)
        activeProfileID = profile.id
        persist()
        return profile
    }

    func update(_ profile: ViewingProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        persist()
    }

    func remove(_ profile: ViewingProfile) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == profile.id }
        if activeProfileID == profile.id {
            activeProfileID = profiles[0].id
        }
        persist()
    }

    func setPreferredTags(_ tags: [String], for profile: ViewingProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].preferredTags = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        persist()
    }

    private func persist() {
        guard !applyingRemote else { return }
        backing.persist(ViewingProfileState(profiles: profiles,
                                            activeProfileID: activeProfileID,
                                            preferences: preferences))
    }
}
