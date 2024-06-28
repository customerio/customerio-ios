@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

class UIViewExtensionsTest: UnitTest {
    func test_getRootSuperview_givenNoSuperview_expectNil() {
        let givenView = UIView()

        XCTAssertNil(givenView.getRootSuperview())
    }

    func test_getRootSuperview_givenSuperview_expectSuperview() {
        let givenView = UIView()
        let givenSuperview = UIView()
        givenSuperview.addSubview(givenView)

        XCTAssertEqual(givenView.getRootSuperview(), givenSuperview)
    }

    func test_getRootSuperview_givenMultipleLevelsOfNesting_expectRootSuperview() {
        let givenView = UIView()
        let givenSuperview = UIView()
        let givenRootSuperview = UIView()
        givenSuperview.addSubview(givenView)
        givenRootSuperview.addSubview(givenSuperview)

        XCTAssertEqual(givenView.getRootSuperview(), givenRootSuperview)
    }
}
