import CioInternalCommon
import Foundation

/// Owns "should we sync?" and "sync to pipeline" logic for location. Caches every location; syncs to server only for identified users when the 24h + 1 km filter allows.
actor LocationSyncCoordinator {
    private let storage: LastLocationStorage
    private let filter: LocationFilter
    private let eventBusHandler: EventBusHandler
    private let identificationState: IdentificationStateProviding
    private let dateUtil: DateUtil
    private let logger: Logger

    init(
        storage: LastLocationStorage,
        filter: LocationFilter,
        eventBusHandler: EventBusHandler,
        identificationState: IdentificationStateProviding,
        dateUtil: DateUtil,
        logger: Logger
    ) {
        self.storage = storage
        self.filter = filter
        self.eventBusHandler = eventBusHandler
        self.identificationState = identificationState
        self.dateUtil = dateUtil
        self.logger = logger
    }

    /// Called for every new location (from setLastKnownLocation or requestLocationUpdate). Always updates cache; syncs to server only when identified and filter allows.
    func processLocationUpdate(_ location: LocationData) {
        storage.setCachedLocation(location)

        guard identificationState.isIdentified else {
            return
        }

        guard filter.shouldSyncToServer(newLocation: location) else {
            logger.locationSyncFiltered()
            return
        }

        let now = dateUtil.now
        postTrackLocationEvent(location)
        storage.recordLastSync(timestamp: now)
    }

    /// Called when ProfileIdentifiedEvent is received. If we have a cached location and user is identified, sync it and set last synced.
    func syncCachedLocationIfNeeded() {
        guard identificationState.isIdentified,
              let cached = storage.getCachedLocation()
        else {
            return
        }
        postTrackLocationEvent(cached)
        storage.recordLastSync(timestamp: dateUtil.now)
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
