@testable import CioMessagingPush
@testable import Common
import Foundation
import SharedTests
import XCTest

class DeviceAttributesProviderTest: UnitTest {
    private let deviceInfoMock = DeviceInfoMock()
    private let sdkConfigStoreMock = SdkConfigStoreMock()

    private var provider: DeviceAttributesProvider!

    override func setUp() {
        super.setUp()

        diGraph.override(.deviceInfo, value: deviceInfoMock, forType: DeviceInfo.self)
        diGraph.override(.sdkConfigStore, value: sdkConfigStoreMock, forType: SdkConfigStore.self)

        provider = SdkDeviceAttributesProvider(diGraph: diGraph)
    }

    private func enableTrackDeviceAttributesSdkConfig(_ enable: Bool) {
        var givenConfig = SdkConfig()
        givenConfig.autoTrackDeviceAttributes = enable
        sdkConfigStoreMock.underlyingConfig = givenConfig
    }

    func test_getDefaultDeviceAttributes_givenTrackingDeviceAttributesDisabled_expectEmptyAttributes() {
        let expected: [String: String] = [:]
        enableTrackDeviceAttributesSdkConfig(false)

        let expect = expectation(description: "Expect to complete")
        provider.getDefaultDeviceAttributes { actual in
            XCTAssertEqual(actual as! [String: String], expected)

            expect.fulfill()
        }

        waitForExpectations()

        XCTAssertFalse(deviceInfoMock.mockCalled)
    }

    func test_getDefaultDeviceAttributes_givenTrackingDeviceAttributesEnabled_expectGetSomeAttributes() {
        let givenSdkVersion = String.random
        let givenAppVersion = String.random
        let givenDeviceLocale = String.random
        let givenDeviceManufacturer = String.random
        let expected = [
            "cio_sdk_version": givenSdkVersion,
            "app_version": givenAppVersion,
            "device_locale": givenDeviceLocale,
            "push_enabled": "true",
            "device_manufacturer": givenDeviceManufacturer
        ]
        deviceInfoMock.underlyingSdkVersion = givenSdkVersion
        deviceInfoMock.underlyingCustomerAppVersion = givenAppVersion
        deviceInfoMock.underlyingDeviceLocale = givenDeviceLocale
        deviceInfoMock.underlyingDeviceManufacturer = givenDeviceManufacturer
        deviceInfoMock.isPushSubscribedClosure = { onComplete in
            onComplete(true)
        }
        enableTrackDeviceAttributesSdkConfig(true)

        let expect = expectation(description: "Expect to complete")
        provider.getDefaultDeviceAttributes { actual in
            XCTAssertEqual(actual as! [String: String], expected)

            expect.fulfill()
        }

        waitForExpectations()
    }
}
