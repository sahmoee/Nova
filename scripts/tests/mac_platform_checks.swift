import SwiftUI

@main
struct MacPlatformChecks {
    @MainActor static func main() {
        #if os(macOS)
        precondition(PlatformCapabilities.platform == .mac, "Native Mac platform identity")
        precondition(PlatformCapabilities.supports(.multiColumnNavigation))
        #else
        precondition(PlatformCapabilities.platform == .iPad, "Mac uses the wide composition")
        #endif
        precondition(PlatformCapabilities.navigationStyle == .sidebar, "Mac keeps native split navigation")
        precondition(!PlatformCapabilities.supports(.externalPlayers), "No iOS external URL handoff on Mac")
        precondition(!PlatformCapabilities.supports(.haptics))
        precondition(!PlatformCapabilities.supports(.widgets))
        precondition(!PlatformCapabilities.supports(.qrScanner))
        #if os(macOS)
        print("Passed 7 native Mac platform capability checks")
        #else
        print("Passed 6 Mac platform capability checks")
        #endif
    }
}
