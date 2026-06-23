import CioInternalCommon
import CoreLocation
import Foundation

/// Callback when a geofence transition occurs.
/// Parameters: region identifier, transition type, user's current location (from CLLocationManager.location, may be nil).
///
/// Invoked synchronously on the main actor (CLLocationManager delegate callbacks arrive on main).
/// The closure body is not statically isolated — callers are free to hop to whatever actor they
/// need: `Task.detached { ... }` for off-main work, `MainActor.assumeIsolated { ... }` for direct
/// main-actor reads, or an `await someActor.method()` to hand off to another isolation domain.
typealias GeofenceTransitionHandler = @Sendable (String, GeofenceTransition, LocationData?) -> Void

/// Callback when iOS reports a change to the location authorization status.
/// Invoked on the main actor — same isolation domain as `CLLocationManagerDelegate`.
typealias GeofenceAuthorizationChangedHandler = @MainActor () -> Void

/// Abstracts CLLocationManager's region monitoring.
///
/// The monitor owns a CLLocationManager and handles the delegate callbacks for region events.
/// Business logic decides which regions to monitor; this component only manages the OS registrations.
///
/// Main-actor isolated because CLLocationManager must be created and called on the main thread,
/// and its delegate callbacks arrive on main. Keeping the monitor's bookkeeping state in the
/// same isolation domain as the OS calls removes the need for locks, fire-and-forget Tasks,
/// or reentrancy reasoning between state mutations and OS dispatches.
@MainActor
protocol GeofenceRegionMonitoring: AnyObject, Sendable {
    /// Sets the handler called when a geofence transition (enter/exit) occurs.
    func setOnTransition(_ handler: GeofenceTransitionHandler?)

    /// Sets the handler invoked when iOS reports an authorization status change. Lets callers
    /// re-attempt registration when permission improves mid-process (e.g. host's permission
    /// prompt resolved, or the user toggled the setting in Settings).
    func setOnAuthorizationChanged(_ handler: GeofenceAuthorizationChangedHandler?)

    /// Starts monitoring a circular geofence region.
    /// - Parameters:
    ///   - identifier: Unique identifier for the region.
    ///   - center: Center coordinate.
    ///   - radius: Radius in meters. Clamped to `CLLocationManager.maximumRegionMonitoringDistance` if exceeded.
    ///   - transitionTypes: Which transitions to monitor (enter, exit, or both).
    func startMonitoring(identifier: String, center: LocationData, radius: Double, transitionTypes: Set<GeofenceTransition>)

    /// Stops monitoring the region with the given identifier.
    func stopMonitoring(identifier: String)

    /// Stops monitoring all regions managed by this monitor.
    func stopMonitoringAll()

    /// Returns the set of region identifiers currently being monitored by this monitor.
    var monitoredRegionIdentifiers: Set<String> { get }

    /// Region identifiers the OS still actively monitors app-wide (`CLLocationManager.monitoredRegions`).
    /// These persist across process launch and device reboot, so on a fresh process this is populated
    /// even though `monitoredRegionIdentifiers` (the in-memory ownership filter) starts empty.
    var osMonitoredRegionIdentifiers: Set<String> { get }

    /// Re-claims the OS-persisted regions whose identifiers are in `identifiers` as owned by this
    /// monitor, without re-registering them. Restores transition recognition on a fresh process
    /// where the OS kept monitoring but the in-memory ownership set was lost.
    func adoptExistingRegions(matching identifiers: Set<String>)
}
