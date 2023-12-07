@testable import CioInternalCommon
@testable import CioMessagingPush
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class MessagignPushTest: IntegrationTest {
    private let automaticPushClickHandlingMock = AutomaticPushClickHandlingMock()

    override func setUp() {
        super.setUp()

        diGraph.override(value: automaticPushClickHandlingMock, forType: AutomaticPushClickHandling.self)

        MessagingPush.resetSharedInstance()
    }

    // MARK: initialize

    func test_initialize_expectOnlyAbleToInitializeOnce_expectInitializeThreadSafe() {
        runTest(numberOfTimes: 500) {
            let expectAllThreadsToComplete = expectation(description: "All threads should complete")
            expectAllThreadsToComplete.expectedFulfillmentCount = 2

            CioThreadUtil().runBackground {
                MessagingPush.initialize()

                expectAllThreadsToComplete.fulfill()
            }

            CioThreadUtil().runBackground {
                MessagingPush.initialize()

                expectAllThreadsToComplete.fulfill()
            }

            waitForExpectations()

            XCTAssertEqual(automaticPushClickHandlingMock.startCallsCount, 1)
        }
    }
}
