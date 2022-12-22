@testable import CioMessagingPush
@testable import Common
import Foundation
import SharedTests
import XCTest

class DeviceAttributesProviderTest: UnitTest {
    private let deviceInfoMock = DeviceInfoMock()
    private let sdkConfigStoreMock = SdkConfigStoreMock()
    private let wrapperMockVersion = "1.2.0"
    private var provider: SdkDeviceAttributesProvider!
    private var sdkConfig: SdkConfig {
        get {
            sdkConfigStoreMock.underlyingConfig!
        }
        set {
            sdkConfigStoreMock.underlyingConfig = newValue
        }
    }
    override func setUp() {
        super.setUp()
        sdkConfigStoreMock.underlyingConfig = SdkConfig() // reset SDK config to a new instance before test
        provider = SdkDeviceAttributesProvider(sdkConfigStore: sdkConfigStoreMock, deviceInfo: deviceInfoMock)
    }
    private func setUp(useSdkWrapper: Bool = false, enableTrackDeviceAttributes: Bool = true) {
        setUp()
        if useSdkWrapper {
            sdkConfig._sdkWrapperConfig = SdkWrapperConfig(source: .reactNative, version: wrapperMockVersion)
        }
        sdkConfig.autoTrackDeviceAttributes = enableTrackDeviceAttributes
    }
    func test_getDefaultDeviceAttributes_givenTrackingDeviceAttributesDisabled_expectEmptyAttributes() {
        let expected: [String: String] = [:]
        setUp(enableTrackDeviceAttributes: false)
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
        setUp(enableTrackDeviceAttributes: true)
        let expect = expectation(description: "Expect to complete")
        provider.getDefaultDeviceAttributes { actual in
            XCTAssertEqual(actual as? [String: String], expected)
            expect.fulfill()
        }
        waitForExpectations()
    }
    func test_getSdkVersionAttribute_givenNotUsingSdkWrapper_expectGetSDKVersion() {
        setUp(useSdkWrapper: false)
        let givenSdkVersion = String.random
        deviceInfoMock.underlyingSdkVersion = givenSdkVersion
        XCTAssertEqual(provider.getSdkVersionAttribute(), givenSdkVersion)
    }
    func test_getSdkVersionAttribute_expectSDKWrapperVersionOverridesSDKVersion() {
        setUp(useSdkWrapper: true)
        deviceInfoMock.underlyingSdkVersion = String.random
        XCTAssertEqual(provider.getSdkVersionAttribute(), wrapperMockVersion)
    }
}
