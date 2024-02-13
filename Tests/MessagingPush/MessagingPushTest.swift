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

        setupTest()
    }

    // MARK: initialize

    func test_initialize_expectOnlyAbleToInitializeOnce_expectInitializeThreadSafe() {
        // Run test multiple times to ensure thread safety. To try and catch a race condition, if one will exist.
        // I do not suggest running test < 100 times. When bugs existed because of not being thread safe, the test may have to run 50 times until it fails.
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

            waitForExpectations(1) // test may take up to 1 second to finish because it is running so many times. CI server is a less powerful machine and this test is flaky when we set wait() for < 1 second.

            XCTAssertEqual(automaticPushClickHandlingMock.startCallsCount, 1)
        }
    }

    func test_initialize_givenDefaultModuleConfigOptions_expectStartAutoPushClickHandling() {
        MessagingPush.initialize()

        XCTAssertEqual(automaticPushClickHandlingMock.startCallsCount, 1)
    }

    func test_initialize_givenCustomerDisabledAutoPushClickHandling_expectDoNotEnableFeature() {
        setupTest { config in
            config.autoTrackPushEvents = false
        }

        MessagingPush.initialize()

        XCTAssertFalse(automaticPushClickHandlingMock.startCalled)
    }
}

extension MessagignPushTest {
    func setupTest(modifySdkConfig: ((inout SdkConfig) -> Void)? = nil) {
        super.setUp(shouldInitializeModule: false, modifySdkConfig: modifySdkConfig)

        diGraph.override(value: automaticPushClickHandlingMock, forType: AutomaticPushClickHandling.self)
    }
}
