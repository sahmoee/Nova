import XCTest
@testable import Nova

final class WorkerConfigurationTests: XCTestCase {
    func testWorkerOriginRejectsUnsafeOrAmbiguousAddresses() {
        for address in ["http://example.com", "file:///tmp/private", "javascript:alert(1)",
                        "https://name:password@example.com", "https://example.com?token=secret",
                        "https://example.com#fragment", "not an address"] {
            XCTAssertNil(NovaWorkerConfiguration.baseURL(address), address)
        }
    }

    func testWorkerOriginDefaultsAndRetainsReverseProxyPath() {
        XCTAssertEqual(NovaWorkerConfiguration.baseURL(" \n")?.absoluteString,
                       NovaWorkerConfiguration.defaultBaseURL)
        XCTAssertEqual(NovaWorkerConfiguration.baseURL(" https://example.com:8443/nova/ \n")?.absoluteString,
                       "https://example.com:8443/nova/")
    }

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
