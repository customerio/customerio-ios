@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class CustomerIOAPIHttpRetryPolicyTest: UnitTest {
    private var policy: CustomerIOAPIHttpRetryPolicy!

    override func setUp() {
        super.setUp()

        policy = CustomerIOAPIHttpRetryPolicy()
    }

    // MARK: nextSleepTimeMilliseconds

    func test_nextSleepTimeMilliseconds_expectRetryAttemptsInCorrectOrder_expect6Retries() {
        let expected = CustomerIOAPIHttpRetryPolicy.retryPolicyMilliseconds
        var actual: [Milliseconds] = []

        var moreValuesToGet = true
        while moreValuesToGet {
            if let nextSleepTime = policy.nextSleepTimeMilliseconds {
                actual.append(nextSleepTime)
            } else {
                moreValuesToGet = false
            }
        }

        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.count, 6)
    }
}
