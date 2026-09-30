import CioInternalCommon
import CoreLocation
import Foundation

/// Tracks its own regions because `monitoredRegions` is shared app-wide. Registration stays
/// synchronous so the ownership update and the OS call have no reentrancy point between them.
@MainActor
final class CoreLocationGeofenceMonitor: NSObject, GeofenceRegionMonitoring, @preconcurrency CLLocationManagerDelegate {
    /// The SDK never requests permission. `.foregroundOnly` still registers; regions fire only while
    /// foregrounded.
    enum PermissionTier: Equatable {
        case backgroundDelivery
        case foregroundOnly
        case blocked
    }

    let manager: CLLocationManager
    let logger: Logger
    let movementFixResolver: MovementFixResolver
    var onTransition: GeofenceTransitionHandler?
    private var onAuthorizationChanged: GeofenceAuthorizationChangedHandler?
    private var lastLoggedPermissionTier: PermissionTier?
    var ownedRegionIdentifiers: Set<String> = []

    var pendingEvents: [PendingRegionEvent] = []
    var isDrainingPendingEvents = false
    static let maxPendingEvents = 64

    let dateUtil: DateUtil

    init(logger: Logger, dateUtil: DateUtil = DIGraphShared.shared.dateUtil) {
        self.dateUtil = dateUtil
        self.manager = CLLocationManager()
        self.logger = logger
        self.movementFixResolver = MovementFixResolver(
            logger: logger,
            backgroundTaskRunner: GeofenceBackgroundTime.runner(name: "io.customer.geofence.movement-fix"),
            dateUtil: dateUtil
        )
        super.init()
        manager.delegate = self
    }

    var monitoredRegionIdentifiers: Set<String> {
        ownedRegionIdentifiers
    }

    var maximumMonitoringRadius: Double {
        manager.maximumRegionMonitoringDistance
    }

    var osMonitoredRegionIdentifiers: Set<String> {
        Set(manager.monitoredRegions.map(\.identifier))
    }

    func adoptExistingRegions(matching identifiers: Set<String>, records _: [String: MonitorRegionRecord]) {
        let adopted = identifiers.intersection(osMonitoredRegionIdentifiers)
        guard !adopted.isEmpty else { return }
        ownedRegionIdentifiers.formUnion(adopted)
        logger.geofenceRegionsAdopted(identifiers: Array(adopted))
    }

    func setOnTransition(_ handler: GeofenceTransitionHandler?) {
        onTransition = handler
        drainPendingEventsIfReady()
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

    @discardableResult
    func setMonitoredRegions(_ regions: [GeofenceRegionRequest]) -> GeofenceRegionDiff {
        let desiredIdentifiers = Set(regions.map(\.identifier))
        var removed: Set<String> = []
        for identifier in ownedRegionIdentifiers.subtracting(desiredIdentifiers) {
            stopMonitoring(identifier: identifier)
            removed.insert(identifier)
        }
        var added: Set<String> = []
        for region in regions where !isRegisteredUnchanged(region) {
            // `startMonitoring(for:)` replaces by id anyway; the stop keeps both monitors' OS
            // sequence identical.
            stopMonitoring(identifier: region.identifier)
            startMonitoring(
                identifier: region.identifier,
                center: region.center,
                radius: region.radius,
                transitionTypes: region.transitionTypes
            )
            // `startMonitoring` may have refused it; count only regions the OS took.
            if ownedRegionIdentifiers.contains(region.identifier) { added.insert(region.identifier) }
        }
        return GeofenceRegionDiff(added: added, removed: removed)
    }

    /// Geometry from the live `CLCircularRegion`, not our bookkeeping, so a region the OS reshaped or
    /// dropped re-registers.
    private func isRegisteredUnchanged(_ region: GeofenceRegionRequest) -> Bool {
        guard ownedRegionIdentifiers.contains(region.identifier),
              let existing = manager.monitoredRegions.first(where: { $0.identifier == region.identifier }) as? CLCircularRegion
        else { return false }
        var registeredTypes: Set<GeofenceTransition> = []
        if existing.notifyOnEntry { registeredTypes.insert(.enter) }
        if existing.notifyOnExit { registeredTypes.insert(.exit) }
        return region.matchesRegistered(
            center: LocationData(latitude: existing.center.latitude, longitude: existing.center.longitude),
            radius: existing.radius,
            transitionTypes: registeredTypes,
            clampedTo: manager.maximumRegionMonitoringDistance
        )
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        handleRegionEvent(region, transition: .enter)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        handleRegionEvent(region, transition: .exit)
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        guard let identifier = region?.identifier,
              ownedRegionIdentifiers.remove(identifier) != nil
        else { return }
        logger.geofenceMonitoringFailed(region: identifier, error: error)
    }

    // Unfiltered: an improvement re-attempts registration, and a downgrade disarms visits. The
    // iOS 14+ call on delegate set is harmless.
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

    var osCachedFix: CLLocation? { manager.location }

    func currentLocationData() -> LocationData? {
        guard let location = bestKnownFix() else { return nil }
        return LocationData(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
}

// MARK: - DI

extension DIGraphShared {
    /// Hand-written: Sourcery's eager-init test reads it from a non-isolated context, which clashes
    /// with `@MainActor`.
    @MainActor
    var geofenceMonitor: GeofenceRegionMonitoring {
        // Typed as the protocol: overrides are keyed by it.
        let overridden: GeofenceRegionMonitoring? = getOverriddenInstance()
        if let overridden { return overridden }
        // iOS 18+ only: `CLServiceSession` is the documented way to keep CLMonitor delivering in
        // the background.
        if #available(iOS 18.0, *) {
            return CLMonitorGeofenceMonitor.shared
        }
        return CoreLocationGeofenceMonitor.shared
    }
}

extension CoreLocationGeofenceMonitor: GeofenceFixSelecting {
    @MainActor
    static let shared = CoreLocationGeofenceMonitor(logger: DIGraphShared.shared.logger)
}
