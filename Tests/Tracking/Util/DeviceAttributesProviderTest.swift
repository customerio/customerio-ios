@testable import CioInternalCommon
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class DeviceAttributesProviderTest: UnitTest {
    private let deviceInfoMock = DeviceInfoMock()

    private var provider: SdkDeviceAttributesProvider!

    func test_getDefaultDeviceAttributes_givenTrackingDeviceAttributesDisabled_expectEmptyAttributes() {
        let expected: [String: String] = [:]
        setupTest(autoTrackDeviceAttributes: false)

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
        setupTest(autoTrackDeviceAttributes: true)

        let expect = expectation(description: "Expect to complete")
        provider.getDefaultDeviceAttributes { actual in
            XCTAssertEqual(actual as? [String: String], expected)

            expect.fulfill()
        }

        waitForExpectations()
    }

    func test_getSdkVersionAttribute_givenNotUsingSdkWrapper_expectGetSDKVersion() {
        setupTest(sdkWrapper: nil)
        let givenSdkVersion = String.random
        deviceInfoMock.underlyingSdkVersion = givenSdkVersion

        XCTAssertEqual(provider.getSdkVersionAttribute(), givenSdkVersion)
    }

    func test_getSdkVersionAttribute_expectSDKWrapperVersionOverridesSDKVersion() {
        let givenWrapperSdkVersion = String.random
        let givenSdkVersion = String.random
        setupTest(sdkWrapper: SdkWrapperConfig(source: .reactNative, version: givenWrapperSdkVersion))
        deviceInfoMock.underlyingSdkVersion = givenSdkVersion

        XCTAssertEqual(provider.getSdkVersionAttribute(), givenWrapperSdkVersion)
    }
}

extension DeviceAttributesProviderTest {
    func setupTest(autoTrackDeviceAttributes: Bool = false, sdkWrapper: SdkWrapperConfig? = nil) {
        super.setUp(modifySdkConfig: { config in
            config.autoTrackDeviceAttributes = autoTrackDeviceAttributes
            config._sdkWrapperConfig = sdkWrapper
        })

        provider = SdkDeviceAttributesProvider(sdkConfig: sdkConfig, deviceInfo: deviceInfoMock)
    }
}
