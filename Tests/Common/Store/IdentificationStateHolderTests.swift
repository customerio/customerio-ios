@testable import CioInternalCommon
import SharedTests
import XCTest

// MARK: - Synchronous EventBusHandler for tests

/// Delivers events to observers synchronously when postEvent is called (no async queue).
private final class SynchronousEventBusHandler: EventBusHandler {
    private var observers: [String: (AnyEventRepresentable) -> Void] = [:]

    func loadEventsFromStorage() async {}

    func addObserver<E: EventRepresentable>(_ eventType: E.Type, action: @escaping (E) -> Void) {
        observers[eventType.key] = { event in
            if let e = event as? E { action(e) }
        }
    }

    func removeObserver<E: EventRepresentable>(for eventType: E.Type) {
        observers.removeValue(forKey: eventType.key)
    }

    func postEvent<E: EventRepresentable>(_ event: E) {
        observers[E.key]?(event)
    }

    func postEventAndWait<E: EventRepresentable>(_ event: E) async {
        observers[E.key]?(event)
    }

    func removeFromStorage<E: EventRepresentable>(_ event: E) async {}
}

// MARK: - IdentificationStateHolderTests

class IdentificationStateHolderTests: UnitTest {
    private var eventBusHandler: SynchronousEventBusHandler!
    private var holder: IdentificationStateHolder!

    override func setUp() {
        super.setUp()
        eventBusHandler = SynchronousEventBusHandler()
        holder = IdentificationStateHolder(eventBusHandler: eventBusHandler)
    }

    func test_initialState_expectNotIdentified() {
        XCTAssertFalse(holder.isIdentified)
    }

    func test_profileIdentifiedEvent_expectIdentified() {
        eventBusHandler.postEvent(ProfileIdentifiedEvent(identifier: "user-1"))
        XCTAssertTrue(holder.isIdentified)
    }

    func test_anonymousProfileIdentifiedEvent_expectNotIdentified() {
        eventBusHandler.postEvent(AnonymousProfileIdentifiedEvent(identifier: "anon-1"))
        XCTAssertFalse(holder.isIdentified)
    }

    func test_resetEvent_expectNotIdentified() {
        eventBusHandler.postEvent(ResetEvent())
        XCTAssertFalse(holder.isIdentified)
    }

    func test_profileIdentifiedThenReset_expectTrueThenFalse() {
        eventBusHandler.postEvent(ProfileIdentifiedEvent(identifier: "user-1"))
        XCTAssertTrue(holder.isIdentified)
        eventBusHandler.postEvent(ResetEvent())
        XCTAssertFalse(holder.isIdentified)
    }

    func test_profileIdentifiedThenAnonymous_expectTrueThenFalse() {
        eventBusHandler.postEvent(ProfileIdentifiedEvent(identifier: "user-1"))
        XCTAssertTrue(holder.isIdentified)
        eventBusHandler.postEvent(AnonymousProfileIdentifiedEvent(identifier: "anon-1"))
        XCTAssertFalse(holder.isIdentified)
    }

    func test_anonymousThenProfileIdentified_expectNotIdentifiedThenIdentified() {
        eventBusHandler.postEvent(AnonymousProfileIdentifiedEvent(identifier: "anon-1"))
        XCTAssertFalse(holder.isIdentified)
        eventBusHandler.postEvent(ProfileIdentifiedEvent(identifier: "user-1"))
        XCTAssertTrue(holder.isIdentified)
    }
}
