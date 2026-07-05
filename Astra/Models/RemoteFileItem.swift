//
//  RemoteFileItem.swift
//  Astra
//
//  Represents a file or folder discovered on a remote source (SMB, etc).
//

import Foundation

struct RemoteFileItem: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var path: String
    var isDirectory: Bool
    var size: Int64?
    var modifiedDate: Date?

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        isDirectory: Bool,
        size: Int64? = nil,
        modifiedDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedDate = modifiedDate
    }

    /// True when the file extension looks like a playable video container.
    var isPlayableVideo: Bool {
        guard !isDirectory else { return false }
        return VideoFileDetector.isVideoFile(name)
    }
}
