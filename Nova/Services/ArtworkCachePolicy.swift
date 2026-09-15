import Foundation
import CryptoKit

/// Pure request identity and allocation limits, shared by loader and view state.
enum ArtworkCachePolicy {
    static let maximumDownloadBytes = 25 * 1024 * 1024
    static func pixels(_ requested: CGFloat) -> Int {
        guard requested.isFinite, requested > 0 else { return 600 }
        return Int(min(4096, max(64, requested)).rounded(.up))
    }
    static func key(url: URL, pixels: Int) -> String {
        let value = url.absoluteString + "\u{0}" + String(pixels)
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func decodedCost(width: Int, height: Int) -> Int? {
        guard width > 0, height > 0, width <= 4096, height <= 4096 else { return nil }
        return width * height * 4
    }
}
