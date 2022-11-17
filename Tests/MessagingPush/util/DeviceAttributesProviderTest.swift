@testable import CioMessagingPush
@testable import Common
import Foundation
import SharedTests
import XCTest

class DeviceAttributesProviderTest: UnitTest {
    private let deviceInfoMock = DeviceInfoMock()
    private let sdkConfigStoreMock = SdkConfigStoreMock()
    private let wrapperMockVersion = "1.2.0"
    private var provider: DeviceAttributesProvider!

    override func setUp() {
        super.setUp()

        provider = SdkDeviceAttributesProvider(sdkConfigStore: sdkConfigStoreMock, deviceInfo: deviceInfoMock)
    }

    private func enableTrackDeviceAttributesSdkConfig(_ enable: Bool) {
        var givenConfig = SdkConfig()
        givenConfig.autoTrackDeviceAttributes = enable
        sdkConfigStoreMock.underlyingConfig = givenConfig
    }
    private func setSDKWrapperConfig() {
        var givenConfig = SdkConfig()
        givenConfig._sdkWrapperConfig = SdkWrapperConfig(source: .reactNative, version: wrapperMockVersion )
        sdkConfigStoreMock.underlyingConfig = givenConfig
    }

    func test_getDefaultDeviceAttributes_givenTrackingDeviceAttributesDisabled_expectEmptyAttributes() {
        let expected: [String: String] = [:]
        enableTrackDeviceAttributesSdkConfig(false)

        let expect = expectation(description: "Expect to complete")
        provider.getDefaultDeviceAttributes { actual in
            XCTAssertEqual(actual as? [String: String], expected)

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
            XCTAssertEqual(actual as? [String: String], expected)

            expect.fulfill()
        }

        waitForExpectations()
    }
    func test_getDefaultDeviceAttributes_givenSDKWrapperConfig_expectWrapperVersionWithSomeAttributes() {
        let givenSdkVersion = wrapperMockVersion
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
        let givenWrapperSdkVersion = String.random
        deviceInfoMock.underlyingSdkVersion = givenSdkVersion
        deviceInfoMock.underlyingCustomerAppVersion = givenAppVersion
        deviceInfoMock.underlyingDeviceLocale = givenDeviceLocale
        deviceInfoMock.underlyingDeviceManufacturer = givenDeviceManufacturer
        deviceInfoMock.isPushSubscribedClosure = { onComplete in
            onComplete(true)
        }
        setSDKWrapperConfig()

        let expect = expectation(description: "Expect to complete")
        provider.getDefaultDeviceAttributes { actual in
            XCTAssertEqual(actual as? [String: String], expected)

            expect.fulfill()
        }

        waitForExpectations()
    }
}
