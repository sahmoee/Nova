import XCTest
import SwiftUI
import SowensKit
import SowensTestSupport
@testable import Nova

@MainActor
final class SharedPresentationTests: XCTestCase {
    func testProductionSurface() throws {
        try assertSurfaceSnapshots(of: Fixture(), named: "surface")
    }

    /// Nova pins `.preferredColorScheme(.dark)` at its scene root, so production never renders
    /// this surface light. Both snapshot variants must show that dark appearance; the light
    /// variant guards against the surface following the system appearance.
    private struct Fixture: View {
        var body: some View {
            SowensStatusView("Your library is empty", detail: "Add a source to begin.", symbol: "play.rectangle").softCard()
                .foregroundStyle(Color.white)
                .background(Color(white: 0.075))
                .environment(\.colorScheme, .dark)
        }
    }
}
