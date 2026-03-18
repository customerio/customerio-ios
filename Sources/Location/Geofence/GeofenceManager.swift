import CioInternalCommon
import CoreLocation
import Foundation

// sourcery: AutoMockable
/// Protocol for handling geofence transition events.
protocol GeofenceEventHandler: AnyObject {
    /// Called when a user enters a geofence region.
    func onGeofenceEntered(_ region: GeofenceRegion, userLocation: CLLocation?) async

    /// Called when a user exits a geofence region.
    func onGeofenceExited(_ region: GeofenceRegion, userLocation: CLLocation?) async

    /// Called when a user dwells in a geofence region.
    func onGeofenceDwelled(_ region: GeofenceRegion, userLocation: CLLocation?) async
}

// sourcery: AutoMockable
// sourcery: AutoDependencyInjection
/// Manages CLLocationManager for geofence region monitoring.
///
/// This actor wraps CLLocationManager and handles region monitoring callbacks,
/// forwarding events to the GeofenceEventHandler.
///
/// Must be created on the main thread so CLLocationManager setup runs on main.
protocol GeofenceManaging: AnyObject {
    /// Starts monitoring a geofence region.
    func startMonitoring(region: GeofenceRegion) async

    /// Stops monitoring a geofence region.
    func stopMonitoring(regionId: String) async

    /// Stops monitoring all geofence regions.
    func stopMonitoringAll() async

    /// Returns the IDs of all currently monitored regions.
    func getMonitoredRegionIds() async -> [String]

    /// Sets the event handler for geofence transitions.
    func setEventHandler(_ handler: GeofenceEventHandler?) async
}

/// Implementation of GeofenceManaging using CLLocationManager.
actor GeofenceManager: NSObject, GeofenceManaging, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private let logger: Logger
    private weak var eventHandler: GeofenceEventHandler?
    private var regionMap: [String: GeofenceRegion] = [:]
    private var dwellTimers: [String: Task<Void, Never>] = [:]

    init(logger: Logger, eventHandler: GeofenceEventHandler? = nil) {
        self.manager = CLLocationManager()
        self.logger = logger
        self.eventHandler = eventHandler
        super.init()
        manager.delegate = self
    }

    /// Sets the event handler for geofence transitions.
    /// Used to resolve circular dependencies during initialization.
    func setEventHandler(_ handler: GeofenceEventHandler?) async {
        eventHandler = handler
    }

    func startMonitoring(region: GeofenceRegion) async {
        let clRegion = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: region.latitude, longitude: region.longitude),
            radius: region.radius,
            identifier: region.id
        )
        clRegion.notifyOnEntry = true
        clRegion.notifyOnExit = true

        regionMap[region.id] = region

        Task { @MainActor in
            manager.startMonitoring(for: clRegion)
        }

        logger.geofenceAdded(
            id: region.id,
            latitude: region.latitude,
            longitude: region.longitude,
            radius: region.radius
        )
    }

    func stopMonitoring(regionId: String) async {
        regionMap.removeValue(forKey: regionId)
        dwellTimers[regionId]?.cancel()
        dwellTimers.removeValue(forKey: regionId)

        Task { @MainActor in
            if let clRegion = manager.monitoredRegions.first(where: { $0.identifier == regionId }) {
                manager.stopMonitoring(for: clRegion)
            }
        }

        logger.geofenceRemoved(id: regionId)
    }

    func stopMonitoringAll() async {
        let count = regionMap.count
        regionMap.removeAll()

        for timer in dwellTimers.values {
            timer.cancel()
        }
        dwellTimers.removeAll()

        Task { @MainActor in
            for region in manager.monitoredRegions {
                manager.stopMonitoring(for: region)
            }
        }

        logger.geofenceAllRemoved(count: count)
    }

    func getMonitoredRegionIds() async -> [String] {
        Array(regionMap.keys)
    }

    // MARK: - CLLocationManagerDelegate (nonisolated; re-enter actor via Task)

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }
        Task { await self.handleRegionEntry(circularRegion) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }
        Task { await self.handleRegionExit(circularRegion) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        if let region {
            Task { await self.handleMonitoringError(region.identifier, error: error) }
        }
    }

    // MARK: - Private (actor-isolated)

    private func handleRegionEntry(_ clRegion: CLCircularRegion) async {
        guard let geofenceRegion = regionMap[clRegion.identifier] else { return }

        logger.geofenceEntered(id: geofenceRegion.id, name: geofenceRegion.name)

        // Get current location for distance calculation
        let location = await getCurrentLocation()

        // Notify entry event
        if let handler = eventHandler {
            await handler.onGeofenceEntered(geofenceRegion, userLocation: location)
        }

        // Start dwell timer
        startDwellTimer(for: geofenceRegion)
    }

    private func handleRegionExit(_ clRegion: CLCircularRegion) async {
        guard let geofenceRegion = regionMap[clRegion.identifier] else { return }

        logger.geofenceExited(id: geofenceRegion.id, name: geofenceRegion.name)

        // Cancel any active dwell timer
        dwellTimers[geofenceRegion.id]?.cancel()
        dwellTimers.removeValue(forKey: geofenceRegion.id)

        // Get current location for distance calculation
        let location = await getCurrentLocation()

        // Notify exit event
        if let handler = eventHandler {
            await handler.onGeofenceExited(geofenceRegion, userLocation: location)
        }
    }

    private func handleMonitoringError(_ regionId: String, error: Error) {
        logger.geofenceMonitoringFailed(id: regionId, error: error)
    }

    private func startDwellTimer(for region: GeofenceRegion) {
        // Cancel existing timer if any
        dwellTimers[region.id]?.cancel()

        let dwellTimeSeconds = Double(region.effectiveDwellTimeMs) / 1000.0
        let regionId = region.id

        let timer = Task { [weak self, weak eventHandler] in
            do {
                try await Task.sleep(nanoseconds: UInt64(dwellTimeSeconds * 1000000000))

                // Check if still in region and timer wasn't cancelled
                guard !Task.isCancelled else { return }
                guard let self else { return }

                await self.logger.geofenceDwelled(id: region.id, name: region.name)

                // Get current location for distance calculation
                let location = await self.getCurrentLocation()

                // Notify dwell event
                if let handler = eventHandler {
                    await handler.onGeofenceDwelled(region, userLocation: location)
                }

                // Clean up timer
                await self.removeDwellTimer(regionId: regionId)
            } catch {
                // Task was cancelled or sleep interrupted
            }
        }

        dwellTimers[region.id] = timer
    }

    private func removeDwellTimer(regionId: String) {
        dwellTimers.removeValue(forKey: regionId)
    }

    private func getCurrentLocation() async -> CLLocation? {
        let m = manager
        return await MainActor.run {
            m.location
        }
    }
}
