//
//  LanguageNames.swift
//  Astra
//
//  Maps subtitle language codes to display names. Handles the common 2- and
//  3-letter codes addons and OpenSubtitles use, falling back to Locale.
//

import Foundation

enum LanguageNames {

    /// A few 3-letter to readable mappings that Locale doesn't always resolve
    /// nicely from the bare code.
    private static let overrides: [String: String] = [
        "eng": "English", "en": "English",
        "spa": "Spanish", "es": "Spanish",
        "fre": "French", "fra": "French", "fr": "French",
        "ger": "German", "deu": "German", "de": "German",
        "ita": "Italian", "it": "Italian",
        "por": "Portuguese", "pt": "Portuguese", "pob": "Portuguese (BR)",
        "rus": "Russian", "ru": "Russian",
        "jpn": "Japanese", "ja": "Japanese",
        "kor": "Korean", "ko": "Korean",
        "chi": "Chinese", "zho": "Chinese", "zh": "Chinese",
        "ara": "Arabic", "ar": "Arabic",
        "dut": "Dutch", "nld": "Dutch", "nl": "Dutch",
        "pol": "Polish", "pl": "Polish",
        "tur": "Turkish", "tr": "Turkish",
        "swe": "Swedish", "sv": "Swedish",
        "und": "Unknown"
    ]

    static func display(for code: String) -> String {
        let key = code.lowercased()
        if let mapped = overrides[key] { return mapped }
        // Try Locale resolution for anything else.
        if let name = Locale.current.localizedString(forLanguageCode: key) {
            return name.capitalized
        }
        return code.uppercased()
    }
}
