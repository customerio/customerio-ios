import CioInternalCommon
import Foundation

/// Wires the monitor's transition handler to forward OS region transitions into
/// `GeofenceEventTracker.trackTransition`. Synchronous by design — must run before any
/// `startMonitoring` call so cold-wake delegate callbacks arriving immediately after
/// `CLLocationManager` becomes active have a handler to dispatch to.
@MainActor
enum GeofenceMonitorBinder {
    static func bind(monitor: GeofenceRegionMonitoring, tracker: GeofenceEventTracker) {
        monitor.setOnTransition { [weak tracker] identifier, transition, location in
            // CLLocationManager delivers on main; trackTransition is async with its own
            // serialization (active-delivery dedup), so a fire-and-forget Task is safe.
            Task { await tracker?.trackTransition(geofenceId: identifier, transition: transition, location: location) }
        }
    }
}
