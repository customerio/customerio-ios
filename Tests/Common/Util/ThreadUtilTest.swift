@testable import Common
import Foundation
import SharedTests
import XCTest

class ThreadUtilTest: UnitTest {
    private var util: ThreadUtil!

    override func setUp() {
        super.setUp()

        util = CioThreadUtil()
    }

    // MARK: queueOnBackground

    // DispatchQueues in iOS can be serial or concurrent. Our codebase expects a serial behavior so this test is to assert the implementation runs that way.
    func test_queueOnBackground_expectQueueToBeSerial() {
        let expected: [Int] = Array(0 ..< 1000)
        var actual: [Int] = [] // we will add to this array in test, then compare the results

        let expect = expectation(description: "Expect all background tasks to complete")
        expect.expectedFulfillmentCount = expected.count

        for index in expected {
            util.queueOnBackground {
                actual.append(index)

                expect.fulfill()
            }
        }

        waitForExpectations()

        XCTAssertEqual(expected, actual)
    }
}
