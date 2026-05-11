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
typealias GeofenceTransitionHandler = @Sendable (String, GeofenceTransition, LocationData?) -> Void

/// Abstracts CLLocationManager's region monitoring.
///
/// The monitor owns a CLLocationManager and handles the delegate callbacks for region events.
/// Business logic decides which regions to monitor; this component only manages the OS registrations.
protocol GeofenceRegionMonitoring: AnyObject {
    /// Handler called when a geofence transition (enter/exit) occurs.
    var onTransition: GeofenceTransitionHandler? { get set }

    /// Starts monitoring a circular geofence region.
    /// - Parameters:
    ///   - identifier: Unique identifier for the region.
    ///   - center: Center coordinate.
    ///   - radius: Radius in meters. Clamped to `CLLocationManager.maximumRegionMonitoringDistance` if exceeded.
    ///   - transitionTypes: Which transitions to monitor (enter, exit, or both).
    func startMonitoring(identifier: String, center: LocationData, radius: Double, transitionTypes: Set<GeofenceTransition>)

    /// Stops monitoring the region with the given identifier.
    func stopMonitoring(identifier: String)

    /// Stops monitoring all currently monitored regions managed by this monitor.
    func stopMonitoringAll()

    /// Returns the set of region identifiers currently being monitored.
    var monitoredRegionIdentifiers: Set<String> { get }
}
