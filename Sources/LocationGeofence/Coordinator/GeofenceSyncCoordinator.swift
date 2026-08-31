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
/// - `reapplyRegistration(latitude:longitude:)` — re-composes the OS-monitored set for the current
///   location without consulting the server. Used when the desired set changed for a reason other
///   than device movement: a polygon tripwire was planted or cleared and must reach the OS before
///   the next sync would otherwise run.
/// - `reset()` — sign-out cleanup. Stops OS-side monitoring and clears user-scoped store
///   state (cooldowns, last-sync). Preserves the workspace cache.
protocol GeofenceSyncCoordinator: AutoMockable, AnyObject, Sendable {
    func refresh(latitude: Double, longitude: Double) async -> Result<Void, GeofenceSyncError>
    func handleMovement(latitude: Double, longitude: Double) async -> Result<Void, GeofenceSyncError>
    func reset() async -> Result<Void, GeofenceSyncError>
    func reapplyRegistration(latitude: Double, longitude: Double) async -> Result<Void, GeofenceSyncError>
    @MainActor
    func applyCachedRegistration(
        cachedRegions: [Geofence],
        anchor: LocationData?,
        config: GeofenceConfig?,
        tripwires: [String: PolygonTripwire],
        userId: String?
    ) -> GeofenceRegistration?
}

/// `@unchecked Sendable`: stored `Logger` and `DateUtil` are existentials of protocols
/// not declared `: Sendable`. Both are `let` references injected once and never mutated;
/// the only mutable state is the `Synchronized<Bool>` dedup gate.
final class GeofenceSyncCoordinatorImpl: GeofenceSyncCoordinator, @unchecked Sendable {
    // Internal (not private) so the `+RefreshDecision` / `+Refresh` / `+InitialEnter` /
    // `+OsRegistration` extensions in their own files can read them; all are immutable injected deps.
    let distanceFilter: GeofenceDistanceFilter
    let logger: Logger
    let apiService: GeofenceApiService
    let monitor: GeofenceRegionMonitoring
    let storage: GeofenceSyncStorage
    let dateUtil: DateUtil
    let transitionEmitter: GeofenceTransitionEmitting
    let contextStore: BackgroundDeliveryContextStore
    private let refreshInProgress = Synchronized<Bool>(false)

    init(
        apiService: GeofenceApiService,
        storage: GeofenceSyncStorage,
        monitor: GeofenceRegionMonitoring,
        contextStore: BackgroundDeliveryContextStore,
        transitionEmitter: GeofenceTransitionEmitting,
        distanceFilter: GeofenceDistanceFilter = GeofenceDistanceFilter(),
        dateUtil: DateUtil,
        logger: Logger
    ) {
        self.apiService = apiService
        self.storage = storage
        self.monitor = monitor
        self.contextStore = contextStore
        self.transitionEmitter = transitionEmitter
        self.distanceFilter = distanceFilter
        self.dateUtil = dateUtil
        self.logger = logger
    }

    func refresh(latitude: Double, longitude: Double) async -> Result<Void, GeofenceSyncError> {
        guard acquireGate() else {
            logger.geofenceSyncSkipped(reason: "refresh already in progress")
            return .failure(.alreadyInProgress)
        }
        let expectedUserId = identifiedUserId
        let result = await performRefresh(expectedUserId: expectedUserId, latitude: latitude, longitude: longitude)
        let cleaned = await cleanupIfUserChanged(expectedUserId: expectedUserId)
        // Explicit release (not defer): the self-heal retry below must find the gate free, or it
        // would be dropped exactly like the refresh it compensates for.
        releaseGate()
        if cleaned { retryForCurrentUser(latitude: latitude, longitude: longitude) }
        return result
    }

    /// The refresh body, extracted so `refresh` has a single exit at which `cleanupIfUserChanged`
    /// runs while the gate is still held — covering every path (freshness-skip, fetch failure,
    /// post-fetch supersede, success alike).
    private func performRefresh(expectedUserId: String?, latitude: Double, longitude: Double) async -> Result<Void, GeofenceSyncError> {
        guard let userId = expectedUserId else {
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
                expectedUserId: userId,
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
        let expectedUserId = identifiedUserId
        let result = await performMovement(expectedUserId: expectedUserId, latitude: latitude, longitude: longitude)
        let cleaned = await cleanupIfUserChanged(expectedUserId: expectedUserId)
        releaseGate()
        if cleaned { retryForCurrentUser(latitude: latitude, longitude: longitude) }
        return result
    }

    /// The movement body, extracted for a single gated exit — same rationale as `performRefresh`.
    private func performMovement(expectedUserId: String?, latitude: Double, longitude: Double) async -> Result<Void, GeofenceSyncError> {
        guard let userId = expectedUserId else {
            logger.geofenceSyncSkipped(reason: "no identified user")
            return .failure(.noIdentifiedUser)
        }

        let cachedConfig = await storage.getCachedConfig()
        let anchor = await storage.getLastSync()?.location
        let effectiveConfig = cachedConfig ?? .fallback
        let movement = LocationData(latitude: latitude, longitude: longitude)

        // No anchor (first EXIT after install / clearAll / sign-out) bootstraps from the server;
        // otherwise refetch only once the device has moved beyond the cached nearby set.
        if anchor == nil || movedBeyondRefetchRadius(from: anchor, to: movement, config: effectiveConfig) {
            logger.geofenceMovementTrigger(tier: .remoteRefresh)
            let remote = await performRemoteRefresh(
                expectedUserId: userId,
                latitude: latitude,
                longitude: longitude,
                cachedConfig: cachedConfig
            )
            if case .failure = remote {
                // A failed pass never re-centers the trigger, leaving it on the circle the device
                // just exited where no further EXIT can fire. Re-rank from cache to re-arm it.
                logger.geofenceMovementRearmedAfterFailedRefresh()
                _ = await performLocalRefresh(
                    expectedUserId: userId,
                    latitude: latitude,
                    longitude: longitude,
                    config: effectiveConfig,
                    cachedRegions: await storage.getCachedGeofences()
                )
            }
            return remote
        } else {
            logger.geofenceMovementTrigger(tier: .localRerank)
            let cachedRegions = await storage.getCachedGeofences()
            return await performLocalRefresh(
                expectedUserId: userId,
                latitude: latitude,
                longitude: longitude,
                config: effectiveConfig,
                cachedRegions: cachedRegions
            )
        }
    }

    func reapplyRegistration(latitude: Double, longitude: Double) async -> Result<Void, GeofenceSyncError> {
        // Losing the gate here is benign: the tripwire that prompted this call is already persisted,
        // so the sync currently holding the gate composes its desired set from storage and carries
        // the tripwire to the OS itself.
        guard acquireGate() else {
            logger.geofenceSyncSkipped(reason: "refresh already in progress")
            return .failure(.alreadyInProgress)
        }
        let expectedUserId = identifiedUserId
        let result: Result<Void, GeofenceSyncError>
        if let userId = expectedUserId {
            result = await performLocalRefresh(
                expectedUserId: userId,
                latitude: latitude,
                longitude: longitude,
                config: await storage.getCachedConfig() ?? .fallback,
                cachedRegions: await storage.getCachedGeofences()
            )
        } else {
            logger.geofenceSyncSkipped(reason: "no identified user")
            result = .failure(.noIdentifiedUser)
        }
        let cleaned = await cleanupIfUserChanged(expectedUserId: expectedUserId)
        releaseGate()
        if cleaned { retryForCurrentUser(latitude: latitude, longitude: longitude) }
        return result
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
        tripwires: [String: PolygonTripwire],
        userId: String?
    ) -> GeofenceRegistration? {
        guard let userId, !userId.isEmpty else {
            logger.geofenceSyncSkipped(reason: "no identified user")
            return nil
        }
        // No early return on an empty cache: an empty nearby response clears it while the movement
        // trigger stays armed, so this is what re-arms the trigger if the OS dropped our regions.
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
        let nearest = distanceFilter.nearest(cachedRegions, to: anchor, limit: businessLimit(for: effectiveConfig, tripwires: tripwires), maxDistance: effectiveConfig.maxMonitoringDistance)
        let registerMovementTrigger = effectiveConfig.maxBusinessGeofences > 0
        registerWithOsSync(
            businessRegions: nearest,
            movementTriggerLocation: anchor,
            movementTriggerRadius: effectiveConfig.localRefreshTriggerRadius,
            registerMovementTrigger: registerMovementTrigger,
            tripwires: tripwires
        )
        logger.geofenceSyncCompleted(registeredCount: nearest.count, movementTriggerRegistered: registerMovementTrigger)
        // No initial-enter here: a cold-wake restore of the pre-kill set (not new registrations) off a
        // possibly-stale anchor. Genuinely-new fences come from a refresh fetch, which emits there.
        return GeofenceRegistration(center: anchor, businessIds: Set(nearest.map(\.id)))
    }

    /// Business-region cap for one pass, with a slot held back for every planted tripwire.
    ///
    /// `maxBusinessGeofences` keeps meaning *business fences*, but a tripwire draws from the same
    /// 20-region OS budget, so the cap has to shrink or the total overflows and the OS starts
    /// refusing registrations. Steady-state tripwire count is zero, so this normally changes
    /// nothing. A polygon whose tripwire costs it its own slot cannot happen: the device is inside
    /// that polygon's covering circle, so its edge distance is 0 and it sorts first.
    func businessLimit(for config: GeofenceConfig, tripwires: [String: PolygonTripwire]) -> Int {
        max(0, config.maxBusinessGeofences - tripwires.count)
    }

    /// The identified user a gated operation runs for (`nil` when signed out); the exit cleanup compares against it.
    private var identifiedUserId: String? {
        guard let userId = contextStore.currentUserId, !userId.isEmpty else { return nil }
        return userId
    }

    /// After a cleanup for an identity change, the device monitors nothing — and the new user's own
    /// refresh may already have been dropped on the gate this operation held. Re-run for whoever is
    /// signed in now, with this operation's seconds-old coordinates, so a user switch converges to a
    /// registered state instead of an outage lasting until the next launch. Loop-safe: a retry only
    /// re-fires if the identity changes yet again during the retry itself.
    private func retryForCurrentUser(latitude: Double, longitude: Double) {
        guard identifiedUserId != nil else { return }
        Task { [weak self] in
            _ = await self?.refresh(latitude: latitude, longitude: longitude)
        }
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
        transitionEmitter: DIGraphShared.shared.geofenceEventTracker,
        dateUtil: DIGraphShared.shared.dateUtil,
        logger: DIGraphShared.shared.logger
    )
}
