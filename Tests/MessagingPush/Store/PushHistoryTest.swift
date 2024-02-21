@testable import CioInternalCommon
@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class PushHistoryTest: IntegrationTest {
    private var pushHistory: PushHistoryImpl!

    override func setUp() {
        super.setUp()

        pushHistory = PushHistoryImpl(lockManager: lockManager)
    }

    // MARK: hasHandledPush

    func test_hasHandledPush_givenPushNotHandled_expectFalse() {
        XCTAssertFalse(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: String.random, pushDeliveryDate: Date()))
    }

    func test_hasHandledPush_givenPushPreviouslyHandled_expectTrue() {
        let givenPushId = String.random
        let givenDate = Date().subtract(10, .minute)

        // Handle push for first time
        XCTAssertFalse(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId, pushDeliveryDate: givenDate))

        // Check that function returns true
        XCTAssertTrue(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId, pushDeliveryDate: givenDate))
    }

    func test_hasHandledPush_givenUniquePushIds_expectEachPushHandledOnlyOnce() {
        let givenPushId1 = String.random
        let givenPushId2 = String.random
        let givenPushId3 = String.random

        let givenDate = Date().subtract(10, .minute)

        // Handle push for first time
        XCTAssertFalse(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId1, pushDeliveryDate: givenDate))
        XCTAssertFalse(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId2, pushDeliveryDate: givenDate))
        XCTAssertFalse(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId3, pushDeliveryDate: givenDate))

        // Check that function returns true
        XCTAssertTrue(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId1, pushDeliveryDate: givenDate))
        XCTAssertTrue(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId2, pushDeliveryDate: givenDate))
        XCTAssertTrue(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId3, pushDeliveryDate: givenDate))
    }

    func test_hasHandledPush_givenUniqueDeliveryDates_expectEachPushHandledOnlyOnce() {
        let givenPushId = String.random

        let givenDate1 = Date().subtract(10, .minute)
        let givenDate2 = Date().subtract(5, .minute)
        let givenDate3 = Date().subtract(2, .minute)

        // Handle push for first time
        XCTAssertFalse(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId, pushDeliveryDate: givenDate1))
        XCTAssertFalse(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId, pushDeliveryDate: givenDate2))
        XCTAssertFalse(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId, pushDeliveryDate: givenDate3))

        // Check that function returns true
        XCTAssertTrue(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId, pushDeliveryDate: givenDate1))
        XCTAssertTrue(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId, pushDeliveryDate: givenDate2))
        XCTAssertTrue(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId, pushDeliveryDate: givenDate3))
    }

    func test_hasHandledPush_givenSamePushId_givenUniquePushEvents_expectEachPushEventHandledOnce() {
        // Tests that each push event has it's own set of history.
        // Make sure that all parameters except for the push event is the same.
        let givenPushId = String.random
        let givenDate = Date().subtract(10, .minute)

        // Handle push for first time
        XCTAssertFalse(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId, pushDeliveryDate: givenDate))
        XCTAssertFalse(pushHistory.hasHandledPush(pushEvent: .willPresent, pushId: givenPushId, pushDeliveryDate: givenDate))

        // Check that function returns true
        XCTAssertTrue(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId, pushDeliveryDate: givenDate))
        XCTAssertTrue(pushHistory.hasHandledPush(pushEvent: .willPresent, pushId: givenPushId, pushDeliveryDate: givenDate))
    }

    func test_hasHandledPush_expectThreadSafe() {
        runTest(numberOfTimes: 100) {
            let givenPushId = String.random
            let givenDate = Date().subtract(10, .minute)

            let expectBackgroundThreadCheckToComplete = expectation(description: "Background thread check should complete")

            // Handle push
            XCTAssertFalse(self.pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId, pushDeliveryDate: givenDate))

            // Assert that the push was handled when accessing from a different thread.
            runOnBackground {
                XCTAssertTrue(self.pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId, pushDeliveryDate: givenDate))

                expectBackgroundThreadCheckToComplete.fulfill()
            }

            waitForExpectations()
        }
    }
}
