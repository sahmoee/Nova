import SwiftUI

@main
struct MacPlatformChecks {
    @MainActor static func main() {
        precondition(PlatformCapabilities.platform == .iPad, "Mac uses the wide composition")
        precondition(PlatformCapabilities.navigationStyle == .sidebar, "Mac keeps native split navigation")
        precondition(!PlatformCapabilities.supports(.externalPlayers), "No iOS external URL handoff on Mac")
        precondition(!PlatformCapabilities.supports(.haptics))
        precondition(!PlatformCapabilities.supports(.widgets))
        precondition(!PlatformCapabilities.supports(.qrScanner))
        print("Passed 6 Mac platform capability checks")
    }
}
