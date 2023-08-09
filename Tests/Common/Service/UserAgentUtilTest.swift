@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class UserAgentUtilTest: UnitTest {
    private let deviceInfoMock = DeviceInfoMock()
    private var sdkWrapperConfig: SdkWrapperConfig?

    private var userAgentUtil: UserAgentUtil!

    // Call this in your test function if you want to attach a SdkWrapper.
    func setUp(sdkWrapperConfig: SdkWrapperConfig) {
        self.sdkWrapperConfig = sdkWrapperConfig

        setUp()
    }

    override func tearDown() {
        super.tearDown()

        sdkWrapperConfig = nil
    }

    override func setUp() {
        super.setUp { config in
            config._sdkWrapperConfig = self.sdkWrapperConfig
        }

        userAgentUtil = UserAgentUtilImpl(deviceInfo: deviceInfoMock, sdkConfig: sdkConfig)
    }

    // MARK: getUserAgentHeaderValue

    func test_getUserAgent_givenDeviceInfoNotAvailable_expectShortUserAgent() {
        let expected = "Customer.io iOS Client/1.0.1"
        deviceInfoMock.underlyingSdkVersion = "1.0.1"
        deviceInfoMock.underlyingDeviceModel = nil

        let actual = userAgentUtil.getUserAgentHeaderValue()

        XCTAssertEqual(expected, actual)
    }

    func test_getUserAgent_givenDeviceInfoAvailable_expectLongUserAgent() {
        let expected = "Customer.io iOS Client/1.0.1 (iPhone12; iOS 14.1) io.customer.superawesomestore/3.4.5"
        deviceInfoMock.underlyingSdkVersion = "1.0.1"
        deviceInfoMock.underlyingDeviceModel = "iPhone12"
        deviceInfoMock.underlyingOsVersion = "14.1"
        deviceInfoMock.underlyingOsName = "iOS"
        deviceInfoMock.underlyingCustomerAppName = "SuperAwesomeStore"
        deviceInfoMock.underlyingCustomerBundleId = "io.customer.superawesomestore"
        deviceInfoMock.underlyingCustomerAppVersion = "3.4.5"

        let actual = userAgentUtil.getUserAgentHeaderValue()

        XCTAssertEqual(expected, actual)
    }

    func test_getUserAgent_givenSdkWrapperConfig_expectModifiedUserAgentForWrapper() {
        let givenWrapperVersion = "2.0.0"
        let givenSdkVersion = "1.0.0" // make sure this value is different from the given wrapper value
        setUp(sdkWrapperConfig: SdkWrapperConfig(source: .reactNative, version: givenWrapperVersion))

        let expected = "Customer.io ReactNative Client/2.0.0 (iPhone12; iOS 14.1) io.customer.superawesomestore/3.4.5"
        deviceInfoMock.underlyingSdkVersion = givenSdkVersion
        deviceInfoMock.underlyingDeviceModel = "iPhone12"
        deviceInfoMock.underlyingOsVersion = "14.1"
        deviceInfoMock.underlyingOsName = "iOS"
        deviceInfoMock.underlyingCustomerAppName = "SuperAwesomeStore"
        deviceInfoMock.underlyingCustomerBundleId = "io.customer.superawesomestore"
        deviceInfoMock.underlyingCustomerAppVersion = "3.4.5"

        let actual = userAgentUtil.getUserAgentHeaderValue()

        XCTAssertEqual(expected, actual)
    }
}
