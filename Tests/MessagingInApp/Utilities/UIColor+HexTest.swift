@testable import CioMessagingInApp

import UIKit
import XCTest

class UIColorFromHexTests: UnitTest {
    func test_parseColor_givenInputColorIsNull_expectNullAsResult() {
        let result = UIColor.fromHex(nil)

        XCTAssertNil(result)
    }

    func test_parseColor_givenInputColorIsEmpty_expectNullAsResult() {
        let result = UIColor.fromHex("")

        XCTAssertNil(result)
    }

    func test_parseColor_givenInputColorHasUnexpectedCharCount_expectNullAsResult() {
        // Only colors with 6 or 8 chars are accepted
        XCTAssertNil(UIColor.fromHex("#"))
        XCTAssertNil(UIColor.fromHex("#FF11F"))
        XCTAssertNil(UIColor.fromHex("#FF11FF1"))
    }

    func test_parseColor_givenInputColorWithNonHexChars_expectNullResult() {
        XCTAssertNil(UIColor.fromHex("#MMXXMMYY"))
    }

    func test_parseColor_givenValidInputColorWithoutAlpha_expectCorrectResult() {
        let result = UIColor.fromHex("#007AFF") // R:0, G:122, B:255

        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        result?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        XCTAssertEqual(red, 0.0, accuracy: 0.01)
        XCTAssertEqual(green, 0.48, accuracy: 0.01)
        XCTAssertEqual(blue, 1.00, accuracy: 0.01)
        XCTAssertEqual(alpha, 1.0, "Alpha should be 1.0 for 6-character hex.")
    }

    func test_parseColor_givenValidInputColorWithoutHashAndWithoutAlpha_expectCorrectResult() {
        let result = UIColor.fromHex("007AFF") // R:0, G:122, B:255

        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        result?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        XCTAssertEqual(red, 0.0, accuracy: 0.01)
        XCTAssertEqual(green, 0.48, accuracy: 0.01)
        XCTAssertEqual(blue, 1.00, accuracy: 0.01)
        XCTAssertEqual(alpha, 1.0, "Alpha should be 1.0 for 6-character hex.")
    }

    func test_parseColor_givenValidInputColorWithAlpha_expectCorrectResult() {
        let result = UIColor.fromHex("#007AFF80") // R:0, G:122, B:255, Alpha:50%

        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        result?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        XCTAssertEqual(red, 0.0, accuracy: 0.01)
        XCTAssertEqual(green, 0.48, accuracy: 0.01)
        XCTAssertEqual(blue, 1.00, accuracy: 0.01)
        XCTAssertEqual(alpha, 0.5, accuracy: 0.01)
    }

    func test_parseColor_givenValidInputColorWithoutHashAndWithAlpha_expectCorrectResult() {
        let result = UIColor.fromHex("007AFF80") // R:0, G:122, B:255, Alpha:50%

        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        result?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        XCTAssertEqual(red, 0.0, accuracy: 0.01)
        XCTAssertEqual(green, 0.48, accuracy: 0.01)
        XCTAssertEqual(blue, 1.00, accuracy: 0.01)
        XCTAssertEqual(alpha, 0.5, accuracy: 0.01)
    }
}
