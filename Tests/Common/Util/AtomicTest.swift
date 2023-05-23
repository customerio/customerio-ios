@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class AtomicTest: UnitTest {
    @Atomic private var atomic: String!

    func test_givenCallSetWithNewValue_expectGetCallReceivesNewValue() {
        let expect = "new value"

        atomic = expect

        let actual = atomic

        XCTAssertEqual(expect, actual)
    }

    func test_givenSetAndGetDifferentThreads_expectGetNewlySetValue() {
        let expect = "new value"

        DispatchQueue.global(qos: .background).sync {
            atomic = expect
        }

        let actual = atomic

        XCTAssertEqual(expect, actual)
    }
}
