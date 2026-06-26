import CioInternalCommon
import Foundation

/// Wires the monitor's transition handler. Synchronous — must run before any
/// `startMonitoring` call so cold-wake delegate callbacks arriving immediately after
/// `CLLocationManager` becomes active have a handler to dispatch to.
///
/// Two dispatch paths:
/// - `GeofenceConstants.movementTriggerIdentifier` (EXIT) → `coordinator.handleMovement`
///   (internal; never tracked as a customer event).
/// - Any other identifier → `tracker.trackTransition` (the business geofences).
@MainActor
enum GeofenceMonitorBinder {
    static func bind(
        monitor: GeofenceRegionMonitoring,
        tracker: GeofenceEventTracker,
        coordinator: GeofenceSyncCoordinator
    ) {
        monitor.setOnTransition { [weak tracker, weak coordinator] identifier, transition, location in
            // CLLocationManager delivers on main; both handlers below are async with their
            // own serialization (tracker active-delivery dedup, coordinator refresh gate),
            // so fire-and-forget Tasks are safe.
            if identifier == GeofenceConstants.movementTriggerIdentifier {
                // EXIT is the only registered transition for the movement trigger; the
                // guard defends against an unexpected ENTER reaching this dispatch.
                guard transition == .exit, let location else { return }
                Task { _ = await coordinator?.handleMovement(latitude: location.latitude, longitude: location.longitude) }
                return
            }
            // `triggeredLocation` is TESTING-ONLY (geofence-testing branch) — feeds distance-from-geofence diagnostics.
            Task { await tracker?.trackTransition(geofenceId: identifier, transition: transition, triggeredLocation: location) }
        }
    }
}
