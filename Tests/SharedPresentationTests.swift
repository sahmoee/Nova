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

    private struct Fixture: View {
        @Environment(\.colorScheme) private var colorScheme
        var dark: Bool { colorScheme == .dark }
        var body: some View {
            SowensStatusView("Your library is empty", detail: "Add a source to begin.", symbol: "play.rectangle").softCard()
                .foregroundStyle(dark ? Color.white : Color.black)
                .background(dark ? Color(white: 0.075) : Color.white)
        }
    }
}
