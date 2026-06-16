import XCTest

@testable import CioInternalCommon

class CioEventBusTest: XCTestCase {
    // MARK: - addObserver

    func test_addObserver_givenNoCachedEvents_expectEmptyReplay() async {
        let bus = CioEventBus()
        let registration = await bus.addObserver(key: ProfileIdentifiedEvent.key) { _ in }
        XCTAssertTrue(registration.eventsToReplay.isEmpty)
    }

    func test_addObserver_givenCachedEvent_expectSnapshotContainsEvent() async {
        let bus = CioEventBus()
        _ = await bus.post(ProfileIdentifiedEvent(identifier: "test"))

        let registration = await bus.addObserver(key: ProfileIdentifiedEvent.key) { _ in }
        XCTAssertEqual(registration.eventsToReplay.count, 1)
    }

    func test_addObserver_givenEventPostedAfterRegistration_expectSnapshotExcludesIt() async {
        let bus = CioEventBus()

        // Snapshot is taken here; nothing in cache yet.
        let registration = await bus.addObserver(key: ProfileIdentifiedEvent.key) { _ in }

        // Posting after registration must not appear in the earlier snapshot.
        _ = await bus.post(ProfileIdentifiedEvent(identifier: "test"))

        XCTAssertTrue(registration.eventsToReplay.isEmpty)
    }

    func test_addObserver_givenMultipleObservers_expectAllReceiveFullHistory() async {
        let bus = CioEventBus()
        _ = await bus.post(ProfileIdentifiedEvent(identifier: "test"))

        let regA = await bus.addObserver(key: ProfileIdentifiedEvent.key) { _ in }
        let regB = await bus.addObserver(key: ProfileIdentifiedEvent.key) { _ in }

        // Both observers should see the same pre-existing event — cache is never cleared.
        XCTAssertEqual(regA.eventsToReplay.count, 1)
        XCTAssertEqual(regB.eventsToReplay.count, 1)
    }

    func test_addObserver_givenDifferentEventTypes_expectIndependentCaches() async {
        let bus = CioEventBus()
        _ = await bus.post(ProfileIdentifiedEvent(identifier: "test"))

        let regProfile = await bus.addObserver(key: ProfileIdentifiedEvent.key) { _ in }
        let regReset = await bus.addObserver(key: ResetEvent.key) { _ in }

        XCTAssertEqual(regProfile.eventsToReplay.count, 1)
        XCTAssertTrue(regReset.eventsToReplay.isEmpty)
    }

    func test_addObserver_expectUniqueTokensPerRegistration() async {
        let bus = CioEventBus()
        let regA = await bus.addObserver(key: ProfileIdentifiedEvent.key) { _ in }
        let regB = await bus.addObserver(key: ProfileIdentifiedEvent.key) { _ in }
        XCTAssertNotEqual(regA.token.identifier, regB.token.identifier)
    }

    // MARK: - post

    func test_post_givenNoObservers_expectEmptyActionsAndEventCached() async {
        let bus = CioEventBus()
        let actions = await bus.post(ProfileIdentifiedEvent(identifier: "test"))
        XCTAssertTrue(actions.isEmpty)

        // Even with no observers, the event must be cached for future registrations.
        let registration = await bus.addObserver(key: ProfileIdentifiedEvent.key) { _ in }
        XCTAssertEqual(registration.eventsToReplay.count, 1)
    }

    func test_post_givenObserver_expectActionDeliveredWithCorrectEvent() async {
        let bus = CioEventBus()
        var received: [ProfileIdentifiedEvent] = []
        _ = await bus.addObserver(key: ProfileIdentifiedEvent.key) { event in
            if let e = event as? ProfileIdentifiedEvent { received.append(e) }
        }

        let event = ProfileIdentifiedEvent(identifier: "hello")
        let actions = await bus.post(event)
        actions.forEach { $0(event) }

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.identifier, "hello")
    }

    func test_post_givenObserver_expectEventAlsoCachedForFutureObservers() async {
        let bus = CioEventBus()
        _ = await bus.addObserver(key: ProfileIdentifiedEvent.key) { _ in }
        _ = await bus.post(ProfileIdentifiedEvent(identifier: "test"))

        let reg = await bus.addObserver(key: ProfileIdentifiedEvent.key) { _ in }
        XCTAssertEqual(reg.eventsToReplay.count, 1)
    }

    func test_post_givenMultipleObservers_expectAllActionsReturned() async {
        let bus = CioEventBus()
        var countA = 0
        var countB = 0
        _ = await bus.addObserver(key: ProfileIdentifiedEvent.key) { _ in countA += 1 }
        _ = await bus.addObserver(key: ProfileIdentifiedEvent.key) { _ in countB += 1 }

        let event = ProfileIdentifiedEvent(identifier: "multi")
        let actions = await bus.post(event)
        actions.forEach { $0(event) }

        XCTAssertEqual(countA, 1)
        XCTAssertEqual(countB, 1)
    }

    // MARK: - removeAllObservers

    func test_removeAllObservers_givenRegisteredObserver_expectNoActionsOnPost() async {
        let bus = CioEventBus()
        _ = await bus.addObserver(key: ProfileIdentifiedEvent.key) { _ in }
        await bus.removeAllObservers(key: ProfileIdentifiedEvent.key)

        let actions = await bus.post(ProfileIdentifiedEvent(identifier: "test"))
        XCTAssertTrue(actions.isEmpty)
    }

    func test_removeAllObservers_givenMultipleObservers_expectAllRemoved() async {
        let bus = CioEventBus()
        _ = await bus.addObserver(key: ProfileIdentifiedEvent.key) { _ in }
        _ = await bus.addObserver(key: ProfileIdentifiedEvent.key) { _ in }
        await bus.removeAllObservers(key: ProfileIdentifiedEvent.key)

        let actions = await bus.post(ProfileIdentifiedEvent(identifier: "test"))
        XCTAssertTrue(actions.isEmpty)
    }

    // MARK: - removeObserver (token-based)

    func test_removeObserver_givenIdentifier_expectOnlyThatObserverRemoved() async {
        let bus = CioEventBus()
        var receivedA = 0
        var receivedB = 0

        let regA = await bus.addObserver(key: ProfileIdentifiedEvent.key) { _ in receivedA += 1 }
        _ = await bus.addObserver(key: ProfileIdentifiedEvent.key) { _ in receivedB += 1 }

        await bus.removeObserver(key: ProfileIdentifiedEvent.key, identifier: regA.token.identifier)

        let event = ProfileIdentifiedEvent(identifier: "test")
        let actions = await bus.post(event)
        actions.forEach { $0(event) }

        XCTAssertEqual(receivedA, 0, "removed observer must not receive events")
        XCTAssertEqual(receivedB, 1, "remaining observer must still receive events")
    }

    func test_removeObserver_givenLastObserver_expectKeyCleared() async {
        let bus = CioEventBus()
        let reg = await bus.addObserver(key: ProfileIdentifiedEvent.key) { _ in }
        await bus.removeObserver(key: ProfileIdentifiedEvent.key, identifier: reg.token.identifier)

        let actions = await bus.post(ProfileIdentifiedEvent(identifier: "test"))
        XCTAssertTrue(actions.isEmpty)
    }

    func test_removeObserver_givenUnknownIdentifier_expectNoObserversAffected() async {
        let bus = CioEventBus()
        var received = 0
        _ = await bus.addObserver(key: ProfileIdentifiedEvent.key) { _ in received += 1 }

        await bus.removeObserver(key: ProfileIdentifiedEvent.key, identifier: UUID())

        let event = ProfileIdentifiedEvent(identifier: "test")
        let actions = await bus.post(event)
        actions.forEach { $0(event) }

        XCTAssertEqual(received, 1, "observer with a different identifier must not be removed")
    }

    // MARK: - seedCache

    func test_seedCache_givenStoredEvents_expectReplayedToNewObserver() async {
        let bus = CioEventBus()
        await bus.seedCache([ProfileIdentifiedEvent(identifier: "stored")], forKey: ProfileIdentifiedEvent.key)

        let registration = await bus.addObserver(key: ProfileIdentifiedEvent.key) { _ in }
        XCTAssertEqual(registration.eventsToReplay.count, 1)
    }

    func test_seedCache_givenNoExistingCache_expectEventsAvailableAfterSeeding() async {
        let bus = CioEventBus()
        await bus.seedCache(
            [ProfileIdentifiedEvent(identifier: "a"), ProfileIdentifiedEvent(identifier: "b")],
            forKey: ProfileIdentifiedEvent.key
        )

        let reg = await bus.addObserver(key: ProfileIdentifiedEvent.key) { _ in }
        XCTAssertEqual(reg.eventsToReplay.count, 2)
    }
}
