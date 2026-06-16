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
    /// Re-rank cached regions for the new location; no API call.
    case localRerank
    /// Anchor moved beyond `remoteFetchRefreshTriggerRadius` (or absent) — refetch from server.
    case remoteRefresh
}

/// Sync pipeline for the on-device geofence cache. Entry points:
///
/// - `refresh(latitude:longitude:)` — fetch from the server, distance-filter, register,
///   persist. Gated on identified user, in-flight dedup, and freshness.
/// - `handleMovement(latitude:longitude:)` — movement-trigger EXIT entry. Two-tier:
///   re-rank cache when within `remoteFetchRefreshTriggerRadius` of the API anchor,
///   otherwise refetch from the server. Shares the same dedup gate as `refresh`.
/// - `applyCachedRegistration(...)` — synchronously register from caller-fetched state,
///   used by cold-wake / boot / auth-change paths. Synchronous on the main actor so
///   `ownedRegionIdentifiers` is populated before the next yield — otherwise the OS may
///   deliver a queued cold-wake transition into an empty filter set.
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
        if let lastSync = await storage.getLastSync() {
            // Time-fresh alone isn't enough: if the app was killed while the user
            // travelled far, no movement EXIT fired to update the cache.
            let effectiveConfig = cachedConfig ?? .fallback
            let timeSinceLastSync = dateUtil.now.timeIntervalSince(lastSync.timestamp)
            let distanceFromAnchor = CLLocation(latitude: lastSync.location.latitude, longitude: lastSync.location.longitude)
                .distance(from: CLLocation(latitude: latitude, longitude: longitude))
            if timeSinceLastSync < effectiveConfig.remoteFetchRefreshExpiry,
               distanceFromAnchor < effectiveConfig.remoteFetchRefreshTriggerRadius {
                logger.geofenceSyncSkippedFresh()
                return .success(())
            }
        }

        return await performRemoteRefresh(
            expectedUserId: userId,
            latitude: latitude,
            longitude: longitude,
            cachedConfig: cachedConfig
        )
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
        // No anchor → no Tier A reference; fall through to remote.
        let needsRemoteFetch: Bool = {
            guard let anchor else { return true }
            let distance = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
                .distance(from: CLLocation(latitude: latitude, longitude: longitude))
            return distance >= effectiveConfig.remoteFetchRefreshTriggerRadius
        }()

        if needsRemoteFetch {
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
        guard acquireGate() else {
            logger.geofenceSyncSkipped(reason: "restore already in progress")
            return
        }
        defer { releaseGate() }

        let effectiveConfig = config ?? .fallback
        let nearest = distanceFilter.nearest(cachedRegions, to: anchor, limit: effectiveConfig.maxBusinessGeofences)
        registerWithOsSync(
            businessRegions: nearest,
            movementTriggerLocation: anchor,
            movementTriggerRadius: effectiveConfig.localRefreshTriggerRadius
        )
        logger.geofenceSyncCompleted(registeredCount: nearest.count)
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

    /// Re-rank cached regions for the new location and re-register with the OS. No API call,
    /// no cache or `lastSync` writes — the API anchor is what `handleMovement` compared
    /// against, so leaving it intact preserves the next Tier B threshold.
    private func performLocalRefresh(
        latitude: Double,
        longitude: Double,
        config: GeofenceConfig,
        cachedRegions: [Geofence]
    ) async -> Result<Void, GeofenceSyncError> {
        let anchor = LocationData(latitude: latitude, longitude: longitude)
        let nearest = distanceFilter.nearest(cachedRegions, to: anchor, limit: config.maxBusinessGeofences)
        await MainActor.run {
            registerWithOsSync(
                businessRegions: nearest,
                movementTriggerLocation: anchor,
                movementTriggerRadius: config.localRefreshTriggerRadius
            )
        }
        logger.geofenceSyncCompleted(registeredCount: nearest.count)
        return .success(())
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
        // With no business regions, a movement trigger would just refetch and get the
        // same empty result — leave it off until the next identify / foreground refresh.
        guard !businessRegions.isEmpty else { return }
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
