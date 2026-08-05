//
//  NovaOnDeviceAI.swift
//  Nova
//
//  On-device intelligence via Apple's Foundation Models framework
//  (Apple Intelligence, iOS 26+, eligible hardware).
//
//  ─────────────────────────────────────────────────────────────────────────
//  READ THIS FIRST: Nova ships to Apple TV
//  ─────────────────────────────────────────────────────────────────────────
//  The Nova-tvOS target compiles the same Swift sources as Nova-iOS, and
//  Apple Intelligence does not exist on tvOS. Every on-device path in this app
//  must therefore be ADDITIVE and DUAL-PATH — the Worker call stays, always, for
//  Apple TV and for iPhones that aren't Apple Intelligence-capable.
//
//  This whole file is behind `#if !os(tvOS) && canImport(FoundationModels)`, and
//  the public surface still exists on tvOS as a permanently-unavailable stub, so
//  call sites never need their own `#if`. That is the only structure that keeps
//  a shared codebase honest across two platforms with different capabilities.
//
//  ─────────────────────────────────────────────────────────────────────────
//  What goes on-device, and why these three
//  ─────────────────────────────────────────────────────────────────────────
//  Nova's Worker is a title-recommendation engine, and title recommendation is
//  the one thing that must NOT move: naming real, TMDB-resolvable films needs
//  broad, current world knowledge, and worker/src/index.ts explicitly instructs the model
//  to "never invent titles". A 3B local model will invent titles. `/titles`
//  stays cloud, unconditionally.
//
//  But three of Nova's "smart" features are hand-written keyword heuristics
//  that were never good enough to justify a network call — and the Worker even
//  has endpoints for two of them that the app has never once called, because a
//  round trip was the wrong shape for the interaction:
//
//   1. Stream filter (StreamFilterParser.swift, 104 lines of keyword matching).
//      Re-parses on EVERY KEYSTROKE. A network call was never viable — which is
//      exactly why the Worker's /filter endpoint has sat unused. Small
//      structured output, zero world knowledge, perfect local fit.
//
//   2. Title cleanup (LibraryEnricher.aiCleanTitle).
//      Today: one 20-second-timeout POST PER LIBRARY ITEM, sequentially. A
//      500-item library is 500 round trips and 500 charges against the user's
//      own Anthropic key, to turn a release filename into a title. Local, free,
//      offline, and not rate-limited.
//
//   3. Playback troubleshooting (PlaybackFailureReason.classify).
//      The failure is frequently *caused by* a bad network, so phoning home to
//      explain a network error is self-defeating. The Worker's /troubleshoot
//      endpoint is likewise unused. Local produces the same
//      {cause, advice, suggestedAction} shape with no network at all.
//
//  Library search is a strong fourth candidate — the data being searched is
//  already fully on-device, and today the query is shipped to Claude to guess
//  titles that are then string-matched back locally. `searchLibrary` below
//  covers it.
//
//  Self-contained: Foundation + FoundationModels only. See "Wiring".
//
//  NOT COMPILED HERE — see the Verification note.
//

import Foundation
import os

#if !os(tvOS) && canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Public value types

/// Mirrors the Worker's `/filter` response and Nova's own `ParsedStreamFilter`.
struct OnDeviceStreamFilter: Sendable, Equatable {
    var minQuality: String?      // "480p" | "720p" | "1080p" | "2160p"
    var maxSizeGB: Double?
    var cachedOnly: Bool
    var language: String?
    var codecPreferred: String?  // "h264" | "h265" | "av1"
    var hdrOnly: Bool

    static let empty = OnDeviceStreamFilter(
        minQuality: nil, maxSizeGB: nil, cachedOnly: false,
        language: nil, codecPreferred: nil, hdrOnly: false
    )
}

/// Mirrors the Worker's `/troubleshoot` response.
struct OnDeviceTroubleshootAdvice: Sendable {
    let cause: String
    let advice: String
    /// One of: retry, pickAnotherStream, checkNetwork, checkDebrid,
    /// lowerQuality, updateApp, none.
    let suggestedAction: String
}

enum NovaOnDeviceError: LocalizedError {
    case unavailable(String)
    case emptyInput
    case guardrail
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let why): return why
        case .emptyInput: return "Nothing to interpret."
        case .guardrail: return "Apple Intelligence declined that request."
        case .failed(let message): return message
        }
    }
}

// MARK: - Entry point

enum NovaOnDeviceAI {

    private static let log = Logger(subsystem: "com.nova.app", category: "OnDeviceAI")

    /// False on Apple TV, always. Safe to call from shared code on any platform.
    static var isAvailable: Bool {
        #if !os(tvOS) && canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
        #else
        return false
        #endif
    }

    static var unavailableReason: String? {
        #if os(tvOS)
        return "Apple Intelligence isn't available on Apple TV."
        #elseif canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in Settings for offline smart filters."
        case .unavailable(.modelNotReady): return "Apple Intelligence is still downloading its model."
        case .unavailable: return "Apple Intelligence isn't available right now."
        }
        #else
        return "This build wasn't compiled with Apple Intelligence support."
        #endif
    }

    // MARK: 1. Stream filter

    /// Parse a free-text stream filter ("1080p or better, under 5 gigs, cached").
    ///
    /// Called on every keystroke, so it is debounced by the caller and returns
    /// `.empty` rather than throwing on an unusable phrase — a filter box that
    /// throws an error at you mid-typing is worse than one that does nothing.
    static func parseStreamFilter(_ phrase: String) async -> OnDeviceStreamFilter? {
        let clean = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 3, isAvailable else { return nil }

        #if !os(tvOS) && canImport(FoundationModels)
        do {
            return try await FoundationModelsNova.parseFilter(clean)
        } catch {
            log.debug("on-device filter parse failed: \(error.localizedDescription, privacy: .public)")
            return nil          // caller falls back to StreamFilterParser
        }
        #else
        return nil
        #endif
    }

    // MARK: 2. Title cleanup

    /// Turn a release filename into a clean title + year.
    ///
    /// Batched on purpose: `LibraryEnricher` today issues one HTTP request per
    /// item. One local session handling a batch is both faster and easier on the
    /// device than N sessions, and it lets the model use the batch as context —
    /// a library is usually internally consistent about naming.
    static func cleanTitles(_ filenames: [String], batchSize: Int = 20) async -> [String: String] {
        guard isAvailable, !filenames.isEmpty else { return [:] }

        #if !os(tvOS) && canImport(FoundationModels)
        var out: [String: String] = [:]
        for batch in stride(from: 0, to: filenames.count, by: batchSize).map({
            Array(filenames[$0 ..< min($0 + batchSize, filenames.count)])
        }) {
            do {
                let cleaned = try await FoundationModelsNova.cleanTitles(batch)
                out.merge(cleaned) { current, _ in current }
            } catch {
                // One bad batch must not abandon the enrichment run — the caller
                // falls back to MetadataParser.cleanTitle for whatever is missing.
                log.debug("on-device title batch failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return out
        #else
        return [:]
        #endif
    }

    // MARK: 3. Playback troubleshooting

    /// Explain a playback failure. Deliberately usable with no network, which is
    /// the whole point — the most common cause of the failure is the network.
    static func troubleshoot(
        errorText: String,
        context: String?
    ) async throws -> OnDeviceTroubleshootAdvice {
        let clean = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw NovaOnDeviceError.emptyInput }
        guard isAvailable else {
            throw NovaOnDeviceError.unavailable(unavailableReason ?? "Apple Intelligence is unavailable.")
        }

        #if !os(tvOS) && canImport(FoundationModels)
        return try await FoundationModelsNova.troubleshoot(errorText: clean, context: context)
        #else
        throw NovaOnDeviceError.unavailable("Apple Intelligence isn't available in this build.")
        #endif
    }

    // MARK: 4. Library search

    /// Rank the user's OWN library against a natural-language phrase.
    ///
    /// Note what this does not do: it never proposes a title. It only chooses
    /// from `titles`, which the device already holds. That constraint is what
    /// makes it safe on a small model — it cannot hallucinate a film that isn't
    /// in your library, because it is picking from a list.
    static func searchLibrary(_ phrase: String, titles: [String], limit: Int = 24) async -> [String] {
        let clean = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2, !titles.isEmpty, isAvailable else { return [] }

        #if !os(tvOS) && canImport(FoundationModels)
        do {
            // Cap the candidate list so a 2,000-title library still fits the
            // context window. Alphabetical order is arbitrary but stable, which
            // matters more than cleverness for a fallback path.
            let candidates = titles.count > 200 ? Array(titles.sorted().prefix(200)) : titles
            let picked = try await FoundationModelsNova.searchLibrary(clean, titles: candidates)
            // Only ever return strings that were in the input.
            let allowed = Set(candidates)
            return picked.filter { allowed.contains($0) }.prefix(limit).map { $0 }
        } catch {
            log.debug("on-device library search failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        #else
        return []
        #endif
    }
}

// MARK: - Foundation Models

#if !os(tvOS) && canImport(FoundationModels)

private enum FoundationModelsNova {

    // MARK: Filter

    @Generable
    struct Filter {
        @Guide(description: "Lowest acceptable resolution: 480p, 720p, 1080p or 2160p. Empty string if not mentioned.")
        var minQuality: String
        @Guide(description: "Largest acceptable file size in gigabytes. Use 0 if not mentioned.", .range(0...200))
        var maxSizeGB: Double
        @Guide(description: "True only if the user asked for cached or instant streams.")
        var cachedOnly: Bool
        @Guide(description: "A language name or code if the user asked for one, otherwise an empty string.")
        var language: String
        @Guide(description: "Preferred codec: h264, h265 or av1. Empty string if not mentioned.")
        var codecPreferred: String
        @Guide(description: "True only if the user asked for HDR, Dolby Vision or HDR10.")
        var hdrOnly: Bool
    }

    static func parseFilter(_ phrase: String) async throws -> OnDeviceStreamFilter {
        let session = LanguageModelSession(instructions: """
        You turn a short phrase about video streams into filter settings.

        Only set a field the user actually asked for. Leaving a field empty is \
        always better than guessing — an invented filter silently hides streams \
        the user wanted.

        "4k" and "uhd" mean 2160p. "hd" means 1080p. "x265", "hevc" mean h265. \
        "small", "light" is about size, not quality.
        """)

        let response = try await session.respond(to: phrase, generating: Filter.self)
        let content = response.content

        let qualities = ["480p", "720p", "1080p", "2160p"]
        let codecs = ["h264", "h265", "av1"]
        let quality = content.minQuality.lowercased().trimmingCharacters(in: .whitespaces)
        let codec = content.codecPreferred.lowercased().trimmingCharacters(in: .whitespaces)
        let language = content.language.trimmingCharacters(in: .whitespaces)

        return OnDeviceStreamFilter(
            minQuality: qualities.contains(quality) ? quality : nil,
            maxSizeGB: content.maxSizeGB > 0 ? content.maxSizeGB : nil,
            cachedOnly: content.cachedOnly,
            language: language.isEmpty ? nil : language,
            codecPreferred: codecs.contains(codec) ? codec : nil,
            hdrOnly: content.hdrOnly
        )
    }

    // MARK: Titles

    @Generable
    struct CleanTitle {
        @Guide(description: "The filename exactly as given.")
        var original: String
        @Guide(description: "The title a person would recognise, with the year in brackets when the filename contains one. For example 'The Matrix (1999)'.")
        var cleaned: String
    }

    @Generable
    struct CleanTitles {
        @Guide(description: "One entry for every filename given, in the same order.")
        var titles: [CleanTitle]
    }

    static func cleanTitles(_ filenames: [String]) async throws -> [String: String] {
        let session = LanguageModelSession(instructions: """
        You turn scene-release filenames into readable titles.

        Strip resolution, source, codec, audio tags, release group names, \
        brackets, dots and underscores. Keep the year if it is there. Keep season \
        and episode markers in a readable form: S01E04 becomes 'S1 E4'.

        Do not translate. Do not correct a title to what you think the real film \
        is called — return what the filename says, cleanly. If a filename is \
        unreadable, return it unchanged.
        """)

        let prompt = "FILENAMES:\n" + filenames.map { "- \($0)" }.joined(separator: "\n")
        let response = try await session.respond(to: prompt, generating: CleanTitles.self)

        var out: [String: String] = [:]
        let valid = Set(filenames)
        for entry in response.content.titles {
            let original = entry.original.trimmingCharacters(in: .whitespaces)
            let cleaned = entry.cleaned.trimmingCharacters(in: .whitespaces)
            // Only accept results that map back to a filename we actually sent.
            guard valid.contains(original), !cleaned.isEmpty else { continue }
            out[original] = cleaned
        }
        return out
    }

    // MARK: Troubleshoot

    @Generable
    struct Advice {
        @Guide(description: "What most likely went wrong, in one plain sentence with no jargon.")
        var cause: String
        @Guide(description: "What to try, in one or two sentences. Be concrete.")
        var advice: String
        @Guide(description: "One of: retry, pickAnotherStream, checkNetwork, checkDebrid, lowerQuality, updateApp, none.")
        var suggestedAction: String
    }

    static func troubleshoot(errorText: String, context: String?) async throws -> OnDeviceTroubleshootAdvice {
        let session = LanguageModelSession(instructions: """
        You explain video playback failures to someone who is not technical.

        Be honest about uncertainty — "this usually means…" is better than a \
        confident wrong diagnosis. Never blame the user. Never suggest anything \
        that would lose their place or their library.

        suggestedAction must be exactly one of: retry, pickAnotherStream, \
        checkNetwork, checkDebrid, lowerQuality, updateApp, none.
        """)

        var prompt = "ERROR:\n\(errorText)"
        if let context, !context.isEmpty { prompt += "\n\nWHAT WAS PLAYING:\n\(context)" }

        do {
            let response = try await session.respond(to: prompt, generating: Advice.self)
            let content = response.content
            let allowed = ["retry", "pickAnotherStream", "checkNetwork", "checkDebrid", "lowerQuality", "updateApp", "none"]
            let action = content.suggestedAction.trimmingCharacters(in: .whitespaces)
            return OnDeviceTroubleshootAdvice(
                cause: content.cause.trimmingCharacters(in: .whitespaces),
                advice: content.advice.trimmingCharacters(in: .whitespaces),
                suggestedAction: allowed.contains(action) ? action : "none"
            )
        } catch let error as LanguageModelSession.GenerationError {
            throw mapError(error)
        } catch {
            throw NovaOnDeviceError.failed(error.localizedDescription)
        }
    }

    // MARK: Library search

    @Generable
    struct Matches {
        @Guide(description: "Titles copied EXACTLY from the LIBRARY list, best match first. Return none if nothing fits.")
        var titles: [String]
    }

    static func searchLibrary(_ phrase: String, titles: [String]) async throws -> [String] {
        let session = LanguageModelSession(instructions: """
        You pick titles from a person's own media library that match what they \
        described.

        Copy titles EXACTLY as they appear in the list. Never write a title that \
        is not in the list, even if you are sure they would like it — this is a \
        search of what they already own, not a recommendation.

        Order by how well each fits. Return nothing rather than padding with \
        weak matches.
        """)

        let prompt = "LIBRARY:\n" + titles.map { "- \($0)" }.joined(separator: "\n") + "\n\nTHEY WANT:\n\(phrase)"
        let response = try await session.respond(to: prompt, generating: Matches.self)
        return response.content.titles.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func mapError(_ error: LanguageModelSession.GenerationError) -> NovaOnDeviceError {
        switch error {
        case .guardrailViolation: return .guardrail
        case .assetsUnavailable: return .unavailable("Apple Intelligence is still preparing.")
        default: return .failed(error.localizedDescription)
        }
    }
}

#endif

// MARK: - Wiring
//
// 1. StreamPickerView.swift:414 / :436 — try on-device, keep the keyword parser:
//
//        if let smart = await NovaOnDeviceAI.parseStreamFilter(text) {
//            apply(smart)
//        } else {
//            apply(StreamFilterParser.parse(text))     // unchanged, tvOS path
//        }
//
//    Debounce ~300ms. Do not await this on the main actor in `onChange`.
//
// 2. LibraryEnricher.swift:76-95 — replace the per-item POST with one batched
//    local pass, and keep both existing fallbacks:
//
//        let cleaned = await NovaOnDeviceAI.cleanTitles(items.map(\.filename))
//        for item in items {
//            item.title = cleaned[item.filename]
//                      ?? (useAI ? await aiCleanTitle(item.filename) : nil)   // Worker
//                      ?? MetadataParser.cleanTitle(item.filename)            // local regex
//        }
//
//    This is the change with the clearest user-visible win: enrichment goes from
//    minutes of sequential network calls to seconds, and stops spending the
//    user's own Anthropic budget on filename tidying.
//
// 3. PlayerView.swift:157 — on-device advice, `PlaybackFailureReason.classify`
//    as the tvOS and non-eligible-device path.
//
// 4. AISearchService.swift `searchLibrary` — on-device first, `localKeywordMatch`
//    behind it. Leave `/titles` alone.
//
// 5. AISearchSettingsView.swift — show `NovaOnDeviceAI.unavailableReason` so
//    an Apple TV user understands why the toggle isn't there, rather than
//    thinking the feature is broken.
//
// Do NOT route /titles, /share/create or /share/fetch here.
//
// MARK: - Verification
//
// Brace/paren balance checked programmatically. Written against Apple's
// published Foundation Models API.
//
// NOT COMPILED and NOT run on hardware. Real tests, in order of what is most
// likely to break:
//   1. **Build the tvOS target.** That is the whole risk of this file. The
//      `#if !os(tvOS)` fencing must hold, and every call site must still compile
//      with `isAvailable` hard-coded false.
//   2. Clean iOS build.
//   3. On an Apple Intelligence-capable iPhone in Airplane Mode: type "4k under
//      8 gigs cached" into the stream filter and confirm it parses; force a
//      playback failure and confirm advice appears with no network.
