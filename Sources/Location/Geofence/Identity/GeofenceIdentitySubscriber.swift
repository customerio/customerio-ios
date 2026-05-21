import CioInternalCommon
import Foundation

/// Keeps `GeofenceIdentityStore` in sync with identity transitions on the EventBus:
/// `ProfileIdentifiedEvent` writes the userId, `ResetEvent` clears it.
///
/// `AnonymousProfileIdentifiedEvent` is intentionally not observed — it's an init-time
/// state report, not a sign-out transition, and treating it as a clear signal would
/// risk clobbering a valid persisted userId during a routine SDK relaunch.
final class GeofenceIdentitySubscriber {
    init(eventBusHandler: EventBusHandler, identityStore: GeofenceIdentityStore) {
        eventBusHandler.addObserver(ProfileIdentifiedEvent.self) { event in
            identityStore.setUserId(event.identifier)
        }
        eventBusHandler.addObserver(ResetEvent.self) { _ in
            identityStore.clearUserId()
        }
    }
}
