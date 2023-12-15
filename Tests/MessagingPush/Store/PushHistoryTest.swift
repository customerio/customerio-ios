@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class PushHistoryTest: IntegrationTest {
    private var pushHistory: PushHistoryImpl!

    override func setUp() {
        super.setUp()

        pushHistory = PushHistoryImpl(keyValueStorage: keyValueStorage, lockManager: lockManager)
        pushHistory.maxSizeOfHistory = 3 // make smaller number to make tests run faster and test edge cases
    }

    // MARK: hasHandledPush

    func test_hasHandledPush_givenPushNotHandled_expectFalse() {
        XCTAssertFalse(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: String.random))
    }

    func test_hasHandledPush_givenPushPreviouslyHandled_expectTrue() {
        let givenPushId = String.random

        // Handle push for first time
        XCTAssertFalse(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId))

        // Check that function returns true
        XCTAssertTrue(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId))
    }

    func test_hasHandledPush_givenUniquePushIds_expectEachPushHandledOnlyOnce() {
        let givenPushId1 = String.random
        let givenPushId2 = String.random
        let givenPushId3 = String.random

        // Handle push for first time
        XCTAssertFalse(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId1))
        XCTAssertFalse(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId2))
        XCTAssertFalse(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId3))

        // Check that function returns true
        XCTAssertTrue(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId1))
        XCTAssertTrue(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId2))
        XCTAssertTrue(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId3))
    }

    func test_hasHandledPush_givenSamePushId_givenUniquePushEvents_expectEachPushEventHandledOnce() {
        let givenPushId = String.random

        // Handle push for first time
        XCTAssertFalse(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId))
        XCTAssertFalse(pushHistory.hasHandledPush(pushEvent: .willPresent, pushId: givenPushId))

        // Check that function returns true
        XCTAssertTrue(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId))
        XCTAssertTrue(pushHistory.hasHandledPush(pushEvent: .willPresent, pushId: givenPushId))
    }
}
