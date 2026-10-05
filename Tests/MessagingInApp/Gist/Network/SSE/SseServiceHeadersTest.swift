@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
@testable import SharedTests
import XCTest

class SseServiceHeadersTest: UnitTest {
    private let deviceInfoStub = DeviceInfoStub()
    private let state = InAppMessageState(
        siteId: "test-site",
        dataCenter: "US",
        environment: .production,
        userId: "user123",
        anonymousId: nil
    )

    override func setUp() {
        super.setUp()
        deviceInfoStub.customerBundleId = "io.customer.superawesomestore"
        diGraphShared.override(value: deviceInfoStub, forType: DeviceInfo.self)
    }

    func test_buildHeaders_expectAppIdentifierAlongsideAnonymousFlag() async {
        let sut = SseService(logger: diGraphShared.logger)

        let headers = await sut.buildHeaders(state: state)

        XCTAssertEqual(headers["X-CIO-Client-App-Identifier"], "io.customer.superawesomestore")
        XCTAssertEqual(headers["X-Gist-User-Anonymous"], "false")
        XCTAssertNil(headers["X-Gist-Encoded-User-Token"])
    }

    func test_buildSseUrl_givenSiteId_expectSiteIdQuery() async throws {
        let sut = SseService(logger: diGraphShared.logger)

        let url = await sut.buildSseUrl(state: state, identifier: "user123")
        let query = try XCTUnwrap(url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems })

        XCTAssertEqual(query.map(\.name), ["sessionId", "siteId", "userToken"])
        XCTAssertEqual(query.first { $0.name == "siteId" }?.value, "test-site")
    }

    func test_buildSseUrl_givenPublicKeyAndNoSiteId_expectKeyQuery() async throws {
        let sut = SseService(logger: diGraphShared.logger)
        let state = InAppMessageState(publicKey: "wk_us_abc", dataCenter: "US", userId: "user123")

        let url = await sut.buildSseUrl(state: state, identifier: "user123")
        let query = try XCTUnwrap(url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems })

        XCTAssertEqual(query.map(\.name), ["sessionId", "key", "userToken"])
        XCTAssertEqual(query.first { $0.name == "key" }?.value, "wk_us_abc")
    }
}
