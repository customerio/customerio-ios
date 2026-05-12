import CioInternalCommon
import CoreLocation
import Foundation

/// CLLocationManager-backed geofence region monitor.
///
/// `@MainActor`-isolated because CLLocationManager must be created and called on the main
/// thread, and its delegate callbacks arrive on main. State and OS calls share one
/// isolation domain, so the ownership-set update and the OS dispatch happen atomically with
/// no reentrancy point between them — no locks, no fire-and-forget Tasks, no FIFO assumption.
///
/// Tracks which regions this monitor owns so it does not interfere with regions
/// registered by the host app or other SDKs (CLLocationManager.monitoredRegions is shared app-wide).
@MainActor
final class CoreLocationGeofenceMonitor: NSObject, GeofenceRegionMonitoring, @preconcurrency CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private let logger: Logger
    private var onTransition: GeofenceTransitionHandler?
    private var hasLoggedPermissionWarning = false
    private var ownedRegionIdentifiers: Set<String> = []

    init(logger: Logger) {
        self.manager = CLLocationManager()
        self.logger = logger
        super.init()
        manager.delegate = self
    }

    var monitoredRegionIdentifiers: Set<String> {
        ownedRegionIdentifiers
    }

    func setOnTransition(_ handler: GeofenceTransitionHandler?) {
        onTransition = handler
    }

    func startMonitoring(identifier: String, center: LocationData, radius: Double, transitionTypes: Set<GeofenceTransition>) {
        guard checkAlwaysAuthorization() else { return }

        let coordinate = CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            logger.geofenceInvalidCoordinatesForRegion(identifier)
            return
        }

        let clampedRadius = min(radius, manager.maximumRegionMonitoringDistance)
        let region = CLCircularRegion(center: coordinate, radius: clampedRadius, identifier: identifier)
        region.notifyOnEntry = transitionTypes.contains(.enter)
        region.notifyOnExit = transitionTypes.contains(.exit)

        ownedRegionIdentifiers.insert(identifier)
        manager.startMonitoring(for: region)
    }

    func stopMonitoring(identifier: String) {
        guard ownedRegionIdentifiers.remove(identifier) != nil else { return }
        if let region = manager.monitoredRegions.first(where: { $0.identifier == identifier }) {
            manager.stopMonitoring(for: region)
        }
    }

    func stopMonitoringAll() {
        let identifiers = ownedRegionIdentifiers
        ownedRegionIdentifiers.removeAll()
        for identifier in identifiers {
            if let region = manager.monitoredRegions.first(where: { $0.identifier == identifier }) {
                manager.stopMonitoring(for: region)
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion,
              ownedRegionIdentifiers.contains(circularRegion.identifier)
        else { return }
        onTransition?(circularRegion.identifier, .enter, currentLocationData())
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion,
              ownedRegionIdentifiers.contains(circularRegion.identifier)
        else { return }
        onTransition?(circularRegion.identifier, .exit, currentLocationData())
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        guard let identifier = region?.identifier,
              ownedRegionIdentifiers.remove(identifier) != nil
        else { return }
        logger.geofenceMonitoringFailed(region: identifier, error: error)
    }

    // MARK: - Private

    private func checkAlwaysAuthorization() -> Bool {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = manager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
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

    private func currentLocationData() -> LocationData? {
        guard let location = manager.location,
              CLLocationCoordinate2DIsValid(location.coordinate)
        else {
            return nil
        }
        return LocationData(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
}
