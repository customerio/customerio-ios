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
        let expect: [Int] = Array(0 ..< 1000)
        var actual: [Int] = [] // we will add to this array in test, then compare the results

        let expectation = expectation(description: "Expect all background tasks to complete")
        expectation.expectedFulfillmentCount = expect.count

        for index in expect {
            util.queueOnBackground {
                actual.append(index)

                expectation.fulfill()
            }
        }

        waitForExpectations()

        XCTAssertEqual(expect, actual)
    }
}
