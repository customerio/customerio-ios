import CioInternalCommon
import CoreLocation
import Foundation

/// Implementation of GeofenceServices that manages geofence regions.
///
/// This actor coordinates geofence operations, persistence, and event delivery.
/// It ensures thread-safe access to the geofence state and handles the interaction
/// between the GeofenceManager (CLLocationManager wrapper) and the DataPipeline.
actor GeofenceServicesImpl: GeofenceServices, GeofenceEventHandler {
    private let config: LocationConfig
    private let logger: Logger
    private let preferenceStore: GeofencePreferenceStore
    private let geofenceManager: GeofenceManaging
    private let dataPipeline: DataPipelineTracking?

    private var activeGeofences: [String: GeofenceRegion] = [:]

    init(
        config: LocationConfig,
        logger: Logger,
        preferenceStore: GeofencePreferenceStore,
        geofenceManager: GeofenceManaging,
        dataPipeline: DataPipelineTracking?
    ) {
        self.config = config
        self.logger = logger
        self.preferenceStore = preferenceStore
        self.geofenceManager = geofenceManager
        self.dataPipeline = dataPipeline
    }

    /// Restores geofences from persistent storage.
    /// Call this during module initialization.
    func restoreFromStorage() async {
        guard config.mode != .off else { return }

        let storedGeofences = preferenceStore.loadGeofences()
        guard !storedGeofences.isEmpty else { return }

        logger.geofenceRestoredFromStorage(count: storedGeofences.count)

        for region in storedGeofences {
            activeGeofences[region.id] = region
            await geofenceManager.startMonitoring(region: region)
        }
    }

    // MARK: - GeofenceServices Protocol

    nonisolated func addGeofences(regions: [GeofenceRegion]) {
        Task { await addGeofencesImpl(regions: regions) }
    }

    nonisolated func removeGeofences(ids: [String]) {
        Task { await removeGeofencesImpl(ids: ids) }
    }

    nonisolated func removeAllGeofences() {
        Task { await removeAllGeofencesImpl() }
    }

    nonisolated func getActiveGeofences() -> [GeofenceRegion] {
        // This is a synchronous API but we need to access actor state
        // Return empty array here; users should not rely on synchronous access to actor state
        // In a real implementation, this would need to be async or use a different pattern
        []
    }

    /// Async version of getActiveGeofences for internal use
    func getActiveGeofencesAsync() -> [GeofenceRegion] {
        Array(activeGeofences.values)
    }

    // MARK: - Private Implementation

    private func addGeofencesImpl(regions: [GeofenceRegion]) async {
        guard config.mode != .off else {
            logger.trackingDisabledIgnoringSetLastKnownLocation()
            return
        }

        var regionsToAdd: [GeofenceRegion] = []

        for region in regions {
            // Check for duplicate coordinates (but allow same ID to update)
            if let existingRegion = findRegionWithSameCoordinates(region),
               existingRegion.id != region.id {
                logger.geofenceDuplicateCoordinates(
                    existingId: existingRegion.id,
                    newId: region.id,
                    latitude: region.latitude,
                    longitude: region.longitude
                )
                continue
            }

            regionsToAdd.append(region)
        }

        // Add regions to active set
        for region in regionsToAdd {
            activeGeofences[region.id] = region
        }

        // Enforce iOS geofence limit
        await enforceLimitIfNeeded()

        // Start monitoring
        for region in regionsToAdd where activeGeofences[region.id] != nil {
            await geofenceManager.startMonitoring(region: region)
        }

        // Persist to storage
        persistActiveGeofences()
    }

    private func removeGeofencesImpl(ids: [String]) async {
        for id in ids where activeGeofences.removeValue(forKey: id) != nil {
            await geofenceManager.stopMonitoring(regionId: id)
        }

        persistActiveGeofences()
    }

    private func removeAllGeofencesImpl() async {
        activeGeofences.removeAll()
        await geofenceManager.stopMonitoringAll()
        preferenceStore.clearGeofences()
    }

    private func findRegionWithSameCoordinates(_ region: GeofenceRegion) -> GeofenceRegion? {
        activeGeofences.values.first { existing in
            existing.latitude == region.latitude &&
                existing.longitude == region.longitude
        }
    }

    private func enforceLimitIfNeeded() async {
        let currentCount = activeGeofences.count
        guard currentCount > GeofenceConstants.MAX_GEOFENCES else { return }

        let excess = currentCount - GeofenceConstants.MAX_GEOFENCES

        // Remove oldest geofences (we don't have timestamps, so just remove arbitrary ones)
        let regionsToRemove = Array(activeGeofences.values.prefix(excess))
        let idsToRemove = regionsToRemove.map(\.id)

        for id in idsToRemove {
            activeGeofences.removeValue(forKey: id)
            await geofenceManager.stopMonitoring(regionId: id)
        }

        logger.geofenceLimitExceeded(limit: GeofenceConstants.MAX_GEOFENCES, removedCount: excess)
    }

    private func persistActiveGeofences() {
        let regions = Array(activeGeofences.values)
        preferenceStore.saveGeofences(regions)
    }

    // MARK: - GeofenceEventHandler Protocol

    func onGeofenceEntered(_ region: GeofenceRegion, userLocation: CLLocation?) async {
        sendGeofenceEvent(
            eventName: GeofenceConstants.EVENT_GEOFENCE_ENTERED,
            transitionType: "enter",
            region: region,
            userLocation: userLocation
        )
    }

    func onGeofenceExited(_ region: GeofenceRegion, userLocation: CLLocation?) async {
        sendGeofenceEvent(
            eventName: GeofenceConstants.EVENT_GEOFENCE_EXITED,
            transitionType: "exit",
            region: region,
            userLocation: userLocation
        )
    }

    func onGeofenceDwelled(_ region: GeofenceRegion, userLocation: CLLocation?) async {
        sendGeofenceEvent(
            eventName: GeofenceConstants.EVENT_GEOFENCE_DWELLED,
            transitionType: "dwell",
            region: region,
            userLocation: userLocation
        )
    }

    // MARK: - Event Delivery

    private func sendGeofenceEvent(
        eventName: String,
        transitionType: String,
        region: GeofenceRegion,
        userLocation: CLLocation?
    ) {
        guard let dataPipeline else {
            logger.geofenceEventSkippedDataPipelineUnavailable(eventType: transitionType, id: region.id)
            return
        }

        guard dataPipeline.isUserIdentified else {
            logger.geofenceEventSkippedUserNotIdentified(eventType: transitionType, id: region.id)
            return
        }

        var properties: [String: Any] = [
            "geofence_id": region.id,
            "latitude": region.latitude,
            "longitude": region.longitude,
            "radius": region.radius,
            "transition_type": transitionType
        ]

        if let name = region.name {
            properties["geofence_name"] = name
        }

        // Calculate distance if user location is available
        if let userLocation {
            let geofenceLocation = CLLocation(
                latitude: region.latitude,
                longitude: region.longitude
            )
            let distance = userLocation.distance(from: geofenceLocation)
            properties["distance"] = distance
        }

        // Merge custom data
        if let customData = region.customData {
            for (key, value) in customData {
                properties[key] = value
            }
        }

        dataPipeline.track(name: eventName, properties: properties)
    }
}

/// Uninitialized implementation that logs errors when used.
final class UninitializedGeofenceServices: GeofenceServices {
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func addGeofences(regions: [GeofenceRegion]) {
        logger.moduleNotInitialized()
    }

    func removeGeofences(ids: [String]) {
        logger.moduleNotInitialized()
    }

    func removeAllGeofences() {
        logger.moduleNotInitialized()
    }

    func getActiveGeofences() -> [GeofenceRegion] {
        logger.moduleNotInitialized()
        return []
    }
}
