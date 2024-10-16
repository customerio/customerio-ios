@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class UserAgentUtilTest: UnitTest {
    private let deviceInfoMock = DeviceInfoMock()
    private let sdkClientMock = SdkClientMock()

    private var userAgentUtil: UserAgentUtil! {
        diGraphShared.userAgentUtil
    }

    override func setUpDependencies() {
        super.setUpDependencies()

        diGraphShared.override(value: deviceInfoMock, forType: DeviceInfo.self)
        diGraphShared.override(value: sdkClientMock, forType: SdkClient.self)
    }

    // MARK: getUserAgentHeaderValue

    func test_getUserAgent_givenDeviceInfoNotAvailable_expectShortUserAgent() {
        let expected = "Customer.io iOS Client/1.0.1"
        deviceInfoMock.underlyingDeviceModel = nil
        sdkClientMock.underlyingSource = "iOS"
        sdkClientMock.underlyingSdkVersion = "1.0.1"

        let actual = userAgentUtil.getUserAgentHeaderValue()

        XCTAssertEqual(expected, actual)
    }

    func test_getUserAgent_givenDeviceInfoAvailable_expectLongUserAgent() {
        let expected = "Customer.io iOS Client/1.0.1 (iPhone12; iOS 14.1) io.customer.superawesomestore/3.4.5"
        deviceInfoMock.underlyingDeviceModel = "iPhone12"
        deviceInfoMock.underlyingOsVersion = "14.1"
        deviceInfoMock.underlyingOsName = "iOS"
        deviceInfoMock.underlyingCustomerAppName = "SuperAwesomeStore"
        deviceInfoMock.underlyingCustomerBundleId = "io.customer.superawesomestore"
        deviceInfoMock.underlyingCustomerAppVersion = "3.4.5"
        sdkClientMock.underlyingSource = deviceInfoMock.underlyingOsName
        sdkClientMock.underlyingSdkVersion = "1.0.1"

        let actual = userAgentUtil.getUserAgentHeaderValue()

        XCTAssertEqual(expected, actual)
    }

    func test_getUserAgent_givenDeviceInfoAvailable_expectLongVisonOsUserAgent() {
        let expected = "Customer.io visionOS Client/3.0.1 (Apple Vision Pro; visionOS 1.1) io.customer.visionos-sample-app.VisionOS/1.0"
        deviceInfoMock.underlyingDeviceModel = "Apple Vision Pro"
        deviceInfoMock.underlyingOsVersion = "1.1"
        deviceInfoMock.underlyingOsName = "visionOS"
        deviceInfoMock.underlyingCustomerAppName = "VisionOS"
        deviceInfoMock.underlyingCustomerBundleId = "io.customer.visionos-sample-app.VisionOS"
        deviceInfoMock.underlyingCustomerAppVersion = "1.0"
        sdkClientMock.underlyingSource = deviceInfoMock.underlyingOsName
        sdkClientMock.underlyingSdkVersion = "3.0.1"

        let actual = userAgentUtil.getUserAgentHeaderValue()

        XCTAssertEqual(expected, actual)
    }

    func test_getUserAgent_givenDeviceInfoAvailable_expectLongReactNativeUserAgent() {
        let expected = "Customer.io React Native Client/1.0.1 (iPhone12; iOS 14.1) io.customer.superawesomestore/3.4.5"
        deviceInfoMock.underlyingDeviceModel = "iPhone12"
        deviceInfoMock.underlyingOsVersion = "14.1"
        deviceInfoMock.underlyingOsName = "iOS"
        deviceInfoMock.underlyingCustomerAppName = "SuperAwesomeStore"
        deviceInfoMock.underlyingCustomerBundleId = "io.customer.superawesomestore"
        deviceInfoMock.underlyingCustomerAppVersion = "3.4.5"
        sdkClientMock.underlyingSource = "React Native"
        sdkClientMock.underlyingSdkVersion = "1.0.1"

        let actual = userAgentUtil.getUserAgentHeaderValue()

        XCTAssertEqual(expected, actual)
    }

    func test_getUserAgent_givenDeviceInfoAvailable_expectLongNSEUserAgent() {
        let expected = "Customer.io NSE Client/\(SdkVersion.version) (iPhone14; iOS 15.3) io.customer.nse/2.0.3"
        deviceInfoMock.underlyingDeviceModel = "iPhone14"
        deviceInfoMock.underlyingOsVersion = "15.3"
        deviceInfoMock.underlyingOsName = "iOS"
        deviceInfoMock.underlyingCustomerAppName = "NSEPush"
        deviceInfoMock.underlyingCustomerBundleId = "io.customer.nse"
        deviceInfoMock.underlyingCustomerAppVersion = "2.0.3"

        let actual = userAgentUtil.getNSEUserAgentHeaderValue()

        XCTAssertEqual(expected, actual)
    }
}
