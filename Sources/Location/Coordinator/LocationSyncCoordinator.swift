import CioInternalCommon
import Foundation

/// Owns "should we sync?" and "sync to pipeline" logic for location. Caches every location; posts TrackLocationEvent when the 24h + 1 km filter allows. Identification is enforced by DataPipeline before tracking.
actor LocationSyncCoordinator {
    private let storage: LastLocationStorage
    private let filter: LocationFilter
    private let eventBusHandler: EventBusHandler
    private let logger: Logger

    init(
        storage: LastLocationStorage,
        filter: LocationFilter,
        eventBusHandler: EventBusHandler,
        logger: Logger
    ) {
        self.storage = storage
        self.filter = filter
        self.eventBusHandler = eventBusHandler
        self.logger = logger
    }

    /// Called for every new location (from setLastKnownLocation or requestLocationUpdate). Always updates cache; posts TrackLocationEvent when filter allows. Last sync is recorded only when DataPipeline actually tracks (LocationTrackedEvent).
    func processLocationUpdate(_ location: LocationData) {
        storage.setCachedLocation(location)

        guard filter.shouldSyncToServer(newLocation: location) else {
            logger.locationSyncFiltered()
            return
        }

        postTrackLocationEvent(location)
    }

    /// Called when ProfileIdentifiedEvent is received. Syncs cached location if present and the 24h + 1 km filter allows. Last sync is recorded only when DataPipeline actually tracks (LocationTrackedEvent).
    func syncCachedLocationIfNeeded() {
        guard let cached = storage.getCachedLocation() else {
            return
        }
        guard filter.shouldSyncToServer(newLocation: cached) else {
            logger.locationSyncFiltered()
            return
        }
        postTrackLocationEvent(cached)
    }

    /// Called when LocationTrackedEvent is received. Records the actual tracked location and timestamp so filter uses the correct reference (cache may have changed since the event was posted).
    func recordLastSyncWhenTracked(location: LocationData, timestamp: Date) {
        storage.recordLastSync(location: location, timestamp: timestamp)
    }

    /// Called when ResetEvent is received. Clears cached location and last synced state.
    func clearCache() {
        storage.clearCache()
        logger.locationCacheCleared()
    }

    private func postTrackLocationEvent(_ location: LocationData) {
        eventBusHandler.postEvent(TrackLocationEvent(location: location))
    }
}
