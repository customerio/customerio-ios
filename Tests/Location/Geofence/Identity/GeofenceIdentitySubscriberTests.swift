@testable import CioInternalCommon
@testable import CioLocation
import Foundation
import SharedTests
import Testing

@Suite("GeofenceIdentitySubscriber")
struct GeofenceIdentitySubscriberTests {
    @Test
    func init_givenProfileIdentifiedEvent_expectStoreUpdated() {
        let storage = InMemorySharedKeyValueStorage()
        let store = GeofenceIdentityStore(storage: storage)
        let bus = SpyEventBusHandler()
        _ = GeofenceIdentitySubscriber(eventBusHandler: bus, identityStore: store)

        bus.post(ProfileIdentifiedEvent(identifier: "user_42"))

        #expect(store.currentUserId == "user_42")
    }

    @Test
    func init_givenResetEvent_expectStoreCleared() {
        let storage = InMemorySharedKeyValueStorage()
        let store = GeofenceIdentityStore(storage: storage)
        store.setUserId("user_42")
        let bus = SpyEventBusHandler()
        _ = GeofenceIdentitySubscriber(eventBusHandler: bus, identityStore: store)

        bus.post(ResetEvent())

        #expect(store.currentUserId == nil)
    }

    @Test
    func init_givenAnonymousProfileIdentifiedEvent_expectStoreUntouched() {
        let storage = InMemorySharedKeyValueStorage()
        let store = GeofenceIdentityStore(storage: storage)
        store.setUserId("user_42")
        let bus = SpyEventBusHandler()
        _ = GeofenceIdentitySubscriber(eventBusHandler: bus, identityStore: store)

        // Posting an anonymous-profile event must NOT clear a previously-stored userId —
        // it's an initial-state report, not a sign-out transition.
        bus.post(AnonymousProfileIdentifiedEvent(identifier: "anon-id"))

        #expect(store.currentUserId == "user_42")
    }

    @Test
    func init_givenSubscriberRegistered_expectExactlyTwoObservers() {
        let storage = InMemorySharedKeyValueStorage()
        let store = GeofenceIdentityStore(storage: storage)
        let bus = SpyEventBusHandler()

        _ = GeofenceIdentitySubscriber(eventBusHandler: bus, identityStore: store)

        #expect(bus.observedEventTypeNames.contains(String(describing: ProfileIdentifiedEvent.self)))
        #expect(bus.observedEventTypeNames.contains(String(describing: ResetEvent.self)))
        #expect(bus.observedEventTypeNames.count == 2)
        #expect(!bus.observedEventTypeNames.contains(String(describing: AnonymousProfileIdentifiedEvent.self)))
    }
}

/// In-test EventBusHandler that records observers and lets the test fire events through them.
/// Mirrors enough of the EventBus contract for unit tests; not a stand-in for `CioEventBusHandler`.
private final class SpyEventBusHandler: EventBusHandler, @unchecked Sendable {
    private(set) var observedEventTypeNames: [String] = []
    private var observers: [String: [(Any) -> Void]] = [:]

    func loadEventsFromStorage() async {}

    func addObserver<E: EventRepresentable>(_ eventType: E.Type, action: @escaping (E) -> Void) {
        let key = String(describing: eventType)
        observedEventTypeNames.append(key)
        observers[key, default: []].append { any in
            if let typed = any as? E { action(typed) }
        }
    }

    func removeObserver<E: EventRepresentable>(for eventType: E.Type) {
        observers.removeValue(forKey: String(describing: eventType))
    }

    func postEvent<E: EventRepresentable>(_ event: E) {
        post(event)
    }

    func postEventAndWait<E: EventRepresentable>(_ event: E) async {
        post(event)
    }

    func removeFromStorage<E: EventRepresentable>(_ event: E) async {}

    func post<E: EventRepresentable>(_ event: E) {
        let key = String(describing: type(of: event))
        observers[key]?.forEach { $0(event) }
    }
}
