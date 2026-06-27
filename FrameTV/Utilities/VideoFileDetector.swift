//
//  VideoFileDetector.swift
//  FrameTV
//
//  Centralizes the list of supported video extensions and detection logic.
//

import Foundation

enum VideoFileDetector {
    /// Extensions we treat as playable video containers.
    static let supportedExtensions: Set<String> = [
        "mp4", "m4v", "mov", "mkv", "avi", "webm"
    ]

    /// Returns true if the given filename has a supported video extension.
    static func isVideoFile(_ filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    /// Returns the lowercased extension, or nil if there isn't one.
    static func fileExtension(_ filename: String) -> String? {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ext.isEmpty ? nil : ext
    }
}
