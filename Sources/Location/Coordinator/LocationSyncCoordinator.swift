import CioInternalCommon
import Foundation

/// Owns "should we sync?" and "sync to pipeline" logic for location. Caches every location; sends track via optional DataPipelineTracking when the 24h + 1 km filter allows and user is identified.
actor LocationSyncCoordinator {
    private let storage: LastLocationStorage
    private let filter: LocationFilter
    private let dataPipeline: DataPipelineTracking?
    private let dateUtil: DateUtil
    private let logger: Logger
    private var onLocationProcessed: (@Sendable (LocationData) -> Void)?

    init(
        storage: LastLocationStorage,
        filter: LocationFilter,
        dataPipeline: DataPipelineTracking?,
        dateUtil: DateUtil,
        logger: Logger
    ) {
        self.storage = storage
        self.filter = filter
        self.dataPipeline = dataPipeline
        self.dateUtil = dateUtil
        self.logger = logger
    }

    /// Called for every new location (from setLastKnownLocation or requestLocationUpdate). Always updates cache; sends track via pipeline when filter allows and user is identified.
    func processLocationUpdate(_ location: LocationData) {
        storage.setCachedLocation(location)
        // Used by the geofence first-run race rearm in `LocationModuleState`.
        onLocationProcessed?(location)

        guard filter.shouldSyncToServer(newLocation: location) else {
            logger.locationSyncFiltered()
            return
        }

        trySendLocationTrack(location)
    }

    /// Registers an observer for every processed location. Used by the geofence module to
    /// re-arm a refresh that previously skipped due to no cached location.
    func setOnLocationProcessed(_ handler: (@Sendable (LocationData) -> Void)?) {
        onLocationProcessed = handler
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
