@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class UserAgentUtilTest: UnitTest {
    private let deviceInfoMock = DeviceInfoMock()
    private var userAgentUtil: UserAgentUtil!

    override func setUp() {
        super.setUp()

        userAgentUtil = UserAgentUtilImpl(deviceInfo: deviceInfoMock)
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
}
