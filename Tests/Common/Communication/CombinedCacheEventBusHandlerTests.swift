@testable import CioInternalCommonMocks
import SharedTests
import XCTest

@testable import CioInternalCommon

class CombinedCacheEventBusHandlerTest: UnitTest {
    var mockEventStorage = EventStorageMock()

    override func setUp() {
        super.setUp()
        mockCollection.add(mocks: [mockEventStorage])
        mockEventStorage.loadEventsReturnValue = []
    }

    private func makeHandler() -> CombinedCacheEventBusHandler {
        CombinedCacheEventBusHandler(eventStorage: mockEventStorage, logger: log)
    }

    // MARK: - postEventAndWait

    func test_postEventAndWait_givenNoObservers_expectEventStoredOnDisk() async {
        let handler = makeHandler()

        await handler.postEventAndWait(ProfileIdentifiedEvent(identifier: "user-1"))

        XCTAssertEqual(mockEventStorage.storeCallsCount, 1)
    }

    func test_postEventAndWait_givenNoObservers_expectNoStoreErrorPropagated() async {
        mockEventStorage.storeThrowableError = NSError(domain: "test", code: 1)
        let handler = makeHandler()

        // Should not throw or crash; errors are absorbed and logged.
        await handler.postEventAndWait(ProfileIdentifiedEvent(identifier: "user-1"))
    }

    // MARK: - addObserver replay

    func test_addObserver_givenEventCachedBeforeRegistration_expectEventReplayed() async {
        let handler = makeHandler()
        let event = ProfileIdentifiedEvent(identifier: "historic")

        // Post with no observers → event enters in-memory cache (and disk).
        await handler.postEventAndWait(event)

        let replayed = XCTestExpectation(description: "event replayed to late observer")
        handler.addObserver(ProfileIdentifiedEvent.self) { received in
            if received.identifier == event.identifier { replayed.fulfill() }
        }

        await fulfillment(of: [replayed], timeout: 5.0)
    }

    func test_addObserver_givenEventReplayed_expectRemovedFromPersistentStorage() async {
        let handler = makeHandler()
        await handler.postEventAndWait(ProfileIdentifiedEvent(identifier: "user-1"))

        let replayed = XCTestExpectation(description: "event replayed")
        handler.addObserver(ProfileIdentifiedEvent.self) { _ in replayed.fulfill() }
        await fulfillment(of: [replayed], timeout: 5.0)

        XCTAssertEqual(mockEventStorage.removeCallsCount, 1)
    }

    func test_addObserver_givenMultipleObserversRegisteredAfterPost_expectBothGetHistory() async {
        let handler = makeHandler()
        let event = ProfileIdentifiedEvent(identifier: "shared")
        await handler.postEventAndWait(event)

        let replayedA = XCTestExpectation(description: "observer A replayed")
        let replayedB = XCTestExpectation(description: "observer B replayed")

        handler.addObserver(ProfileIdentifiedEvent.self) { received in
            if received.identifier == event.identifier { replayedA.fulfill() }
        }
        handler.addObserver(ProfileIdentifiedEvent.self) { received in
            if received.identifier == event.identifier { replayedB.fulfill() }
        }

        await fulfillment(of: [replayedA, replayedB], timeout: 5.0)
    }

    // MARK: - No duplicate delivery (the core race condition fix)

    func test_noDuplicateDelivery_givenPostThenObserverRegistration_expectSingleDelivery() async {
        let handler = makeHandler()
        let event = ProfileIdentifiedEvent(identifier: "once")

        await handler.postEventAndWait(event)

        var deliveryCount = 0
        let delivered = XCTestExpectation(description: "delivered")
        delivered.assertForOverFulfill = true

        handler.addObserver(ProfileIdentifiedEvent.self) { received in
            if received.identifier == event.identifier {
                deliveryCount += 1
                delivered.fulfill()
            }
        }

        await fulfillment(of: [delivered], timeout: 5.0)
        XCTAssertEqual(deliveryCount, 1, "event must be delivered exactly once")
    }

    func test_noDuplicateDelivery_givenConcurrentPostAndObserverRegistration_expectSingleDelivery() async {
        // Stress test: run many iterations to surface timing-dependent duplicates.
        // NOTE: deliveryCount is intentionally absent to avoid a data race (TSAN). Instead,
        // assertForOverFulfill detects duplicate delivery in a thread-safe way.
        for iteration in 0 ..< 20 {
            let handler = makeHandler()
            let event = ProfileIdentifiedEvent(identifier: "iter-\(iteration)")

            let delivered = XCTestExpectation(description: "delivered-\(iteration)")
            delivered.assertForOverFulfill = true

            // Race: register and post concurrently.
            async let posting: Void = handler.postEventAndWait(event)
            handler.addObserver(ProfileIdentifiedEvent.self) { received in
                if received.identifier == event.identifier {
                    delivered.fulfill()
                }
            }
            await posting

            await fulfillment(of: [delivered], timeout: 5.0)
        }
    }

    // MARK: - loadEventsFromStorage

    func test_loadEventsFromStorage_expectEventsSeededAndReplayed() async {
        let event = ProfileIdentifiedEvent(identifier: "persisted")
        mockEventStorage.loadEventsClosure = { key in
            key == ProfileIdentifiedEvent.key ? [event] : []
        }

        let handler = makeHandler()
        // Explicitly await loading so the cache is populated before the observer registers.
        // This avoids a race with the background Task launched in init.
        await handler.loadEventsFromStorage()

        let replayed = XCTestExpectation(description: "persisted event replayed to new observer")
        handler.addObserver(ProfileIdentifiedEvent.self) { received in
            if received.identifier == event.identifier { replayed.fulfill() }
        }

        await fulfillment(of: [replayed], timeout: 5.0)
    }

    func test_initialization_givenStorageThrows_expectNoObserversAndNoHang() async {
        mockEventStorage.loadEventsThrowableError = NSError(domain: "io", code: 2)
        let handler = makeHandler()

        // Wait long enough for loadEventsFromStorage to attempt all event types.
        try? await Task.sleep(nanoseconds: 200000000)

        // Posting after a failed load should still work gracefully.
        await handler.postEventAndWait(ProfileIdentifiedEvent(identifier: "fallback"))
        XCTAssertEqual(mockEventStorage.storeCallsCount, 1)
    }

    // MARK: - removeObserver

    func test_removeObserver_givenObserverRemoved_expectNoDeliveryAfterRemoval() async {
        let handler = makeHandler()
        var received = false

        // Register and then immediately remove. The handler applies operations in call
        // order (FIFO chain), and postEventAndWait joins that chain, so by the time it
        // returns the add and remove have both been applied and delivery has completed.
        handler.addObserver(ProfileIdentifiedEvent.self) { _ in received = true }
        handler.removeObserver(for: ProfileIdentifiedEvent.self)

        await handler.postEventAndWait(ProfileIdentifiedEvent(identifier: "after-remove"))

        XCTAssertFalse(received, "removed observer must not receive events")
    }
}
