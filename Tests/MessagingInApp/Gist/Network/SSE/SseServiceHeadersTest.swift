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

        XCTAssertEqual(headers["X-CIO-App-Identifier"], "io.customer.superawesomestore")
        XCTAssertEqual(headers["X-Gist-User-Anonymous"], "false")
        XCTAssertNil(headers["X-Gist-Encoded-User-Token"])
    }
}
