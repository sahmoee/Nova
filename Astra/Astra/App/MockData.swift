//
//  MockData.swift
//  Astra
//
//  Public-domain / Creative-Commons sample media used to populate the UI during
//  Phase 1/2. These are well-known open test assets — safe, legal placeholders.
//

import Foundation

enum MockData {

    static var sampleLibrary: [MediaItem] {
        [bigBuckBunny, sintel, tearsOfSteel, elephantsDream, forBiggerBlazes]
    }

    static let bigBuckBunny = MediaItem(
        title: "Big Buck Bunny",
        sourceType: .publicDomain,
        playbackURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!,
        posterURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg"),
        duration: 596,
        lastPlayedPosition: 120,                       // gives Continue Watching something to show
        lastPlayedDate: Date().addingTimeInterval(-3600),
        isFavorite: true,
        legalAccessConfirmed: true,
        metadata: MediaMetadata(filename: "BigBuckBunny.mp4", resolution: "1080p", year: 2008)
    )

    static let sintel = MediaItem(
        title: "Sintel",
        sourceType: .publicDomain,
        playbackURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4")!,
        posterURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/Sintel.jpg"),
        duration: 888,
        legalAccessConfirmed: true,
        metadata: MediaMetadata(filename: "Sintel.mp4", resolution: "1080p", year: 2010)
    )

    static let tearsOfSteel = MediaItem(
        title: "Tears of Steel",
        sourceType: .publicDomain,
        playbackURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4")!,
        posterURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/TearsOfSteel.jpg"),
        duration: 734,
        lastPlayedPosition: 300,
        lastPlayedDate: Date().addingTimeInterval(-7200),
        legalAccessConfirmed: true,
        metadata: MediaMetadata(filename: "TearsOfSteel.mp4", resolution: "720p", year: 2012)
    )

    static let elephantsDream = MediaItem(
        title: "Elephants Dream",
        sourceType: .publicDomain,
        playbackURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4")!,
        posterURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ElephantsDream.jpg"),
        duration: 654,
        legalAccessConfirmed: true,
        metadata: MediaMetadata(filename: "ElephantsDream.mp4", resolution: "1080p", year: 2006)
    )

    static let forBiggerBlazes = MediaItem(
        title: "For Bigger Blazes",
        sourceType: .directURL,
        playbackURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4")!,
        posterURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerBlazes.jpg"),
        duration: 15,
        legalAccessConfirmed: true,
        metadata: MediaMetadata(filename: "ForBiggerBlazes.mp4", resolution: "1080p")
    )
}
