import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
import XCTest

class QueueFetchCoordinatorTest: XCTestCase {
    private var sut: QueueFetchCoordinator!

    override func setUp() {
        super.setUp()
        sut = QueueFetchCoordinator()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    private func key(userId: String? = nil, anonymousId: String? = nil) -> QueueFetchKey {
        QueueFetchKey(state: InAppMessageState(userId: userId, anonymousId: anonymousId))!
    }

    // MARK: - QueueFetchKey

    func test_key_givenUserIdAndAnonymousId_expectUserIdentity() {
        let key = QueueFetchKey(state: InAppMessageState(userId: "user-1", anonymousId: "anon-1"))

        XCTAssertEqual(key?.userToken, "user-1")
        XCTAssertEqual(key?.isAnonymous, false)
    }

    func test_key_givenBlankUserId_expectAnonymousIdentity() {
        let key = QueueFetchKey(state: InAppMessageState(userId: "  ", anonymousId: "anon-1"))

        XCTAssertEqual(key?.userToken, "anon-1")
        XCTAssertEqual(key?.isAnonymous, true)
    }

    func test_key_givenNoUsableIdentifier_expectNil() {
        XCTAssertNil(QueueFetchKey(state: InAppMessageState()))
        XCTAssertNil(QueueFetchKey(state: InAppMessageState(userId: "", anonymousId: " ")))
    }

    // MARK: - Sharing an in-flight request

    func test_begin_givenNothingInFlight_expectTicket() {
        XCTAssertNotNil(sut.begin(key: key(anonymousId: "anon-1"), mustBeFresh: false))
    }

    func test_begin_givenSameIdentityInFlight_expectShared() {
        let anon = key(anonymousId: "anon-1")
        _ = sut.begin(key: anon, mustBeFresh: false)

        XCTAssertNil(sut.begin(key: anon, mustBeFresh: false))
        XCTAssertNil(sut.begin(key: anon, mustBeFresh: true))
    }

    func test_begin_givenPreviousRequestFinished_expectNewTicket() {
        let anon = key(anonymousId: "anon-1")
        let first = sut.begin(key: anon, mustBeFresh: false)!
        _ = sut.finish(first)

        let second = sut.begin(key: anon, mustBeFresh: false)

        XCTAssertNotNil(second)
        XCTAssertNotEqual(second, first)
    }

    func test_begin_givenConcurrentCallersForSameIdentity_expectSingleTicket() {
        let anon = key(anonymousId: "anon-1")
        let tickets = CioInternalCommon.Synchronized<[QueueFetchCoordinator.Ticket]>([])

        DispatchQueue.concurrentPerform(iterations: 100) { index in
            if let ticket = sut.begin(key: anon, mustBeFresh: index.isMultiple(of: 2)) {
                tickets.mutating { $0.append(ticket) }
            }
        }

        XCTAssertEqual(tickets.wrappedValue.count, 1)
    }

    // MARK: - Callers that need newer data

    func test_finish_givenOnlyCallersThatAcceptSharedData_expectNoRefetch() {
        let anon = key(anonymousId: "anon-1")
        let ticket = sut.begin(key: anon, mustBeFresh: false)!
        _ = sut.begin(key: anon, mustBeFresh: false)

        XCTAssertFalse(sut.finish(ticket))
    }

    func test_finish_givenCallersThatNeedNewerData_expectOneRefetch() {
        let anon = key(anonymousId: "anon-1")
        let ticket = sut.begin(key: anon, mustBeFresh: false)!
        _ = sut.begin(key: anon, mustBeFresh: true)
        _ = sut.begin(key: anon, mustBeFresh: true)

        XCTAssertTrue(sut.finish(ticket))

        // The follow-up is a fresh request: owing nothing once it finishes.
        let followUp = sut.begin(key: anon, mustBeFresh: false)!
        XCTAssertFalse(sut.finish(followUp))
    }

    func test_finish_givenFirstCallerNeededNewerData_expectNoRefetch() {
        // The request was started by the caller that needed newer data, so it already satisfies it.
        let ticket = sut.begin(key: key(anonymousId: "anon-1"), mustBeFresh: true)!

        XCTAssertFalse(sut.finish(ticket))
    }

    // MARK: - Identity changes

    func test_begin_givenDifferentIdentityInFlight_expectNewTicket() {
        _ = sut.begin(key: key(anonymousId: "anon-1"), mustBeFresh: false)

        XCTAssertNotNil(sut.begin(key: key(userId: "user-1"), mustBeFresh: false))
    }

    func test_finish_givenRequestReplacedByNewIdentity_expectOldTicketCannotReleaseSlot() {
        let user = key(userId: "user-1")
        let anonTicket = sut.begin(key: key(anonymousId: "anon-1"), mustBeFresh: false)!
        let userTicket = sut.begin(key: user, mustBeFresh: false)!

        XCTAssertFalse(sut.finish(anonTicket))
        // The identified user's request is still in flight, so it is still shared.
        XCTAssertNil(sut.begin(key: user, mustBeFresh: false))

        _ = sut.finish(userTicket)
        XCTAssertNotNil(sut.begin(key: user, mustBeFresh: false))
    }

    func test_finish_givenRefetchOwedToPreviousIdentity_expectNotCarriedOver() {
        let anon = key(anonymousId: "anon-1")
        _ = sut.begin(key: anon, mustBeFresh: false)
        _ = sut.begin(key: anon, mustBeFresh: true)

        let userTicket = sut.begin(key: key(userId: "user-1"), mustBeFresh: false)!

        XCTAssertFalse(sut.finish(userTicket))
    }

    func test_begin_givenIdentitySwitchesBackWhileInFlight_expectOldTicketCannotReleaseSlot() {
        let anon = key(anonymousId: "anon-1")
        let firstAnon = sut.begin(key: anon, mustBeFresh: false)!
        _ = sut.begin(key: key(userId: "user-1"), mustBeFresh: false)
        let secondAnon = sut.begin(key: anon, mustBeFresh: false)!

        // The first anonymous request finishing late must not free the slot the second one holds.
        XCTAssertFalse(sut.finish(firstAnon))
        XCTAssertNil(sut.begin(key: anon, mustBeFresh: false))

        _ = sut.finish(secondAnon)
        XCTAssertNotNil(sut.begin(key: anon, mustBeFresh: false))
    }
}
