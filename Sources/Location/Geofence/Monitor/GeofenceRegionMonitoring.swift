import CioInternalCommon
import CoreLocation
import Foundation

/// Transition type for geofence boundary crossings.
enum GeofenceTransition: String, Codable, Sendable {
    case enter
    case exit
}

/// Callback when a geofence transition occurs.
/// Parameters: region identifier, transition type, user's current location (from CLLocationManager.location, may be nil).
///
/// Invoked synchronously on the main actor (CLLocationManager delegate callbacks arrive on main).
/// The closure body is not statically isolated — callers are free to hop to whatever actor they
/// need: `Task.detached { ... }` for off-main work, `MainActor.assumeIsolated { ... }` for direct
/// main-actor reads, or an `await someActor.method()` to hand off to another isolation domain.
typealias GeofenceTransitionHandler = @Sendable (String, GeofenceTransition, LocationData?) -> Void

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
}
