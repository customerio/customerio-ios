import CioInternalCommon
import Foundation

/// The diff-based initial enter-when-inside, split out to keep the coordinator's core flow readable.
/// Methods are `internal` (not `private`) only because they live in a separate file from their
/// callers; they remain coordinator implementation detail.
extension GeofenceSyncCoordinatorImpl {
    /// Fires an initial ENTER for each newly-registered geofence the device is already inside — the
    /// crossing neither OS layer reports for a region added around you (Android's `INITIAL_TRIGGER_ENTER`).
    /// The `previouslyRegisteredIds` diff keeps a wholesale re-register silent; a sign-out clears that set
    /// so the next sign-in re-fires. At the coordinator so iOS ≤17 and 18+ match; cooldown-deduped via the tracker.
    ///
    /// - Parameter registeredIds: the OS-accepted set. A candidate the monitor dropped (blocked
    ///   permission, invalid coordinates) isn't monitored, so it must not emit an enter it can't balance.
    func emitInitialEnters(
        candidates: [Geofence],
        registeredIds: Set<String>,
        previouslyRegisteredIds: Set<String>,
        expectedUserId: String,
        anchor: LocationData
    ) {
        let newInside = candidates.filter { region in
            registeredIds.contains(region.id)
                && !previouslyRegisteredIds.contains(region.id)
                && region.transitionTypes.contains(.enter)
                && region.distanceTo(anchor) <= region.radius
        }
        guard !newInside.isEmpty else { return }
        // Deliver off the refresh gate (like the binder does for real crossings) so a slow send can't
        // stall the next refresh; `trackTransition` persists first, so an interrupted send is retried.
        Task { [transitionEmitter, contextStore] in
            // The diff was computed for `expectedUserId`; a sign-out/sign-in before this detached task
            // runs must not reattribute the enter to whoever is current now (as `performRemoteRefresh`).
            guard contextStore.currentUserId == expectedUserId else { return }
            for region in newInside {
                await transitionEmitter.trackTransition(geofenceId: region.id, transition: .enter)
            }
        }
    }
}
