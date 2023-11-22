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

    // MARK: hasHandledPushClick

    func test_hasHandledPushClick_givenNoPushesClicked_expectFalse() {
        XCTAssertFalse(pushHistory.hasHandledPushClick(deliveryId: .random))
    }

    func test_hasHandledPushClick_givenHasClickedOtherPushes_expectFalse() {
        pushHistory.handledPushClick(deliveryId: .random)

        XCTAssertFalse(pushHistory.hasHandledPushClick(deliveryId: .random))
    }

    func test_hasHandledPushClick_givenHasHandledThatPush_expectTrue() {
        let givenDeliveryId = String.random

        pushHistory.handledPushClick(deliveryId: givenDeliveryId)

        XCTAssertTrue(pushHistory.hasHandledPushClick(deliveryId: givenDeliveryId))
    }

    // MARK: handledPushClick

    func test_handledPushClick_expectMaintainHistoryOfLastPushesClicked() {
        let givenDeliveryId1 = String.random
        let givenDeliveryId2 = String.random
        let givenDeliveryId3 = String.random
        let givenDeliveryId4 = String.random

        pushHistory.handledPushClick(deliveryId: givenDeliveryId1)
        pushHistory.handledPushClick(deliveryId: givenDeliveryId2)
        pushHistory.handledPushClick(deliveryId: givenDeliveryId3)
        pushHistory.handledPushClick(deliveryId: givenDeliveryId4)

        XCTAssertEqual(pushHistory.lastPushesClicked, [givenDeliveryId2, givenDeliveryId3, givenDeliveryId4])
    }
}
