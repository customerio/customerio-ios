import CioInternalCommon
import CoreLocation
import Foundation

/// Errors surfaced by `GeofenceSyncCoordinator` callers.
enum GeofenceSyncError: Error, Equatable {
    case noIdentifiedUser
    case alreadyInProgress
    case fetchFailed(GeofenceApiError)
}

/// Which branch `handleMovement` took for the current EXIT.
enum HandleMovementTier: String, Sendable {
    /// Re-rank cached regions for the new location; no API call. The only `fetchAll` movement path.
    case localRerank
    /// Refetch from the server — when no anchor exists yet (first EXIT after install / clearAll /
    /// sign-out).
    case remoteRefresh
}

/// Sync pipeline for the on-device geofence cache. Entry points:
///
/// - `refresh(latitude:longitude:)` — identify / app-launch entry. Routes through `refreshAction`:
///   re-fetch when stale, re-rank locally when the ranking is stale or the cache is unregistered,
///   else skip. Gated on identified user and in-flight dedup.
/// - `handleMovement(latitude:longitude:)` — movement-trigger EXIT entry. Re-ranks the cached set
///   for the new location; bootstraps from the server only when there's no anchor. Shares the same
///   dedup gate as `refresh`.
/// - `applyCachedRegistration(...)` — synchronously register from caller-fetched state,
///   used by cold-wake / boot / auth-change paths. Synchronous on the main actor so
///   `ownedRegionIdentifiers` is populated before the next yield — otherwise the OS may
///   deliver a queued cold-wake transition into an empty filter set. Returns what it
///   registered so the caller can persist it once the no-await window has closed.
/// - `reset()` — sign-out cleanup. Stops OS-side monitoring and clears user-scoped store
///   state (cooldowns, last-sync). Preserves the workspace cache.
protocol GeofenceSyncCoordinator: AutoMockable, AnyObject, Sendable {
    func refresh(latitude: Double, longitude: Double) async -> Result<Void, GeofenceSyncError>
    func handleMovement(latitude: Double, longitude: Double) async -> Result<Void, GeofenceSyncError>
    func reset() async -> Result<Void, GeofenceSyncError>
    @MainActor
    func applyCachedRegistration(
        cachedRegions: [Geofence],
        anchor: LocationData?,
        config: GeofenceConfig?,
        userId: String?
    ) -> GeofenceRegistration?
}

/// `@unchecked Sendable`: stored `Logger` and `DateUtil` are existentials of protocols
/// not declared `: Sendable`. Both are `let` references injected once and never mutated;
/// the only mutable state is the `Synchronized<Bool>` dedup gate.
final class GeofenceSyncCoordinatorImpl: GeofenceSyncCoordinator, @unchecked Sendable {
    private let apiService: GeofenceApiService
    private let monitor: GeofenceRegionMonitoring
    private let contextStore: BackgroundDeliveryContextStore
    private let distanceFilter: GeofenceDistanceFilter
    private let logger: Logger
    // Internal (not private) so the `+RefreshDecision` extension in its own file can read them;
    // all are immutable injected deps.
    let storage: GeofenceSyncStorage
    let dateUtil: DateUtil
    /// Defaults to `GeofenceSyncMode.active` (the shipped mode); injectable so tests can pin a mode.
    let syncMode: GeofenceSyncMode
    private let refreshInProgress = Synchronized<Bool>(false)

    init(
        apiService: GeofenceApiService,
        storage: GeofenceSyncStorage,
        monitor: GeofenceRegionMonitoring,
        contextStore: BackgroundDeliveryContextStore,
        distanceFilter: GeofenceDistanceFilter = GeofenceDistanceFilter(),
        dateUtil: DateUtil,
        logger: Logger,
        syncMode: GeofenceSyncMode = .active
    ) {
        self.apiService = apiService
        self.storage = storage
        self.monitor = monitor
        self.contextStore = contextStore
        self.distanceFilter = distanceFilter
        self.dateUtil = dateUtil
        self.logger = logger
        self.syncMode = syncMode
    }

    func refresh(latitude: Double, longitude: Double) async -> Result<Void, GeofenceSyncError> {
        guard acquireGate() else {
            logger.geofenceSyncSkipped(reason: "refresh already in progress")
            return .failure(.alreadyInProgress)
        }
        defer { releaseGate() }

        guard let userId = contextStore.currentUserId, !userId.isEmpty else {
            logger.geofenceSyncSkipped(reason: "no identified user")
            return .failure(.noIdentifiedUser)
        }

        let cachedConfig = await storage.getCachedConfig()
        let effectiveConfig = cachedConfig ?? .fallback
        let location = LocationData(latitude: latitude, longitude: longitude)
        switch await refreshAction(location: location, config: effectiveConfig) {
        case .remote:
            return await performRemoteRefresh(
                expectedUserId: userId,
                latitude: latitude,
                longitude: longitude,
                cachedConfig: cachedConfig
            )
        case .local:
            let cachedRegions = await storage.getCachedGeofences()
            return await performLocalRefresh(
                latitude: latitude,
                longitude: longitude,
                config: effectiveConfig,
                cachedRegions: cachedRegions
            )
        case .skip:
            logger.geofenceSyncSkippedFresh()
            return .success(())
        }
    }

    func handleMovement(latitude: Double, longitude: Double) async -> Result<Void, GeofenceSyncError> {
        guard acquireGate() else {
            logger.geofenceSyncSkipped(reason: "refresh already in progress")
            return .failure(.alreadyInProgress)
        }
        defer { releaseGate() }

        guard let userId = contextStore.currentUserId, !userId.isEmpty else {
            logger.geofenceSyncSkipped(reason: "no identified user")
            return .failure(.noIdentifiedUser)
        }

        let cachedConfig = await storage.getCachedConfig()
        let anchor = await storage.getLastSync()?.location
        let effectiveConfig = cachedConfig ?? .fallback
        let movement = LocationData(latitude: latitude, longitude: longitude)

        // No anchor (first EXIT after install / clearAll / sign-out) bootstraps from the server;
        // otherwise refetch only when fetchNearby has moved beyond its set. fetchAll always re-ranks.
        if anchor == nil || movedBeyondRefetchRadius(from: anchor, to: movement, config: effectiveConfig) {
            logger.geofenceMovementTrigger(tier: .remoteRefresh)
            return await performRemoteRefresh(
                expectedUserId: userId,
                latitude: latitude,
                longitude: longitude,
                cachedConfig: cachedConfig
            )
        } else {
            logger.geofenceMovementTrigger(tier: .localRerank)
            let cachedRegions = await storage.getCachedGeofences()
            return await performLocalRefresh(
                latitude: latitude,
                longitude: longitude,
                config: effectiveConfig,
                cachedRegions: cachedRegions
            )
        }
    }

    func reset() async -> Result<Void, GeofenceSyncError> {
        guard acquireGate() else {
            logger.geofenceSyncSkipped(reason: "refresh already in progress")
            return .failure(.alreadyInProgress)
        }
        defer { releaseGate() }

        // If a new user signed in between sign-out and this handler firing, skip — their
        // own refresh path will register the right state for them, and clearing here
        // would undo it.
        if let currentUserId = contextStore.currentUserId, !currentUserId.isEmpty {
            logger.geofenceResetSuperseded()
            return .success(())
        }

        await MainActor.run { monitor.stopMonitoringAll() }
        await storage.clearUserScopedState()
        logger.geofenceResetCompleted()
        return .success(())
    }

    @MainActor
    func applyCachedRegistration(
        cachedRegions: [Geofence],
        anchor: LocationData?,
        config: GeofenceConfig?,
        userId: String?
    ) -> GeofenceRegistration? {
        guard let userId, !userId.isEmpty else {
            logger.geofenceSyncSkipped(reason: "no identified user")
            return nil
        }
        guard !cachedRegions.isEmpty else {
            logger.geofenceSyncSkipped(reason: "no cached regions to restore")
            return nil
        }
        // Need an anchor to distance-filter and to center the movement trigger. Skipping
        // when absent is safer than re-using an arbitrary location.
        guard let anchor else {
            logger.geofenceSyncSkipped(reason: "no last-sync anchor to restore from")
            return nil
        }
        guard acquireGate() else {
            logger.geofenceSyncSkipped(reason: "restore already in progress")
            return nil
        }
        defer { releaseGate() }

        let effectiveConfig = config ?? .fallback
        let nearest = distanceFilter.nearest(cachedRegions, to: anchor, limit: effectiveConfig.maxBusinessGeofences, maxDistance: effectiveConfig.maxMonitoringDistance)
        registerWithOsSync(
            businessRegions: nearest,
            movementTriggerLocation: anchor,
            movementTriggerRadius: effectiveConfig.localRefreshTriggerRadius,
            registerMovementTrigger: effectiveConfig.maxBusinessGeofences > 0 && !cachedRegions.isEmpty
        )
        logger.geofenceSyncCompleted(registeredCount: nearest.count)
        // Return the registration so the caller persists it (async, after the no-await window) as
        // the ranking-staleness reference — otherwise a later fresh refresh measures from a stale
        // anchor and may skip while the OS holds the wrong nearest-set.
        return GeofenceRegistration(center: anchor, businessIds: Set(nearest.map(\.id)))
    }

    /// Returns false when another call already holds the gate; the caller short-circuits.
    private func acquireGate() -> Bool {
        refreshInProgress.mutating { inProgress in
            if inProgress { return false }
            inProgress = true
            return true
        }
    }

    private func releaseGate() {
        refreshInProgress.wrappedValue = false
    }

    /// Fetch + filter + register + persist. Caller owns the dedup gate and user-id check;
    /// `expectedUserId` is the value captured before the API call so this helper can
    /// re-check that the identified user hasn't changed during the (potentially long) fetch.
    private func performRemoteRefresh(
        expectedUserId: String,
        latitude: Double,
        longitude: Double,
        cachedConfig: GeofenceConfig?
    ) async -> Result<Void, GeofenceSyncError> {
        let fetchResult = await awaitApiFetch(latitude: latitude, longitude: longitude)
        let response: GeofenceApiResponse
        switch fetchResult {
        case .success(let value):
            response = value
        case .failure(let error):
            logger.geofenceSyncFetchFailed(error: error)
            return .failure(.fetchFailed(error))
        }

        // If the user signed out / changed during the API call, drop the result —
        // registering and persisting for a stale user would attribute geofences and
        // events to whoever signs in next.
        if contextStore.currentUserId != expectedUserId {
            logger.geofenceSyncSupersededByUserChange()
            return .success(())
        }

        let parsedConfig = response.toDomainConfig()
        let regions = response.toDomainRegions()
        let effectiveConfig = parsedConfig ?? cachedConfig ?? .fallback
        let anchor = LocationData(latitude: latitude, longitude: longitude)
        let nearest = distanceFilter.nearest(regions, to: anchor, limit: effectiveConfig.maxBusinessGeofences, maxDistance: effectiveConfig.maxMonitoringDistance)
        await MainActor.run {
            registerWithOsSync(
                businessRegions: nearest,
                movementTriggerLocation: anchor,
                movementTriggerRadius: effectiveConfig.localRefreshTriggerRadius,
                registerMovementTrigger: effectiveConfig.maxBusinessGeofences > 0 && !regions.isEmpty
            )
        }

        await storage.setCachedGeofences(regions)
        // Skip overwriting when the response did not ship a config — a previously cached
        // value must not be clobbered by a null parse from a partial-rollout backend.
        if let parsedConfig {
            await storage.setCachedConfig(parsedConfig)
        }
        await storage.recordSync(timestamp: dateUtil.now, location: anchor)
        await storage.recordRegistration(center: anchor, businessIds: Set(nearest.map(\.id)))
        logger.geofenceSyncCompleted(registeredCount: nearest.count)
        return .success(())
    }

    /// Re-rank cached regions for the new location and re-register with the OS. No API call and no
    /// `lastSync` write — the API-fetch anchor is what the re-fetch decision compares against, so
    /// leaving it intact preserves the next threshold. Records the registration anchor so the
    /// ranking-staleness reference follows the device after a local re-rank.
    private func performLocalRefresh(
        latitude: Double,
        longitude: Double,
        config: GeofenceConfig,
        cachedRegions: [Geofence]
    ) async -> Result<Void, GeofenceSyncError> {
        let anchor = LocationData(latitude: latitude, longitude: longitude)
        let nearest = distanceFilter.nearest(cachedRegions, to: anchor, limit: config.maxBusinessGeofences, maxDistance: config.maxMonitoringDistance)
        await MainActor.run {
            registerWithOsSync(
                businessRegions: nearest,
                movementTriggerLocation: anchor,
                movementTriggerRadius: config.localRefreshTriggerRadius,
                registerMovementTrigger: config.maxBusinessGeofences > 0 && !cachedRegions.isEmpty
            )
        }
        await storage.recordRegistration(center: anchor, businessIds: Set(nearest.map(\.id)))
        logger.geofenceSyncCompleted(registeredCount: nearest.count)
        return .success(())
    }
}

// MARK: - OS registration & fetch plumbing

private extension GeofenceSyncCoordinatorImpl {
    /// Dispatches the fetch per `syncMode`. `fetchAll` sends no location; `fetchNearby` sends a
    /// coarsened coordinate (the precise location that drives on-device ranking never leaves the
    /// coordinator — only `GeofenceApiService` coarsens what it transmits). See `GeofenceSyncMode`.
    func awaitApiFetch(latitude: Double, longitude: Double) async -> Result<GeofenceApiResponse, GeofenceApiError> {
        await withCheckedContinuation { continuation in
            switch syncMode {
            case .fetchAll:
                apiService.fetchAllGeofences { continuation.resume(returning: $0) }
            case .fetchNearby:
                apiService.fetchNearbyGeofences(latitude: latitude, longitude: longitude) { continuation.resume(returning: $0) }
            }
        }
    }

    /// Stops all monitored regions, then starts the new business set + movement trigger.
    /// `@MainActor`-isolated so a same-actor caller (e.g. `applyCachedRegistration`)
    /// can register without yielding — see the protocol doc for why that matters.
    @MainActor
    func registerWithOsSync(
        businessRegions: [Geofence],
        movementTriggerLocation: LocationData,
        movementTriggerRadius: Double,
        registerMovementTrigger: Bool
    ) {
        monitor.stopMonitoringAll()
        // Register the movement trigger FIRST so it isn't starved when business regions fill the
        // shared 20-region OS budget (e.g. a host app that also monitors regions): losing it freezes
        // the set, since exiting the trigger is what re-ranks toward now-closer geofences. Kept even
        // when the distance cap left the business set empty; skipped only when there's nothing to
        // register toward (no geofences, or registration kill-switched).
        if registerMovementTrigger {
            monitor.startMonitoring(
                identifier: GeofenceConstants.movementTriggerIdentifier,
                center: movementTriggerLocation,
                radius: movementTriggerRadius,
                transitionTypes: [.exit]
            )
        }
        for region in businessRegions {
            monitor.startMonitoring(
                identifier: region.id,
                center: LocationData(latitude: region.latitude, longitude: region.longitude),
                radius: region.radius,
                transitionTypes: region.transitionTypes
            )
        }
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
