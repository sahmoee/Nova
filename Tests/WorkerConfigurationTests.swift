import XCTest
@testable import Nova

final class WorkerConfigurationTests: XCTestCase {
    func testEndpointPreservesCustomDomainBasePath() throws {
        let base = try XCTUnwrap(URL(string: "https://api.example.com/nova"))
        let endpoint = NovaWorkerConfiguration.endpoint(
            base: base,
            path: NovaIdentifiers.WorkerPath.shareCreate
        )

        XCTAssertEqual(endpoint.absoluteString, "https://api.example.com/nova/share/create")
    }

    func testHealthEndpointUsesCanonicalRoute() throws {
        let base = try XCTUnwrap(URL(string: NovaWorkerConfiguration.exampleBaseURL))

        XCTAssertEqual(
            NovaWorkerConfiguration.healthEndpoint(base: base).absoluteString,
            "https://api.sowensstudios.com/nova/health"
        )
    }
}
