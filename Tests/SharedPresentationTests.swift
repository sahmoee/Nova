import XCTest
import SwiftUI
import SowensKit
import SowensTestSupport
import SnapshotTesting
@testable import Nova

@MainActor
final class SharedPresentationTests: XCTestCase {
    func testProductionSurface() throws {
        // Allow imperceptible GPU rounding and at most ~2–3 transparent fringe pixels.
        // All other helper callers retain exact color matching by default.
        try assertSurfaceSnapshots(of: Fixture(), named: "surface", pixelPrecision: 0.99998, perceptualPrecision: 0.99)
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
        let tolerant = Diffing<UIImage>.image(precision: 0.99998, perceptualPrecision: 0.99)
        let strict = Diffing<UIImage>.image(precision: 1, perceptualPrecision: 1)
        XCTAssertNil(tolerant.diffV2(baseline, rounding), "One-level renderer rounding should pass")
        XCTAssertNotNil(strict.diffV2(baseline, rounding), "Other callers keep strict defaults")
        XCTAssertNotNil(tolerant.diffV2(baseline, try image(title: "Different library content")))
        XCTAssertNotNil(tolerant.diffV2(baseline, try image(gray: 0.7)))
        XCTAssertNotNil(tolerant.diffV2(baseline, try image(width: 260)))

        // Match the observed 820px fixture's two alpha=1 antialias fringe pixels.
        func fringeImage(count: Int) throws -> UIImage {
            let width = 860, height = 213
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            for offset in 0..<count {
                let index = ((50 + offset * 20) * width + 840) * 4
                bytes[index] = 255; bytes[index + 1] = 255
                bytes[index + 2] = 255; bytes[index + 3] = 1
            }
            let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
            let cgImage = try XCTUnwrap(CGImage(width: width, height: height,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
            return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        }
        let clear = try fringeImage(count: 0)
        XCTAssertNil(tolerant.diffV2(try fringeImage(count: 2), clear))
        let allPixels = Diffing<UIImage>.image(precision: 1, perceptualPrecision: 0.99)
        XCTAssertNotNil(allPixels.diffV2(try fringeImage(count: 2), clear))
        XCTAssertNotNil(tolerant.diffV2(try fringeImage(count: 4), clear), "Fringe allowance stays below four pixels")
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
