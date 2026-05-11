import CioInternalCommon
import CoreLocation
import Foundation

/// CLLocationManager-backed geofence region monitor.
///
/// Must be created on the main thread (CLLocationManager requirement).
/// Delegate callbacks are forwarded to the `onTransition` handler along with the
/// manager's current location so callers have a fresh fix at transition time.
///
/// Tracks which regions this monitor owns so it does not interfere with regions
/// registered by the host app or other SDKs (CLLocationManager.monitoredRegions is shared app-wide).
///
/// All mutable state is protected by `lock` since CLLocationManager delegate callbacks
/// may fire on a different thread than the caller of start/stop methods.
final class CoreLocationGeofenceMonitor: NSObject, GeofenceRegionMonitoring, CLLocationManagerDelegate {
    var onTransition: GeofenceTransitionHandler? {
        get { lock.lock()
            defer { lock.unlock() }
            return _onTransition
        }
        set { lock.lock()
            defer { lock.unlock() }
            _onTransition = newValue
        }
    }

    private let manager: CLLocationManager
    private let logger: Logger
    private let lock = NSLock()
    private var _onTransition: GeofenceTransitionHandler?
    private var hasLoggedPermissionWarning = false
    private var ownedRegionIdentifiers: Set<String> = []

    /// Must be called on the main thread so CLLocationManager and delegate setup run on main.
    init(logger: Logger) {
        self.manager = CLLocationManager()
        self.logger = logger
        super.init()
        manager.delegate = self
    }

    var monitoredRegionIdentifiers: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return ownedRegionIdentifiers
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
        lock.lock()
        ownedRegionIdentifiers.insert(identifier)
        lock.unlock()

        manager.startMonitoring(for: region)
    }

    func stopMonitoring(identifier: String) {
        lock.lock()
        let removed = ownedRegionIdentifiers.remove(identifier) != nil
        lock.unlock()

        guard removed else { return }
        if let region = manager.monitoredRegions.first(where: { $0.identifier == identifier }) {
            manager.stopMonitoring(for: region)
        }
    }

    func stopMonitoringAll() {
        lock.lock()
        let identifiers = ownedRegionIdentifiers
        ownedRegionIdentifiers.removeAll()
        lock.unlock()

        for identifier in identifiers {
            if let region = manager.monitoredRegions.first(where: { $0.identifier == identifier }) {
                manager.stopMonitoring(for: region)
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }

        lock.lock()
        let isOwned = ownedRegionIdentifiers.contains(circularRegion.identifier)
        let handler = _onTransition
        lock.unlock()

        guard isOwned else { return }
        handler?(circularRegion.identifier, .enter, currentLocationData())
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }

        lock.lock()
        let isOwned = ownedRegionIdentifiers.contains(circularRegion.identifier)
        let handler = _onTransition
        lock.unlock()

        guard isOwned else { return }
        handler?(circularRegion.identifier, .exit, currentLocationData())
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        guard let identifier = region?.identifier else { return }

        lock.lock()
        let wasOwned = ownedRegionIdentifiers.remove(identifier) != nil
        lock.unlock()

        guard wasOwned else { return }
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
            lock.lock()
            let alreadyLogged = hasLoggedPermissionWarning
            hasLoggedPermissionWarning = true
            lock.unlock()

            if !alreadyLogged {
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
