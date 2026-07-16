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
    func emitInitialEnters(registered: [Geofence], previouslyRegisteredIds: Set<String>, anchor: LocationData) {
        let newInside = registered.filter { region in
            !previouslyRegisteredIds.contains(region.id)
                && region.transitionTypes.contains(.enter)
                && region.distanceTo(anchor) <= region.radius
        }
        guard !newInside.isEmpty else { return }
        // Deliver off the refresh gate (like the binder does for real crossings) so a slow send can't
        // stall the next refresh; `trackTransition` persists first, so an interrupted send is retried.
        Task { [transitionEmitter] in
            for region in newInside {
                await transitionEmitter.trackTransition(geofenceId: region.id, transition: .enter)
            }
        }
    }
}
