@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class DeviceInfoTest: UnitTest {
    private var deviceInfo: CIODeviceInfo!

    override func setUp() {
        super.setUp()

        deviceInfo = CIODeviceInfo()
    }

    func test_deviceLocale_expectDashes() {
        let actual = deviceInfo.deviceLocale

        // Regex tests that format is "X-X" instead of "X_X"
        // https://regexr.com/6i6io
        XCTAssertMatches(actual, regex: #"\w+-\w+"#)
    }
}
