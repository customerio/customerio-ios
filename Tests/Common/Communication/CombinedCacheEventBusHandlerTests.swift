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

    func test_postEventAndWait_givenNoObserversAndTransientEvent_expectEventNotStored() async {
        let handler = makeHandler()

        // LocationAcquiredEvent is transient (isPersistent == false).
        await handler.postEventAndWait(LocationAcquiredEvent(location: LocationData(latitude: 0, longitude: 0)))

        // Even with no observers it must not be written to disk, so location-only apps
        // don't accumulate undrained event files.
        XCTAssertEqual(mockEventStorage.storeCallsCount, 0)
    }

    func test_postEventAndWait_givenNoObservers_expectNoStoreErrorPropagated() async {
        mockEventStorage.storeThrowableError = NSError(domain: "test", code: 1)
        let handler = makeHandler()

        // Should not throw or crash; errors are absorbed and logged.
        await handler.postEventAndWait(ProfileIdentifiedEvent(identifier: "user-1"))
    }

    func test_postEvent_givenObserverAddedThenRemoved_expectEventStoredWithoutDelivery() async {
        let handler = makeHandler()
        let event = ProfileIdentifiedEvent(identifier: "after-remove")
        let received = Synchronized(false)
        let stored = XCTestExpectation(description: "unobserved event stored")
        mockEventStorage.storeClosure = { storedEvent in
            guard storedEvent.storageId == event.storageId else { return }
            stored.fulfill()
        }

        handler.addObserver(ProfileIdentifiedEvent.self) { _ in received.wrappedValue = true }
        handler.removeObserver(for: ProfileIdentifiedEvent.self)
        handler.postEvent(event)

        await fulfillment(of: [stored], timeout: 5.0)
        XCTAssertFalse(received.wrappedValue)
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
        let removed = XCTestExpectation(description: "event removed from persistent storage")
        mockEventStorage.removeClosure = { _, _ in removed.fulfill() }
        handler.addObserver(ProfileIdentifiedEvent.self) { _ in replayed.fulfill() }
        await fulfillment(of: [replayed, removed], timeout: 5.0)

        XCTAssertEqual(mockEventStorage.removeCallsCount, 1)
    }

    func test_postEventAndWait_givenReplayCleanupSuspended_expectSameKeyPostNotBlocked() async {
        let storage = SuspendedRemovalEventStorage()
        let handler = CombinedCacheEventBusHandler(eventStorage: storage, logger: log)
        await handler.postEventAndWait(ProfileIdentifiedEvent(identifier: "historic"))

        handler.addObserver(ProfileIdentifiedEvent.self) { _ in }
        await storage.waitForRemovalToStart()

        let completedBeforeTimeout = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            group.addTask {
                await handler.postEventAndWait(ProfileIdentifiedEvent(identifier: "after-replay"))
                return true
            }
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: 2000000000)
                } catch {
                    return true
                }
                await storage.releaseRemoval()
                return false
            }

            let firstResult = await group.next() ?? false
            if firstResult {
                await storage.releaseRemoval()
            }
            group.cancelAll()
            return firstResult
        }

        XCTAssertTrue(completedBeforeTimeout, "persistent cleanup must not block event delivery")
    }

    func test_addObserver_givenPostImmediatelyAfterRegistration_expectDirectDelivery() async {
        let handler = makeHandler()
        let received = Synchronized(false)

        handler.addObserver(ProfileIdentifiedEvent.self) { _ in received.wrappedValue = true }
        await handler.postEventAndWait(ProfileIdentifiedEvent(identifier: "after-add"))

        XCTAssertTrue(received.wrappedValue, "registration requested before the post must be applied first")
    }

    func test_postEventAndWait_givenUnrelatedRegistryWorkSuspended_expectPostNotBlocked() async {
        let handler = makeHandler()
        let registryGate = AsyncGate()
        handler.chainRegistryWork(forKey: ProfileIdentifiedEvent.key) {
            await registryGate.wait()
        }
        await registryGate.waitUntilStarted()

        let watchdogReleasedRegistry = Synchronized(false)
        let completedBeforeTimeout = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            group.addTask {
                await handler.postEventAndWait(ResetEvent())
                return true
            }
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: 2000000000)
                } catch {
                    return true
                }
                watchdogReleasedRegistry.wrappedValue = true
                await registryGate.release()
                return false
            }

            let firstResult = await group.next() ?? false
            if firstResult {
                await registryGate.release()
            }
            group.cancelAll()
            return firstResult
        }

        XCTAssertTrue(completedBeforeTimeout)
        XCTAssertFalse(watchdogReleasedRegistry.wrappedValue)

        // Drain the Profile chain so the suspended operation cannot outlive the test.
        await handler.postEventAndWait(ProfileIdentifiedEvent(identifier: "after-registry-work"))
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

        let deliveryCount = Synchronized(0)
        let delivered = XCTestExpectation(description: "delivered")
        delivered.assertForOverFulfill = true

        handler.addObserver(ProfileIdentifiedEvent.self) { received in
            if received.identifier == event.identifier {
                deliveryCount.mutating { $0 += 1 }
                delivered.fulfill()
            }
        }

        await fulfillment(of: [delivered], timeout: 5.0)
        XCTAssertEqual(deliveryCount.wrappedValue, 1, "event must be delivered exactly once")
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

    func test_registryOrdering_givenConcurrentDifferentEventKeys_expectEachRemovalApplied() async {
        // Stress the synchronized per-key tail map from concurrent callers while preserving
        // a deterministic add-then-remove order within each event type.
        for iteration in 0 ..< 50 {
            let handler = makeHandler()
            let deliveryCount = Synchronized(0)

            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    handler.addObserver(ProfileIdentifiedEvent.self) { _ in
                        deliveryCount.mutating { $0 += 1 }
                    }
                    handler.removeObserver(for: ProfileIdentifiedEvent.self)
                    await handler.postEventAndWait(
                        ProfileIdentifiedEvent(identifier: "profile-\(iteration)")
                    )
                }
                group.addTask {
                    handler.addObserver(ResetEvent.self) { _ in
                        deliveryCount.mutating { $0 += 1 }
                    }
                    handler.removeObserver(for: ResetEvent.self)
                    await handler.postEventAndWait(ResetEvent())
                }
            }

            XCTAssertEqual(deliveryCount.wrappedValue, 0)
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
        let received = Synchronized(false)

        // Register and then immediately remove.
        handler.addObserver(ProfileIdentifiedEvent.self) { _ in received.wrappedValue = true }
        handler.removeObserver(for: ProfileIdentifiedEvent.self)

        // No sleep needed: postEventAndWait applies the add/remove requested above in call
        // order before it reads the observer set, and it invokes every observer it finds
        // before returning. So if the removal were lost, `received` would be true here.
        await handler.postEventAndWait(ProfileIdentifiedEvent(identifier: "after-remove"))

        XCTAssertFalse(received.wrappedValue, "removed observer must not receive events")
    }

    func test_removeObserver_givenObserverAlreadyApplied_expectRemovalOrderedBeforeNextPost() async {
        let handler = makeHandler()
        let deliveryCount = Synchronized(0)

        handler.addObserver(ProfileIdentifiedEvent.self) { _ in deliveryCount.mutating { $0 += 1 } }
        await handler.postEventAndWait(ProfileIdentifiedEvent(identifier: "before-remove"))

        handler.removeObserver(for: ProfileIdentifiedEvent.self)
        await handler.postEventAndWait(ProfileIdentifiedEvent(identifier: "after-remove"))

        XCTAssertEqual(deliveryCount.wrappedValue, 1, "removal requested before the second post must be applied first")
    }
}

private actor AsyncGate {
    private var started = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        started = true
        let currentStartedWaiters = startedWaiters
        startedWaiters.removeAll()
        currentStartedWaiters.forEach { $0.resume() }
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func release() {
        let currentWaiters = waiters
        waiters.removeAll()
        currentWaiters.forEach { $0.resume() }
    }
}

private actor SuspendedRemovalEventStorage: EventStorage {
    private let removalGate = AsyncGate()

    func store(event: AnyEventRepresentable) async throws {}

    func retrieve(eventType: String, storageId: String) async throws -> AnyEventRepresentable? {
        nil
    }

    func loadEvents(ofType type: String) async throws -> [AnyEventRepresentable] {
        []
    }

    func remove(ofType eventType: String, withStorageId storageId: String) async {
        await removalGate.wait()
    }

    func removeAll() async {}

    func waitForRemovalToStart() async {
        await removalGate.waitUntilStarted()
    }

    func releaseRemoval() async {
        await removalGate.release()
    }
}
