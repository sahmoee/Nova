//
//  SearchCorrector.swift
//  Astra
//
//  Generates lightweight alternative spellings for a search query, used to retry a
//  search that returned nothing. Remote (Apple TV) text entry is error-prone, so a
//  few cheap transformations — collapsing doubled letters, fixing common letter
//  swaps, trimming a stray trailing character — often turn a miss into a hit without
//  any network round-trip or dictionary.
//

import Foundation

enum SearchCorrector {

    /// Returns up to a few candidate corrections for a query, ordered most-likely
    /// first, excluding the original. Empty if nothing plausible.
    static func corrections(for query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3 else { return [] }

        var candidates: [String] = []

        // 1. Collapse runs of 3+ identical letters to 2, and doubled to single
        //    (handles "innterstellar" / "avengerss").
        candidates.append(collapseRepeats(q))

        // 2. Common adjacent-key and phonetic swaps.
        candidates.append(applySwaps(q))

        // 3. Drop a single stray trailing character (fat-fingered remote).
        if q.count > 4 { candidates.append(String(q.dropLast())) }

        // 4. Collapse all internal double letters to singles.
        candidates.append(singleizeDoubles(q))

        // De-duplicate, drop empties and the original (case-insensitive).
        var seen = Set<String>([q.lowercased()])
        var result: [String] = []
        for c in candidates {
            let trimmed = c.trimmingCharacters(in: .whitespaces)
            let key = trimmed.lowercased()
            if !trimmed.isEmpty, seen.insert(key).inserted {
                result.append(trimmed)
            }
        }
        return Array(result.prefix(3))
    }

    private static func collapseRepeats(_ s: String) -> String {
        var out = ""
        var lastTwo: [Character] = []
        for ch in s {
            if lastTwo.count == 2, lastTwo[0] == ch, lastTwo[1] == ch {
                continue   // already have two of these, skip a third+
            }
            out.append(ch)
            lastTwo.append(ch)
            if lastTwo.count > 2 { lastTwo.removeFirst() }
        }
        return out
    }

    private static func singleizeDoubles(_ s: String) -> String {
        var out = ""
        var prev: Character?
        for ch in s {
            if ch == prev, ch.isLetter { continue }
            out.append(ch)
            prev = ch
        }
        return out
    }

    /// A few common letter-swap corrections seen in remote typing.
    private static func applySwaps(_ s: String) -> String {
        var t = s
        let swaps: [(String, String)] = [
            ("ie", "ei"), ("ei", "ie"),   // receive/wierd-type swaps
            ("ph", "f"),                   // fonetic
            ("ous", "us"), ("us", "ous")
        ]
        // Apply only the first swap that changes the string, to avoid over-mangling.
        for (a, b) in swaps where t.range(of: a) != nil {
            let replaced = t.replacingOccurrences(of: a, with: b)
            if replaced != t { t = replaced; break }
        }
        return t
    }
}
