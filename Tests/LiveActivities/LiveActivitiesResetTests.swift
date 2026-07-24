import CioInternalCommon
import Foundation
import Testing

@testable import CioLiveActivities

// MARK: - Fakes for driving the module directly (no ActivityKit / no event bus)

final class NoopEventBusHandler: EventBusHandler, @unchecked Sendable {
    func loadEventsFromStorage() async {}
    func addObserver<E: EventRepresentable>(_ eventType: E.Type, action: @escaping (E) -> Void) {}
    func removeObserver<E: EventRepresentable>(for eventType: E.Type) {}
    func postEvent<E: EventRepresentable>(_ event: E) {}
    func postEventAndWait<E: EventRepresentable>(_ event: E) async {}
    func removeFromStorage<E: EventRepresentable>(_ event: E) async {}
}

/// Records posted events so tests can assert what the SDK emitted onto the event bus.
final class CapturingEventBusHandler: EventBusHandler, @unchecked Sendable {
    private(set) var posted: [Any] = []
    func loadEventsFromStorage() async {}
    func addObserver<E: EventRepresentable>(_ eventType: E.Type, action: @escaping (E) -> Void) {}
    func removeObserver<E: EventRepresentable>(for eventType: E.Type) {}
    func postEvent<E: EventRepresentable>(_ event: E) {
        posted.append(event)
    }

    func postEventAndWait<E: EventRepresentable>(_ event: E) async {}
    func removeFromStorage<E: EventRepresentable>(_ event: E) async {}
}

final class FakeLiveActivitiesSDK: CIOLiveActivitiesSDKProviding, @unchecked Sendable {
    let registeredDeviceToken: String?
    let isUserIdentified: Bool
    let eventBusHandler: EventBusHandler
    let logger: Logger = NoopLogger()
    let sharedKeyValueStorage: SharedKeyValueStorage = InMemoryKeyValueStorage()

    init(
        registeredDeviceToken: String? = "device-token",
        isUserIdentified: Bool,
        eventBusHandler: EventBusHandler = NoopEventBusHandler()
    ) {
        self.registeredDeviceToken = registeredDeviceToken
        self.isUserIdentified = isUserIdentified
        self.eventBusHandler = eventBusHandler
    }

    func track(name: String, properties: [String: Any]?) {}
}

// MARK: - Reset suppression (account-switch regression)

struct LiveActivitiesResetTests {
    /// Regression: on reset (logout/account switch), every activity that reset force-ends must be
    /// marked as an SDK-initiated (local) end. The `.immediate` dismissal surfaces as a `.dismissed`
    /// terminal, which the observer would otherwise report as a user swipe — and, because the
    /// reporter now gates on the *synchronous* identity, a `clearIdentify(); identify("B")` sequence
    /// has already put B into the store by the time this async reset runs, so the stray `end` would
    /// be attributed to B. Marking the local end makes the terminal classify as cleanupOnly instead.
    @Test func reset_marksForceEndedActivitiesAsLocalEnds_evenWhenAnotherUserIsIdentified() async {
        let tracker = LiveActivityLocalEndTracker()
        let store = FakeTokenStore()
        var config = LiveActivityConfig()
        config.registrations = [
            ActivityTypeRegistration(
                activityIdentifier: "io.customer.livenotifications.segments",
                attributesTypeName: "CIOSegmentsAttributes",
                startObserving: { _ in Task {} },
                endAllActivities: { prepareLocalEnd in
                    // Simulate one running activity being force-ended by reset.
                    prepareLocalEnd("activitykit-id-1", "inst-1")
                }
            )
        ]
        // isUserIdentified == true simulates the account switch: B is already identified in the
        // synchronous store when this async reset runs.
        let sdk = FakeLiveActivitiesSDK(isUserIdentified: true)
        let module = LiveActivitiesModule(config: config, sdk: sdk, tokenStorage: store, localEndTracker: tracker)

        await module.handleReset()

        // The forced end was marked as a local end, so `liveActivityTerminalAction` classifies its
        // `.dismissed` terminal as `.cleanupOnly` — no `end` reported under the new user.
        #expect(tracker.consume("inst-1") == true)
    }

    /// Regression: an activity the app ended via `CIOLiveActivity.end()` just before logout is
    /// already marked local but no longer in `Activity.activities`, so the reset loop won't re-mark
    /// it. Reset must NOT drop that marker — otherwise its late `.dismissed` terminal would be
    /// reported as a user dismissal under the next user.
    @Test func reset_preservesInFlightLocalEndMarks() async {
        let tracker = LiveActivityLocalEndTracker()
        tracker.markEnded("in-flight-1") // an app-initiated end already in flight at logout
        let store = FakeTokenStore()
        var config = LiveActivityConfig()
        config.registrations = [
            ActivityTypeRegistration(
                activityIdentifier: "io.customer.livenotifications.segments",
                attributesTypeName: "CIOSegmentsAttributes",
                startObserving: { _ in Task {} },
                endAllActivities: { _ in } // nothing currently listed to force-end
            )
        ]
        let sdk = FakeLiveActivitiesSDK(isUserIdentified: true)
        let module = LiveActivitiesModule(config: config, sdk: sdk, tokenStorage: store, localEndTracker: tracker)

        await module.handleReset()

        #expect(tracker.consume("in-flight-1") == true)
    }

    /// Sanity: when the type carries no attributes instance id, reset still marks a (minted) local
    /// end for the activity, keyed by the token store's resolved id.
    @Test func reset_marksLocalEnd_whenNoAttributesInstanceId() async {
        let tracker = LiveActivityLocalEndTracker()
        let store = FakeTokenStore()
        var config = LiveActivityConfig()
        config.registrations = [
            ActivityTypeRegistration(
                activityIdentifier: "io.customer.livenotifications.custom",
                attributesTypeName: "Custom",
                startObserving: { _ in Task {} },
                endAllActivities: { prepareLocalEnd in prepareLocalEnd("activitykit-id-2", nil) }
            )
        ]
        let sdk = FakeLiveActivitiesSDK(isUserIdentified: true)
        let module = LiveActivitiesModule(config: config, sdk: sdk, tokenStorage: store, localEndTracker: tracker)

        await module.handleReset()

        // The minted id is the one the store resolved for the activity; it must be marked local.
        let resolved = store.resolveInstanceId(forActivityId: "activitykit-id-2") { "" }
        #expect(!resolved.isEmpty)
        #expect(tracker.consume(resolved) == true)
    }
}
