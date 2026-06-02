import CioInternalCommon
import Foundation

/// Errors surfaced by `GeofenceSyncCoordinator` callers.
enum GeofenceSyncError: Error, Equatable {
    case noIdentifiedUser
    case alreadyInProgress
    case fetchFailed(GeofenceApiError)
}

/// Sync pipeline for the on-device geofence cache. Two entry points:
///
/// - `refresh(latitude:longitude:)` — fetch from the server, distance-filter, register,
///   persist. Gated on identified user, in-flight dedup, and freshness.
/// - `applyCachedRegistration(...)` — synchronously register from caller-fetched state,
///   used by cold-wake / boot / auth-change paths. Synchronous on the main actor so
///   `ownedRegionIdentifiers` is populated before the next yield — otherwise the OS may
///   deliver a queued cold-wake transition into an empty filter set.
protocol GeofenceSyncCoordinator: AutoMockable, Sendable {
    func refresh(latitude: Double, longitude: Double) async -> Result<Void, GeofenceSyncError>
    @MainActor
    func applyCachedRegistration(
        cachedRegions: [Geofence],
        anchor: LocationData?,
        config: GeofenceConfig?,
        userId: String?
    )
}

/// `@unchecked Sendable`: stored `Logger` and `DateUtil` are existentials of protocols
/// not declared `: Sendable`. Both are `let` references injected once and never mutated;
/// the only mutable state is the `Synchronized<Bool>` dedup gate.
final class GeofenceSyncCoordinatorImpl: GeofenceSyncCoordinator, @unchecked Sendable {
    private let apiService: GeofenceApiService
    private let storage: GeofenceSyncStorage
    private let monitor: GeofenceRegionMonitoring
    private let contextStore: BackgroundDeliveryContextStore
    private let distanceFilter: GeofenceDistanceFilter
    private let dateUtil: DateUtil
    private let logger: Logger
    private let refreshInProgress = Synchronized<Bool>(false)

    init(
        apiService: GeofenceApiService,
        storage: GeofenceSyncStorage,
        monitor: GeofenceRegionMonitoring,
        contextStore: BackgroundDeliveryContextStore,
        distanceFilter: GeofenceDistanceFilter = GeofenceDistanceFilter(),
        dateUtil: DateUtil,
        logger: Logger
    ) {
        self.apiService = apiService
        self.storage = storage
        self.monitor = monitor
        self.contextStore = contextStore
        self.distanceFilter = distanceFilter
        self.dateUtil = dateUtil
        self.logger = logger
    }

    func refresh(latitude: Double, longitude: Double) async -> Result<Void, GeofenceSyncError> {
        // Concurrent calls return `.alreadyInProgress` (not `.success`) so callers can
        // distinguish a skip-due-to-dedup from a real completion.
        let acquired: Bool = refreshInProgress.mutating { inProgress in
            if inProgress { return false }
            inProgress = true
            return true
        }
        guard acquired else {
            logger.geofenceSyncSkipped(reason: "refresh already in progress")
            return .failure(.alreadyInProgress)
        }
        defer { refreshInProgress.wrappedValue = false }

        guard let userId = contextStore.currentUserId, !userId.isEmpty else {
            logger.geofenceSyncSkipped(reason: "no identified user")
            return .failure(.noIdentifiedUser)
        }

        let cachedConfig = await storage.getCachedConfig()
        if let lastSync = await storage.getLastSync() {
            let expiry = cachedConfig?.remoteFetchRefreshExpiry ?? GeofenceConstants.staleSyncInterval
            if dateUtil.now.timeIntervalSince(lastSync.timestamp) < expiry {
                logger.geofenceSyncSkippedFresh()
                return .success(())
            }
        }

        let fetchResult = await awaitApiFetch(latitude: latitude, longitude: longitude)
        let response: GeofenceApiResponse
        switch fetchResult {
        case .success(let value):
            response = value
        case .failure(let error):
            logger.geofenceSyncFetchFailed(error: error)
            return .failure(.fetchFailed(error))
        }

        let parsedConfig = response.toDomainConfig()
        let regions = response.toDomainRegions()
        let effectiveConfig = parsedConfig ?? cachedConfig ?? .fallback
        let anchor = LocationData(latitude: latitude, longitude: longitude)
        let nearest = distanceFilter.nearest(regions, to: anchor, limit: effectiveConfig.maxBusinessGeofences)
        await MainActor.run {
            registerWithOsSync(
                businessRegions: nearest,
                movementTriggerLocation: anchor,
                movementTriggerRadius: effectiveConfig.localRefreshTriggerRadius
            )
        }

        await storage.setCachedGeofences(regions)
        // Skip overwriting when the response did not ship a config — a previously cached
        // value must not be clobbered by a null parse from a partial-rollout backend.
        if let parsedConfig {
            await storage.setCachedConfig(parsedConfig)
        }
        await storage.recordSync(timestamp: dateUtil.now, location: anchor)
        logger.geofenceSyncCompleted(registeredCount: nearest.count)
        return .success(())
    }

    @MainActor
    func applyCachedRegistration(
        cachedRegions: [Geofence],
        anchor: LocationData?,
        config: GeofenceConfig?,
        userId: String?
    ) {
        guard let userId, !userId.isEmpty else {
            logger.geofenceSyncSkipped(reason: "no identified user")
            return
        }
        guard !cachedRegions.isEmpty else {
            logger.geofenceSyncSkipped(reason: "no cached regions to restore")
            return
        }
        // Need an anchor to distance-filter and to center the movement trigger. Skipping
        // when absent is safer than re-using an arbitrary location.
        guard let anchor else {
            logger.geofenceSyncSkipped(reason: "no last-sync anchor to restore from")
            return
        }
        let acquired: Bool = refreshInProgress.mutating { inProgress in
            if inProgress { return false }
            inProgress = true
            return true
        }
        guard acquired else {
            logger.geofenceSyncSkipped(reason: "restore already in progress")
            return
        }
        defer { refreshInProgress.wrappedValue = false }

        let effectiveConfig = config ?? .fallback
        let nearest = distanceFilter.nearest(cachedRegions, to: anchor, limit: effectiveConfig.maxBusinessGeofences)
        registerWithOsSync(
            businessRegions: nearest,
            movementTriggerLocation: anchor,
            movementTriggerRadius: effectiveConfig.localRefreshTriggerRadius
        )
        logger.geofenceSyncCompleted(registeredCount: nearest.count)
    }

    private func awaitApiFetch(
        latitude: Double,
        longitude: Double
    ) async -> Result<GeofenceApiResponse, GeofenceApiError> {
        await withCheckedContinuation { continuation in
            apiService.fetchGeofences(latitude: latitude, longitude: longitude) { result in
                continuation.resume(returning: result)
            }
        }
    }

    /// Stops all monitored regions, then starts the new business set + movement trigger.
    /// `@MainActor`-isolated so a same-actor caller (e.g. `applyCachedRegistration`)
    /// can register without yielding — see the protocol doc for why that matters.
    @MainActor
    private func registerWithOsSync(
        businessRegions: [Geofence],
        movementTriggerLocation: LocationData,
        movementTriggerRadius: Double
    ) {
        monitor.stopMonitoringAll()
        for region in businessRegions {
            monitor.startMonitoring(
                identifier: region.id,
                center: LocationData(latitude: region.latitude, longitude: region.longitude),
                radius: region.radius,
                transitionTypes: region.transitionTypes
            )
        }
        monitor.startMonitoring(
            identifier: GeofenceConstants.movementTriggerIdentifier,
            center: movementTriggerLocation,
            radius: movementTriggerRadius,
            transitionTypes: [.exit]
        )
    }
}

// MARK: - DI

extension DIGraphShared {
    /// Hand-written + `@MainActor`-isolated because constructing the coordinator reads
    /// `geofenceMonitor`, whose accessor is also `@MainActor`. Override-check mirrors
    /// the generated accessors so tests can substitute via `di.override(value:forType:)`.
    @MainActor
    var geofenceSyncCoordinator: GeofenceSyncCoordinator {
        let overridden: GeofenceSyncCoordinator? = getOverriddenInstance()
        return overridden ?? GeofenceSyncCoordinatorImpl.shared
    }
}

extension GeofenceSyncCoordinatorImpl {
    /// Process-wide singleton — must be shared so the instance-level `refreshInProgress`
    /// dedup gate actually deduplicates across every caller. A factory-style accessor
    /// would hand each caller its own gate and defeat the point.
    @MainActor
    static let shared = GeofenceSyncCoordinatorImpl(
        apiService: DIGraphShared.shared.geofenceApiService,
        storage: DIGraphShared.shared.geofenceStorage,
        monitor: DIGraphShared.shared.geofenceMonitor,
        contextStore: DIGraphShared.shared.backgroundDeliveryContextStore,
        dateUtil: DIGraphShared.shared.dateUtil,
        logger: DIGraphShared.shared.logger
    )
}
