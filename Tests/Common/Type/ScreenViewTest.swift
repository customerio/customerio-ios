@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class ScreenViewTest: UnitTest {
    func test_getScreenView_givenNamesWithMatchingCase_expectCorrectScreenView() {
        let screenViewAnalytics = ScreenView.getScreenView("All")
        let screenViewInApp = ScreenView.getScreenView("InApp")

        XCTAssertEqual(screenViewAnalytics, .all)
        XCTAssertEqual(screenViewInApp, .inApp)
    }

    func test_getScreenView_givenNamesWithDifferentCase_expectCorrectScreenView() {
        let screenViewAnalytics = ScreenView.getScreenView("all")
        let screenViewInApp = ScreenView.getScreenView("inapp")

        XCTAssertEqual(screenViewAnalytics, .all)
        XCTAssertEqual(screenViewInApp, .inApp)
    }

    func test_getScreenView_givenInvalidValue_expectFallbackScreenView() {
        let parsedValue = ScreenView.getScreenView("none")

        XCTAssertEqual(parsedValue, .all)
    }

    func test_getScreenView_givenEmptyValue_expectFallbackScreenView() {
        let parsedValue = ScreenView.getScreenView("", fallback: .inApp)

        XCTAssertEqual(parsedValue, .inApp)
    }

    func test_getScreenView_givenNil_expectFallbackScreenView() {
        let parsedValue = ScreenView.getScreenView(nil)

        XCTAssertEqual(parsedValue, .all)
    }
}
