import CioInternalCommon
import Foundation

/// Owns "should we sync?" and "sync to pipeline" logic for location. Caches every location; sends track via optional DataPipelineTracking when the 24h + 1 km filter allows and user is identified.
actor LocationSyncCoordinator {
    private let storage: LastLocationStorage
    private let filter: LocationFilter
    private let dataPipeline: DataPipelineTracking?
    private let dateUtil: DateUtil
    private let logger: Logger
    private let eventBusHandler: EventBusHandler

    init(
        storage: LastLocationStorage,
        filter: LocationFilter,
        dataPipeline: DataPipelineTracking?,
        dateUtil: DateUtil,
        logger: Logger,
        eventBusHandler: EventBusHandler
    ) {
        self.storage = storage
        self.filter = filter
        self.dataPipeline = dataPipeline
        self.dateUtil = dateUtil
        self.logger = logger
        self.eventBusHandler = eventBusHandler
    }

    /// Called for every new location (from setLastKnownLocation or requestLocationUpdate). Always updates cache; sends track via pipeline when filter allows and user is identified.
    func processLocationUpdate(_ location: LocationData) {
        storage.setCachedLocation(location)
        // Signals the geofence first-run-refresh re-arm. Routed through the EventBus so
        // geofence can observe fixes without a direct reference to this coordinator.
        eventBusHandler.postEvent(LocationAcquiredEvent(location: location))

        guard filter.shouldSyncToServer(newLocation: location) else {
            logger.locationSyncFiltered()
            return
        }

        trySendLocationTrack(location)
    }

    /// Called when ProfileIdentifiedEvent is received. Syncs cached location if present and the 24h + 1 km filter allows.
    func syncCachedLocationIfNeeded() {
        guard let cached = storage.getCachedLocation() else {
            return
        }
        guard filter.shouldSyncToServer(newLocation: cached) else {
            logger.locationSyncFiltered()
            return
        }
        trySendLocationTrack(cached)
    }

    /// Clears cached location and last synced state. Location cache is cleared synchronously via LocationProfileEnrichmentProvider.resetContext() on analytics reset; this method remains for tests and symmetry.
    func clearCache() {
        storage.clearCache()
        logger.locationCacheCleared()
    }

    private func trySendLocationTrack(_ location: LocationData) {
        guard let pipeline = dataPipeline else { return }
        guard pipeline.isUserIdentified else { return }

        let properties: [String: Any] = [
            "latitude": location.latitude,
            "longitude": location.longitude
        ]
        pipeline.track(name: "CIO Location Update", properties: properties)
        storage.recordLastSync(location: location, timestamp: dateUtil.now)
    }
}
