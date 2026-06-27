//
//  SMBShare.swift
//  FrameTV
//
//  A saved SMB share definition. The password is NOT stored here —
//  it lives in the Keychain, keyed by this share's id.
//

import Foundation

struct SMBShare: Identifiable, Codable, Hashable {
    var id: UUID
    var displayName: String
    var host: String
    var shareName: String
    var username: String
    var path: String?

    init(
        id: UUID = UUID(),
        displayName: String,
        host: String,
        shareName: String,
        username: String,
        path: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.host = host
        self.shareName = shareName
        self.username = username
        self.path = path
    }

    /// Keychain account string used to store/retrieve this share's password.
    var keychainAccount: String { "smb.\(id.uuidString)" }
}
