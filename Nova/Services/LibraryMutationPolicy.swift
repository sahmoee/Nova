import Foundation

/// Pure library mutations shared by device code and local regression fixtures.
enum LibraryMutationPolicy {
    struct Reconciliation {
        var items: [MediaItem]
        var renamedKeys: [String: String]
    }

    static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }

    static func orderedValues<Key: Hashable, Value>(keys: [Key], values: [Value], key: (Value) -> Key) -> [Value] {
        var lookup: [Key: Value] = [:]
        for value in values where lookup[key(value)] == nil { lookup[key(value)] = value }
        return unique(keys).compactMap { lookup[$0] }
    }

    static func moving<T>(_ values: [T], from source: IndexSet, to destination: Int) -> [T]? {
        guard !source.isEmpty, destination >= 0, destination <= values.count,
              source.allSatisfy({ values.indices.contains($0) }) else { return nil }
        let moved = source.map { values[$0] }
        var remaining = values.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let adjusted = destination - source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moved, at: adjusted)
        return remaining
    }

    static func location(_ item: MediaItem) -> MediaSourceLocation {
        MediaSourceLocation(sourceType: item.sourceType, playbackURL: item.playbackURL,
                            mediaServerID: item.metadata.mediaServerID,
                            mediaServerItemID: item.metadata.mediaServerItemID)
    }

    static func merged(_ incoming: MediaItem, preserving existing: MediaItem) -> MediaItem {
        var updated = incoming
        updated.id = existing.id
        updated.isFavorite = existing.isFavorite
        updated.addedDate = existing.addedDate
        updated.lastPlayedPosition = existing.lastPlayedPosition
        updated.lastPlayedDate = existing.lastPlayedDate
        updated.duration = MediaReliabilityPolicy.validDuration(incoming.duration) ?? existing.duration
        updated.subtitleOffset = existing.subtitleOffset
        updated.tags = existing.tags
        updated.isHidden = existing.isHidden
        updated.legalAccessConfirmed = existing.legalAccessConfirmed || incoming.legalAccessConfirmed
        if updated.posterURL == nil { updated.posterURL = existing.posterURL }
        if updated.backdropURL == nil { updated.backdropURL = existing.backdropURL }
        if updated.subtitles.isEmpty { updated.subtitles = existing.subtitles }
        if updated.skipSegments.isEmpty { updated.skipSegments = existing.skipSegments }

        let primary = location(incoming)
        // Prefer newly refreshed alternate URLs over stale copies with the same server identity.
        var seen: Set<String> = [primary.identity]
        updated.alternateSources = (incoming.alternateSources + [location(existing)] + existing.alternateSources)
            .filter { seen.insert($0.identity).inserted }
        return updated
    }

    /// O(existing + incoming) lookup work, with one published array at the call site.
    static func adding(_ incoming: [MediaItem], to existing: [MediaItem]) -> [MediaItem] {
        var result = existing
        var positions: [String: Int] = [:]
        for (index, item) in result.enumerated() where positions[item.contentKey] == nil { positions[item.contentKey] = index }
        var appended = 0
        for item in incoming {
            if let index = positions[item.contentKey] { result[index] = merged(item, preserving: result[index]) }
            else { positions[item.contentKey] = result.count; result.append(item); appended += 1 }
        }
        // Match single-add insertion semantics: the final newly added title leads.
        return Array(result.suffix(appended).reversed()) + result.dropLast(appended)
    }

    static func reconcile(_ incoming: [MediaItem], existing: [MediaItem], connectionID: UUID) -> Reconciliation {
        // A caller error must not make another server's rows look like this one's live inventory.
        let incoming = incoming.filter { $0.metadata.mediaServerID == connectionID && $0.metadata.mediaServerItemID?.isEmpty == false }
        let liveIDs = Set(incoming.compactMap(\.metadata.mediaServerItemID))
        var result = existing.compactMap { original -> MediaItem? in
            var item = original
            item.alternateSources.removeAll {
                $0.mediaServerID == connectionID && !liveIDs.contains($0.mediaServerItemID ?? "")
            }
            guard item.metadata.mediaServerID == connectionID,
                  !liveIDs.contains(item.metadata.mediaServerItemID ?? "") else { return item }
            guard let fallback = item.alternateSources.first else { return nil }
            item.alternateSources.removeFirst()
            item.sourceType = fallback.sourceType
            item.playbackURL = fallback.playbackURL
            item.metadata.mediaServerID = fallback.mediaServerID
            item.metadata.mediaServerItemID = fallback.mediaServerItemID
            return item
        }
        var positions: [String: Int] = [:]
        var nativePositions: [String: Int] = [:]
        for (index, item) in result.enumerated() {
            if positions[item.contentKey] == nil { positions[item.contentKey] = index }
            for source in [location(item)] + item.alternateSources where source.mediaServerID == connectionID {
                nativePositions[source.identity] = index
            }
        }
        var renamed: [String: String] = [:]
        for item in incoming {
            if let index = nativePositions[location(item).identity] ?? positions[item.contentKey] {
                let oldKey = result[index].contentKey
                result[index] = merged(item, preserving: result[index])
                if oldKey != item.contentKey {
                    renamed[oldKey] = item.contentKey
                    if positions[oldKey] == index { positions.removeValue(forKey: oldKey) }
                }
                positions[item.contentKey] = index
                nativePositions[location(item).identity] = index
            } else {
                positions[item.contentKey] = result.count
                nativePositions[location(item).identity] = result.count
                result.append(item)
            }
        }
        result.sort {
            $0.addedDate != $1.addedDate ? $0.addedDate > $1.addedDate : $0.id.uuidString < $1.id.uuidString
        }
        return Reconciliation(items: result, renamedKeys: renamed)
    }

    static func remapping(_ collections: [MediaCollection], keys: [String: String]) -> [MediaCollection] {
        guard !keys.isEmpty else { return collections }
        return collections.map { collection in
            var result = collection
            result.contentKeys = unique(collection.contentKeys.map { key in
                var value = key
                var seen = Set<String>()
                while let next = keys[value], seen.insert(value).inserted { value = next }
                return value
            })
            return result
        }
    }

    static func normalizedTag(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func duplicateKey(_ item: MediaItem) -> String {
        let type = item.isSeries ? "series" : (item.sourceType == .liveTV ? "tv" : "movie")
        if let imdb = item.contentID?.imdb, !imdb.isEmpty { return "\(type):imdb:\(imdb)" }
        if let tmdb = item.contentID?.tmdb, tmdb > 0 { return "\(type):tmdb:\(tmdb)" }
        let title = item.title.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        // Blank titles provide no evidence of a match.
        guard !title.isEmpty else { return "item:\(item.id)" }
        return "\(type):title:\(title):\(item.metadata.year.map(String.init) ?? "?")"
    }
}
