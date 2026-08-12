@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
@testable import SharedTests
import XCTest

class GistCommonHeadersTest: UnitTest {
    private let deviceInfoStub = DeviceInfoStub()
    private let state = InAppMessageState(
        siteId: "test-site",
        dataCenter: "US",
        environment: .production,
        userId: "user123",
        anonymousId: nil
    )

    private func builder(source: String = "iOS", sdkVersion: String = "1.2.3") -> GistCommonHeaders {
        GistCommonHeaders(
            sdkClient: CustomerIOSdkClient(source: source, sdkVersion: sdkVersion),
            deviceInfo: deviceInfoStub
        )
    }

    // Wrapper SDKs override `SdkClient` to change the platform header. The app identifier
    // comes from the host bundle instead, so it must stay put across every source.
    func test_headers_givenWrapperSources_expectPlatformVariesAndAppIdentifierDoesNot() {
        deviceInfoStub.customerBundleId = "com.example.wrapperapp"
        let expectedPlatforms = [
            "iOS": "ios-apple",
            "Flutter": "flutter-apple",
            "ReactNative": "reactnative-apple",
            "Expo": "expo-apple"
        ]

        for (source, expectedPlatform) in expectedPlatforms {
            let headers = builder(source: source).headers(state: state)

            XCTAssertEqual(headers["X-CIO-Client-Platform"], expectedPlatform, "source: \(source)")
            XCTAssertEqual(headers["X-CIO-App-Identifier"], "com.example.wrapperapp", "source: \(source)")
        }
    }

    func test_headers_givenSdkClient_expectSiteAndVersionHeaders() {
        let headers = builder(sdkVersion: "4.7.3").headers(state: state)

        XCTAssertEqual(headers["X-CIO-Site-Id"], "test-site")
        XCTAssertEqual(headers["X-CIO-Datacenter"], "US")
        XCTAssertEqual(headers["X-CIO-Client-Version"], "4.7.3")
    }

    // The queue fetch and the SSE connect both build from this set, so an added or renamed
    // key here changes both transports.
    func test_headers_expectOnlyCommonHeaders() {
        let headers = builder().headers(state: state)

        XCTAssertEqual(Set(headers.keys), [
            "X-CIO-Site-Id",
            "X-CIO-Datacenter",
            "X-CIO-Client-Platform",
            "X-CIO-Client-Version",
            "X-CIO-App-Identifier"
        ])
    }
}
