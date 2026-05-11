import CioInternalCommon
import CoreLocation
import Foundation

/// CLLocationManager-backed geofence region monitor.
///
/// Implemented as an actor so all mutable state is serialized without locks.
/// Delegate callbacks are nonisolated and re-enter the actor via `Task { await ... }`,
/// matching the existing `CoreLocationProvider` pattern in this module.
///
/// Tracks which regions this monitor owns so it does not interfere with regions
/// registered by the host app or other SDKs (CLLocationManager.monitoredRegions is shared app-wide).
///
/// Must be created on the main thread so CLLocationManager and delegate setup run on main.
/// CLLocationManager method calls are dispatched to the main actor via fire-and-forget
/// `Task { @MainActor in ... }` so the ownership-set update and OS-call dispatch happen
/// atomically on the actor executor with no reentrancy point between them.
actor CoreLocationGeofenceMonitor: NSObject, GeofenceRegionMonitoring, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private let logger: Logger
    private let maxRegionMonitoringDistance: CLLocationDistance
    private var onTransition: GeofenceTransitionHandler?
    private var hasLoggedPermissionWarning = false
    private var ownedRegionIdentifiers: Set<String> = []

    init(logger: Logger) {
        let manager = CLLocationManager()
        self.manager = manager
        self.logger = logger
        // Constant for the platform (documented as 10 km on iOS); cache so we don't need
        // an actor-suspending main-actor hop in startMonitoring.
        self.maxRegionMonitoringDistance = manager.maximumRegionMonitoringDistance
        super.init()
        manager.delegate = self
    }

    var monitoredRegionIdentifiers: Set<String> {
        ownedRegionIdentifiers
    }

    func setOnTransition(_ handler: GeofenceTransitionHandler?) {
        onTransition = handler
    }

    func startMonitoring(identifier: String, center: LocationData, radius: Double, transitionTypes: Set<GeofenceTransition>) async {
        guard await checkAlwaysAuthorization() else { return }

        let coordinate = CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            logger.geofenceInvalidCoordinatesForRegion(identifier)
            return
        }

        let clampedRadius = min(radius, maxRegionMonitoringDistance)
        let region = CLCircularRegion(center: coordinate, radius: clampedRadius, identifier: identifier)
        region.notifyOnEntry = transitionTypes.contains(.enter)
        region.notifyOnExit = transitionTypes.contains(.exit)

        // Atomic on the actor executor: insert into the ownership set and dispatch the OS
        // call without any await between them. A concurrent stop cannot interleave here
        // because there is no suspension point. The OS call itself runs later on the main
        // actor; subsequent stop dispatches submitted afterwards run after it (FIFO).
        ownedRegionIdentifiers.insert(identifier)
        let locationManager = manager
        Task { @MainActor in locationManager.startMonitoring(for: region) }
    }

    func stopMonitoring(identifier: String) async {
        guard ownedRegionIdentifiers.remove(identifier) != nil else { return }
        let locationManager = manager
        Task { @MainActor in
            if let region = locationManager.monitoredRegions.first(where: { $0.identifier == identifier }) {
                locationManager.stopMonitoring(for: region)
            }
        }
    }

    func stopMonitoringAll() async {
        let identifiers = ownedRegionIdentifiers
        ownedRegionIdentifiers.removeAll()
        let locationManager = manager
        Task { @MainActor in
            for identifier in identifiers {
                if let region = locationManager.monitoredRegions.first(where: { $0.identifier == identifier }) {
                    locationManager.stopMonitoring(for: region)
                }
            }
        }
    }

    // MARK: - CLLocationManagerDelegate (nonisolated; re-enter actor via Task)

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }
        let identifier = circularRegion.identifier
        let location = locationDataFrom(manager)
        Task { await self.handleTransition(identifier: identifier, transition: .enter, location: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }
        let identifier = circularRegion.identifier
        let location = locationDataFrom(manager)
        Task { await self.handleTransition(identifier: identifier, transition: .exit, location: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        guard let identifier = region?.identifier else { return }
        Task { await self.handleMonitoringFailure(identifier: identifier, error: error) }
    }

    // MARK: - Private (actor-isolated)

    private func handleTransition(identifier: String, transition: GeofenceTransition, location: LocationData?) {
        guard ownedRegionIdentifiers.contains(identifier) else { return }
        onTransition?(identifier, transition, location)
    }

    private func handleMonitoringFailure(identifier: String, error: Error) {
        guard ownedRegionIdentifiers.remove(identifier) != nil else { return }
        logger.geofenceMonitoringFailed(region: identifier, error: error)
    }

    private func checkAlwaysAuthorization() async -> Bool {
        let locationManager = manager
        let status: CLAuthorizationStatus = await MainActor.run {
            if #available(iOS 14.0, *) {
                return locationManager.authorizationStatus
            } else {
                return CLLocationManager.authorizationStatus()
            }
        }

        guard status == .authorizedAlways else {
            if !hasLoggedPermissionWarning {
                hasLoggedPermissionWarning = true
                logger.geofenceAlwaysAuthorizationRequired(currentStatus: status)
            }
            return false
        }
        return true
    }

    private nonisolated func locationDataFrom(_ manager: CLLocationManager) -> LocationData? {
        guard let location = manager.location,
              CLLocationCoordinate2DIsValid(location.coordinate)
        else {
            return nil
        }
        return LocationData(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
}
