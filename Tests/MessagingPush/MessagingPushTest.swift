@testable import CioInternalCommon
@testable import CioMessagingPush
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class MessagignPushTest: IntegrationTest {
    private let automaticPushClickHandlingMock = AutomaticPushClickHandlingMock()

    override func setUp() {
        super.setUp(shouldInitializeModule: false) // we manually initialize module in test functions.

        diGraph.override(value: automaticPushClickHandlingMock, forType: AutomaticPushClickHandling.self)
    }

    // MARK: initialize

    func test_initialize_expectOnlyAbleToInitializeOnce_expectInitializeThreadSafe() {
        // Run test multiple times to ensure thread safety. To try and catch a race condition, if one will exist.
        runTest(numberOfTimes: 100) {
            let expectAllThreadsToComplete = expectation(description: "All threads should complete")
            expectAllThreadsToComplete.expectedFulfillmentCount = 2

            runOnBackground {
                MessagingPush.initialize()

                expectAllThreadsToComplete.fulfill()
            }

            runOnBackground {
                MessagingPush.initialize()

                expectAllThreadsToComplete.fulfill()
            }

            waitForExpectations()

            XCTAssertEqual(automaticPushClickHandlingMock.startCallsCount, 1)
        }
    }

    func test_initialize_givenDefaultModuleConfigOptions_expectStartAutoPushClickHandling() {
        MessagingPush.initialize()

        XCTAssertEqual(automaticPushClickHandlingMock.startCallsCount, 1)
    }

    func test_initialize_givenCustomerDisabledAutoPushClickHandling_expectDoNotEnableFeature() {
        var givenModuleConfig = MessagingPushConfigOptions()
        givenModuleConfig.autoPushClickHandling = false

        MessagingPush.initialize(config: givenModuleConfig)

        XCTAssertFalse(automaticPushClickHandlingMock.startCalled)
    }
}
