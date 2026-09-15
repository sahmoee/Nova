import Foundation

enum LibraryFilePolicy {
    static let maximumLibraryBytes = 128 * 1_024 * 1_024
    static let maximumCollectionsBytes = 8 * 1_024 * 1_024

    enum Failure: LocalizedError {
        case invalidFile, tooLarge, recoveryRequired
        var errorDescription: String? {
            switch self {
            case .invalidFile: return "The saved library file cannot be read. Its original data has been kept."
            case .tooLarge: return "The saved library exceeds the supported file size. Its original data has been kept."
            case .recoveryRequired: return "The saved library needs recovery. Restore a valid backup or explicitly reset this data before saving changes."
            }
        }
    }

    static func read(_ url: URL, maximumBytes: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.invalidFile }
        guard let size = values.fileSize, size <= maximumBytes else { throw Failure.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw Failure.tooLarge }
        return data
    }

    static func write(_ data: Data, to url: URL, maximumBytes: Int) throws {
        guard data.count <= maximumBytes else { throw Failure.tooLarge }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
