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
    /// - Parameter osRegistration: what the OS accepted this sync. A candidate absent from
    ///   `registeredIds` (dropped for blocked permission / invalid coordinates) isn't monitored, so it
    ///   must not emit an enter it can't balance; the inside check clamps to `maxMonitoringRadius`
    ///   (Apple guarantees no floor for it, so a fence radius can exceed the monitored circle).
    func emitInitialEnters(
        candidates: [Geofence],
        osRegistration: GeofenceOsRegistration,
        previouslyRegisteredIds: Set<String>,
        expectedUserId: String,
        anchor: LocationData
    ) {
        let newInside = candidates.filter { region in
            osRegistration.registeredIds.contains(region.id)
                && !previouslyRegisteredIds.contains(region.id)
                && region.transitionTypes.contains(.enter)
                && region.distanceTo(anchor) <= min(region.radius, osRegistration.maxMonitoringRadius)
        }
        guard !newInside.isEmpty else { return }
        // Deliver off the refresh gate (like the binder does for real crossings) so a slow send can't
        // stall the next refresh; `trackTransition` persists first, so an interrupted send is retried.
        Task { [transitionEmitter, contextStore] in
            for region in newInside {
                // Re-check per iteration: the diff was computed for `expectedUserId`, and each awaited
                // send can span a sign-out/switch that the tracker would otherwise stamp to whoever is
                // current — so stop the batch the moment identity changes.
                guard contextStore.currentUserId == expectedUserId else { return }
                await transitionEmitter.trackTransition(geofenceId: region.id, transition: .enter)
            }
        }
    }
}
