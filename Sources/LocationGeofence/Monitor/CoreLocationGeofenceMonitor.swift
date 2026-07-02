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
    /// Tier of capability available given the current `CLAuthorizationStatus`. The SDK never
    /// requests permission — the host app owns that — so the monitor adapts to whatever was
    /// granted: `.authorizedAlways` enables background delivery, `.authorizedWhenInUse` falls
    /// back to foreground-only (regions still register and fire while foregrounded),
    /// everything else skips registration.
    enum PermissionTier: Equatable {
        case backgroundDelivery
        case foregroundOnly
        case blocked
    }

    private let manager: CLLocationManager
    private let logger: Logger
    private var onTransition: GeofenceTransitionHandler?
    private var onAuthorizationChanged: GeofenceAuthorizationChangedHandler?
    private var lastLoggedPermissionTier: PermissionTier?
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

    var osMonitoredRegionIdentifiers: Set<String> {
        Set(manager.monitoredRegions.map(\.identifier))
    }

    func adoptExistingRegions(matching identifiers: Set<String>) {
        let adopted = identifiers.intersection(osMonitoredRegionIdentifiers)
        guard !adopted.isEmpty else { return }
        ownedRegionIdentifiers.formUnion(adopted)
        logger.geofenceRegionsAdopted(count: adopted.count)
    }

    func setOnTransition(_ handler: GeofenceTransitionHandler?) {
        onTransition = handler
    }

    func setOnAuthorizationChanged(_ handler: GeofenceAuthorizationChangedHandler?) {
        onAuthorizationChanged = handler
    }

    func startMonitoring(identifier: String, center: LocationData, radius: Double, transitionTypes: Set<GeofenceTransition>) {
        reportPermissionTier()
        guard Self.permissionTier(for: currentAuthorizationStatus()) != .blocked else { return }

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
        logger.geofenceRegionRegistered(identifier: identifier, latitude: center.latitude, longitude: center.longitude, radius: clampedRadius)
    }

    func stopMonitoring(identifier: String) {
        guard ownedRegionIdentifiers.remove(identifier) != nil else { return }
        if let region = manager.monitoredRegions.first(where: { $0.identifier == identifier }) {
            manager.stopMonitoring(for: region)
        }
        logger.geofenceRegionDeregistered(identifier: identifier)
    }

    func stopMonitoringAll() {
        let identifiers = ownedRegionIdentifiers
        ownedRegionIdentifiers.removeAll()
        for identifier in identifiers {
            if let region = manager.monitoredRegions.first(where: { $0.identifier == identifier }) {
                manager.stopMonitoring(for: region)
            }
        }
        if !identifiers.isEmpty {
            logger.geofenceRegionsCleared(identifiers: identifiers)
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let owned = ownedRegionIdentifiers.contains(region.identifier)
        logger.geofenceOsTransitionReceived(identifier: region.identifier, transition: .enter, observed: owned)
        guard let circularRegion = region as? CLCircularRegion, owned else { return }
        onTransition?(circularRegion.identifier, .enter, currentLocationData())
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let owned = ownedRegionIdentifiers.contains(region.identifier)
        logger.geofenceOsTransitionReceived(identifier: region.identifier, transition: .exit, observed: owned)
        guard let circularRegion = region as? CLCircularRegion, owned else { return }
        onTransition?(circularRegion.identifier, .exit, currentLocationData())
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        guard let identifier = region?.identifier,
              ownedRegionIdentifiers.remove(identifier) != nil
        else { return }
        logger.geofenceMonitoringFailed(region: identifier, error: error)
    }

    // iOS 14+ fires this on delegate set with the current status, and again on every change.
    // We surface it to callers so the bootstrap can re-attempt registration when permission
    // improves mid-process (the initial fire after delegate-set is harmless — the bootstrap
    // already read the current status synchronously before installing the handler).
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorizationChanged?()
    }

    // MARK: - Private

    nonisolated static func permissionTier(for status: CLAuthorizationStatus) -> PermissionTier {
        switch status {
        case .authorizedAlways:
            return .backgroundDelivery
        case .authorizedWhenInUse:
            return .foregroundOnly
        case .notDetermined, .restricted, .denied:
            return .blocked
        @unknown default:
            return .blocked
        }
    }

    func reportPermissionTier() {
        let status = currentAuthorizationStatus()
        let tier = Self.permissionTier(for: status)
        guard tier != lastLoggedPermissionTier else { return }
        lastLoggedPermissionTier = tier
        switch tier {
        case .blocked:
            logger.geofencePermissionUnavailable(currentStatus: status)
        case .foregroundOnly:
            logger.geofenceBackgroundDeliveryUnavailable(currentStatus: status)
        case .backgroundDelivery:
            logger.geofenceBackgroundDeliveryAvailable(currentStatus: status)
        }
    }

    private func currentAuthorizationStatus() -> CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return manager.authorizationStatus
        } else {
            return CLLocationManager.authorizationStatus()
        }
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

// MARK: - DI

extension DIGraphShared {
    /// Process-wide singleton. Hand-written rather than via Sourcery's `InjectRegisterShared`
    /// because that template's eager-init resolution test references the property from a
    /// non-isolated context, which clashes with `@MainActor` isolation propagated through
    /// `GeofenceRegionMonitoring`. The override check below mirrors the generated DI accessors
    /// so tests can still substitute via `di.override(value:forType:)`.
    @MainActor
    var geofenceMonitor: GeofenceRegionMonitoring {
        // Explicit type on the optional pins the generic `T` in `getOverriddenInstance()` to
        // the protocol — without it, Swift infers `T` as the concrete `CoreLocationGeofenceMonitor`
        // from the `??` right-hand side and the override lookup misses by key.
        let overridden: GeofenceRegionMonitoring? = getOverriddenInstance()
        return overridden ?? CoreLocationGeofenceMonitor.shared
    }
}

extension CoreLocationGeofenceMonitor {
    @MainActor
    static let shared = CoreLocationGeofenceMonitor(logger: DIGraphShared.shared.logger)
}
