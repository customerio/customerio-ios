@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class CustomerIOAPIHttpRetryPolicyTest: UnitTest {
    private var policy: CustomerIOAPIHttpRetryPolicy!

    override func setUp() {
        super.setUp()

        policy = CustomerIOAPIHttpRetryPolicy()
    }

    // MARK: nextSleepTime

    func test_nextSleepTime_expectRetryAttemptsInCorrectOrder_expect6Retries() {
        let expected = CustomerIOAPIHttpRetryPolicy.retryPolicy
        var actual: [Seconds] = []

        var moreValuesToGet = true
        while moreValuesToGet {
            if let nextSleepTime = policy.nextSleepTime {
                actual.append(nextSleepTime)
            } else {
                moreValuesToGet = false
            }
        }

        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.count, 6)
    }
}
