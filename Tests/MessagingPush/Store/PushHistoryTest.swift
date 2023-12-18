@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class PushHistoryTest: IntegrationTest {
    private var pushHistory: PushHistoryImpl!

    override func setUp() {
        super.setUp()

        pushHistory = PushHistoryImpl(keyValueStorage: keyValueStorage, lockManager: lockManager)
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

    func test_hasHandledPush_expectPushHistorySizeIsLimited() {
        pushHistory.maxSizeOfHistory = 3

        let givenPushId1 = String.random
        let givenPushId2 = String.random
        let givenPushId3 = String.random
        let givenPushId4 = String.random

        // Check that push history is kept for 3 pushes.
        // If the function returns false and then true, we know the history was kept for that push to return "true" for the second call.
        XCTAssertFalse(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId1))
        XCTAssertTrue(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId1))

        XCTAssertFalse(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId2))
        XCTAssertTrue(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId2))

        XCTAssertFalse(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId3))
        XCTAssertTrue(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId3))

        XCTAssertFalse(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId4))
        XCTAssertTrue(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId4))

        // We expect that the 1st push is no longer in history. So, it should return false for the next call.
        XCTAssertFalse(pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: givenPushId1))
    }
}
