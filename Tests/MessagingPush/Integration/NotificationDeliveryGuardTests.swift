@_spi(Internal) @testable import CioMessagingPush
import Foundation
import XCTest

final class NotificationDeliveryGuardTests: XCTestCase {
    private final class Delivery {}

    func testBegin_givenActiveOrCompletedIdentity_thenRejectsRepeatedDelivery() {
        let guardUnderTest = NotificationDeliveryGuard<Delivery>()
        let delivery = Delivery()

        XCTAssertTrue(guardUnderTest.begin(delivery))
        XCTAssertFalse(guardUnderTest.begin(delivery))

        guardUnderTest.complete(delivery)

        XCTAssertFalse(guardUnderTest.begin(delivery))
    }

    func testBegin_givenCompletedDeliveryDeallocates_thenAcceptsNewDelivery() {
        let guardUnderTest = NotificationDeliveryGuard<Delivery>()
        weak var releasedDelivery: Delivery?

        autoreleasepool {
            let delivery = Delivery()
            releasedDelivery = delivery
            XCTAssertTrue(guardUnderTest.begin(delivery))
            guardUnderTest.complete(delivery)
        }

        XCTAssertNil(releasedDelivery)
        XCTAssertTrue(guardUnderTest.begin(Delivery()))
    }

    func testConcurrentBegin_givenOneDelivery_thenOnlyOneCallerWins() {
        let guardUnderTest = NotificationDeliveryGuard<Delivery>()
        let delivery = Delivery()
        let lock = NSLock()
        var acceptedCount = 0

        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            if guardUnderTest.begin(delivery) {
                lock.lock()
                acceptedCount += 1
                lock.unlock()
            }
        }

        XCTAssertEqual(acceptedCount, 1)
        guardUnderTest.complete(delivery)
    }
}
