@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class RegionTest: UnitTest {
    func test_from_givenUppercaseString_expectGetRegion() {
        let given = Region.getRegion(from: "US")
        let expected = Region.US
        XCTAssertEqual(given, expected)
    }

    func test_from_givenLowercaseString_expectGetRegion() {
        let given = Region.getRegion(from: "eu")
        let expected = Region.EU
        XCTAssertEqual(given, expected)
    }

    func test_from_expectConvertToAndFromRegion() {
        let expected = Region.US
        let actual = Region.getRegion(from: Region.US.rawValue)
        XCTAssertEqual(expected, actual)
    }
}
