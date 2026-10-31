import XCTest
import SwiftUI
import SowensKit
import SowensTestSupport
import SnapshotTesting
@testable import Nova

@MainActor
final class SharedPresentationTests: XCTestCase {
    func testProductionSurface() throws {
        // Keep every pixel accountable while allowing imperceptible GPU color rounding.
        // All other helper callers retain exact color matching by default.
        try assertSurfaceSnapshots(of: Fixture(), named: "surface", perceptualPrecision: 0.99)
    }

    #if os(iOS)
    func testPerceptualTolerancePreservesContentChecks() throws {
        func image(title: String = "Your library is empty", gray: Double = 64.0 / 255.0,
                   width: CGFloat = 240) throws -> UIImage {
            let renderer = ImageRenderer(content:
                Text(title).font(.headline).foregroundStyle(.white)
                    .frame(width: width, height: 80)
                    .background(Color(white: gray)))
            renderer.scale = 1
            return try XCTUnwrap(renderer.uiImage)
        }
        let baseline = try image()
        let rounding = try image(gray: 65.0 / 255.0)
        let tolerant = Diffing<UIImage>.image(precision: 1, perceptualPrecision: 0.99)
        let strict = Diffing<UIImage>.image(precision: 1, perceptualPrecision: 1)
        XCTAssertNil(tolerant.diffV2(baseline, rounding), "One-level renderer rounding should pass")
        XCTAssertNotNil(strict.diffV2(baseline, rounding), "Other callers keep strict defaults")
        XCTAssertNotNil(tolerant.diffV2(baseline, try image(title: "Different library content")))
        XCTAssertNotNil(tolerant.diffV2(baseline, try image(gray: 0.7)))
        XCTAssertNotNil(tolerant.diffV2(baseline, try image(width: 260)))
    }
    #endif

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
