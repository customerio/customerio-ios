import CioInternalCommon
import Foundation

/// Wires `GeofenceRegionMonitoring` into the SDK: routes OS region transitions to
/// `GeofenceEventTracker.trackTransition` and seeds the monitor with the given regions
/// so a fresh process resumes monitoring without waiting on a server-sync round trip.
///
/// Synchronous by design. Callers MUST fetch the cached geofences before constructing the
/// monitor — any `await` between the `CLLocationManager` delegate being set and
/// `startMonitoring` being called creates a window where pending cold-wake delegate
/// callbacks pass the filter on `ownedRegionIdentifiers` (still empty) and are dropped.
@MainActor
enum GeofenceMonitorBinder {
    static func bind(
        monitor: GeofenceRegionMonitoring,
        geofences: [Geofence],
        tracker: GeofenceEventTracker
    ) {
        monitor.setOnTransition { [weak tracker] identifier, transition, location in
            // CLLocationManager delivers on main; trackTransition is async with its own
            // serialization (active-delivery dedup), so a fire-and-forget Task is safe.
            Task { await tracker?.trackTransition(geofenceId: identifier, transition: transition, location: location) }
        }
        for geofence in geofences {
            monitor.startMonitoring(
                identifier: geofence.id,
                center: LocationData(latitude: geofence.latitude, longitude: geofence.longitude),
                radius: geofence.radius,
                transitionTypes: geofence.transitionTypes
            )
        }
    }
}
