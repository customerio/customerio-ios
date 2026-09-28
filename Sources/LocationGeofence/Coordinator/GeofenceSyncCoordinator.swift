import CioInternalCommon
import CoreLocation
import Foundation

/// Errors surfaced by `GeofenceSyncCoordinator` callers.
enum GeofenceSyncError: Error, Equatable {
    case noIdentifiedUser
    case alreadyInProgress
    case fetchFailed(GeofenceApiError)
}

/// Which branch `handleMovement` took for the current EXIT (the polygon wake pass logs separately).
enum HandleMovementTier: String, Sendable, CaseIterable {
    /// Re-rank cached regions for the new location; no API call.
    case localRerank
    /// Refetch from the server: no fetch anchor yet, or the device moved beyond the refetch radius.
    case remoteRefresh
}

/// Sync pipeline for the on-device geofence cache. Entry points:
///
/// - `refresh(latitude:longitude:anchorIsLiveFix:)` — identify / app-launch entry. Re-fetches when
///   stale, re-ranks locally when the ranking is stale or the cache is unregistered, else skips.
///   `anchorIsLiveFix` says whether the coordinates are where the device is NOW or a stored stand-in;
///   only the caller knows, and the trigger cannot be sized to a polygon boundary around a point the
///   device may not be at.
/// - `handleMovement(latitude:longitude:anchorIsLiveFix:heldFix:)` — movement-trigger EXIT entry.
///   Refetches when there's no anchor or the device moved beyond the refetch radius, re-ranks from
///   cache beyond the re-rank radius, else just re-arms the trigger and re-evaluates polygons. Not
///   automatically live: a pass whose fresh-fix request failed carries the cached fix. `heldFix` is a
///   fix the caller already obtained and gated; the membership re-evaluation runs against it instead
///   of requesting its own.
/// - `applyCachedRegistration(...)` — synchronously register from caller-fetched state (cold-wake /
///   boot / auth-change). Synchronous on the main actor so `ownedRegionIdentifiers` is populated
///   before the next yield; otherwise the OS may deliver a queued cold-wake transition into an empty
///   filter set. Returns what it registered so the caller can persist it after that window closes.
/// - `reset()` — sign-out cleanup. Stops OS monitoring and clears user-scoped state; keeps the
///   workspace cache.
///
/// All entry points share one in-flight gate. `refresh`, `handleMovement` and
/// `applyCachedRegistration` need an identified user; `reset` does not.
protocol GeofenceSyncCoordinator: AutoMockable, AnyObject, Sendable {
    func refresh(latitude: Double, longitude: Double, anchorIsLiveFix: Bool) async -> Result<Void, GeofenceSyncError>
    func handleMovement(
        latitude: Double, longitude: Double, anchorIsLiveFix: Bool, heldFix: ResolvedFix?
    ) async -> Result<Void, GeofenceSyncError>
    func reset() async -> Result<Void, GeofenceSyncError>
    /// Fired after a remote refresh writes a new config; replaces any prior handler. Hooked at the
    /// writer because `handleMovement`'s refetch, the common background refresh, has no module-level
    /// call site.
    func setOnConfigPersisted(_ handler: (@Sendable () -> Void)?)
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
/// all mutable state is in `Synchronized` wrappers.
final class GeofenceSyncCoordinatorImpl: GeofenceSyncCoordinator, @unchecked Sendable {
    // Internal (not private) only so the split extension files can read them.
    let distanceFilter: GeofenceDistanceFilter
    let logger: Logger
    let apiService: GeofenceApiService
    let monitor: GeofenceRegionMonitoring
    let storage: GeofenceSyncStorage
    let dateUtil: DateUtil
    let transitionEmitter: GeofenceTransitionEmitting
    let contextStore: BackgroundDeliveryContextStore
    let refreshInProgress = Synchronized<Bool>(false)

    /// A movement pass that lost the gate, replayed when the holder releases it.
    ///
    /// Only movement is deferred. A refresh that loses the gate is redundant with the holder, but a
    /// dropped movement pass leaves the trigger on the circle the device just left, where no further
    /// EXIT can fire. A business crossing and a trigger EXIT routinely race from the same movement.
    ///
    /// Holds one movement: the highest arrival sequence wins (see `acquireGateOrDefer`).
    let deferredMovement = Synchronized<DeferredMovement?>(nil)

    /// Set by `GeofenceBootstrap` so visit arming can be reconciled against a newly landed config.
    let onConfigPersisted = Synchronized<(@Sendable () -> Void)?>(nil)
    /// Arrival order for movements, so a replay can tell whether it has been overtaken. By ARRIVAL,
    /// not completion: a movement that lost the gate is newer than the holder, so a completion
    /// counter would discard exactly the replay the deferral exists to preserve.
    let movementSequence = Synchronized<UInt64>(0)
    /// Arrival sequence of the newest movement that has already re-centred the trigger.
    let appliedMovementSequence = Synchronized<UInt64>(0)

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

    func refresh(latitude: Double, longitude: Double, anchorIsLiveFix: Bool) async -> Result<Void, GeofenceSyncError> {
        // A refresh re-centres the trigger too, so it takes a sequence; otherwise an older replay
        // could walk the trigger back. See `acquireGateWithSequence`.
        guard let sequence = acquireGateWithSequence() else {
            logger.geofenceSyncSkipped(reason: .refreshInProgress)
            return .failure(.alreadyInProgress)
        }
        let expectedUserId = identifiedUserId
        let outcome = await performRefresh(expectedUserId: expectedUserId, latitude: latitude, longitude: longitude, anchorIsLiveFix: anchorIsLiveFix)
        let result = outcome.result
        if outcome.reCentred { noteMovementApplied(sequence) }
        let cleaned = await cleanupIfUserChanged(expectedUserId: expectedUserId)
        // Explicit release (not defer): the self-heal retry below must find the gate free, or it
        // would be dropped exactly like the refresh it compensates for.
        releaseGate()
        if cleaned { retryForCurrentUser(latitude: latitude, longitude: longitude, anchorIsLiveFix: anchorIsLiveFix) }
        drainDeferredMovement(userChanged: cleaned)
        return result
    }

    /// Extracted so `refresh` has a single exit where `cleanupIfUserChanged` runs with the gate
    /// still held, whichever path the body took.
    private func performRefresh(
        expectedUserId: String?,
        latitude: Double,
        longitude: Double,
        anchorIsLiveFix: Bool
    ) async -> MovementPassOutcome {
        guard let userId = expectedUserId else {
            logger.geofenceSyncSkipped(reason: .noIdentifiedUser)
            return MovementPassOutcome(result: .failure(.noIdentifiedUser), reCentred: false)
        }

        let cachedConfig = await storage.getCachedConfig()
        let effectiveConfig = cachedConfig ?? .fallback
        let requested = LocationData(latitude: latitude, longitude: longitude)
        // A non-live anchor can be an OS cache value hours old. Ranking and planting around it can
        // drop the fence that just fired and leave a trigger the device is not inside, which on the
        // classic path never fires again. The last registration centre is what the live
        // registration is already built around, so a time-expired catalog can still refetch there.
        let location = anchorIsLiveFix ? requested : (await storage.getLastRegistrationCenter() ?? requested)
        switch await refreshAction(location: location, config: effectiveConfig) {
        case .remote:
            return await performRemoteRefresh(
                expectedUserId: userId,
                anchor: location,
                cachedConfig: cachedConfig,
                anchorIsLiveFix: anchorIsLiveFix
            )
        case .local:
            let cachedRegions = await storage.getCachedGeofences()
            return await performLocalRefresh(
                expectedUserId: userId,
                anchor: location,
                config: effectiveConfig,
                cachedRegions: cachedRegions,
                anchorIsLiveFix: anchorIsLiveFix
            )
        // Moves nothing, so it must not retire a movement waiting behind it.
        case .skip:
            logger.geofenceSyncSkippedFresh()
            return MovementPassOutcome(result: .success(()), reCentred: false)
        }
    }

    // Defaulted here because protocol requirements cannot carry default arguments.
    func handleMovement(
        latitude: Double, longitude: Double, anchorIsLiveFix: Bool, heldFix: ResolvedFix? = nil
    ) async -> Result<Void, GeofenceSyncError> {
        // A fresh movement is stamped inside the gate, not here. See `acquireGateOrDefer`.
        await handleMovement(
            latitude: latitude, longitude: longitude, anchorIsLiveFix: anchorIsLiveFix,
            replaySequence: nil, heldFix: heldFix
        )
    }

    /// Extracted for a single gated exit, like `performRefresh`. Internal only because the gated
    /// caller lives in `+Gate`.
    func performMovement(
        expectedUserId: String?,
        latitude: Double,
        longitude: Double,
        anchorIsLiveFix: Bool,
        heldFix: ResolvedFix?
    ) async -> MovementPassOutcome {
        guard let userId = expectedUserId else {
            logger.geofenceSyncSkipped(reason: .noIdentifiedUser)
            return MovementPassOutcome(result: .failure(.noIdentifiedUser), reCentred: false)
        }

        let cachedConfig = await storage.getCachedConfig()
        let anchor = await storage.getLastSync()?.location
        let effectiveConfig = cachedConfig ?? .fallback
        let movement = LocationData(latitude: latitude, longitude: longitude)

        // No anchor (first EXIT after install / sign-out) bootstraps from the server; otherwise
        // refetch only once the device has moved beyond the cached nearby set.
        if anchor == nil || movedBeyondRefetchRadius(from: anchor, to: movement, config: effectiveConfig) {
            logger.geofenceMovementTrigger(tier: .remoteRefresh)
            let remote = await performRemoteRefresh(
                expectedUserId: userId,
                anchor: movement,
                cachedConfig: cachedConfig,
                anchorIsLiveFix: anchorIsLiveFix,
                heldFix: heldFix
            )
            if case .failure = remote.result {
                // A failed pass never re-centers the trigger, leaving it on the circle the device
                // just exited where no further EXIT can fire. Re-rank from cache to re-arm it.
                logger.geofenceMovementRearmedAfterFailedRefresh()
                let rearm = await performLocalRefresh(
                    expectedUserId: userId,
                    anchor: movement,
                    config: effectiveConfig,
                    cachedRegions: await storage.getCachedGeofences(),
                    anchorIsLiveFix: anchorIsLiveFix,
                    heldFix: heldFix
                )
                // The fetch failed but the re-arm may still have moved the trigger, and an older
                // replay must not undo that move.
                return MovementPassOutcome(result: remote.result, reCentred: rearm.reCentred)
            }
            return remote
        } else if await !movedBeyondRerankRadius(to: movement, config: effectiveConfig) {
            return await performPolygonWakePass(expectedUserId: userId, at: movement, config: effectiveConfig, anchorIsLiveFix: anchorIsLiveFix, heldFix: heldFix)
        } else {
            logger.geofenceMovementTrigger(tier: .localRerank)
            let cachedRegions = await storage.getCachedGeofences()
            return await performLocalRefresh(
                expectedUserId: userId,
                anchor: movement,
                config: effectiveConfig,
                cachedRegions: cachedRegions,
                anchorIsLiveFix: anchorIsLiveFix,
                heldFix: heldFix
            )
        }
    }

    func reset() async -> Result<Void, GeofenceSyncError> {
        guard acquireGate() else {
            logger.geofenceSyncSkipped(reason: .refreshInProgress)
            return .failure(.alreadyInProgress)
        }
        // Discarded, not drained: a movement queued behind a reset belongs to the profile being
        // cleared, and re-registering for it would undo the sign-out.
        defer { discardDeferredAndReleaseGate() }

        // A new user signed in before this ran: their own refresh registers their state, and
        // clearing here would undo it.
        if let currentUserId = contextStore.currentUserId, !currentUserId.isEmpty {
            logger.geofenceResetSuperseded()
            return .success(())
        }

        // Clear BEFORE the OS stop. A polygon pass resuming between the two awaits would otherwise
        // read a still-populated `monitoredGeofenceIds`, pass the create guard in
        // `recordPolygonMembership` and emit an enter for a fence being torn down. Clearing first
        // makes it fail closed.
        await storage.clearUserScopedState()
        await MainActor.run { monitor.stopMonitoringAll() }
        logger.geofenceResetCompleted()
        return .success(())
    }

    /// The identified user a gated operation runs for (`nil` when signed out).
    var identifiedUserId: String? {
        guard let userId = contextStore.currentUserId, !userId.isEmpty else { return nil }
        return userId
    }
}

// MARK: - DI

extension DIGraphShared {
    /// Hand-written and `@MainActor` because constructing the coordinator reads `geofenceMonitor`,
    /// which is `@MainActor`. The override check mirrors the generated accessors for tests.
    @MainActor
    var geofenceSyncCoordinator: GeofenceSyncCoordinator {
        let overridden: GeofenceSyncCoordinator? = getOverriddenInstance()
        return overridden ?? GeofenceSyncCoordinatorImpl.shared
    }
}

extension GeofenceSyncCoordinatorImpl {
    /// Shared so the instance-level `refreshInProgress` gate deduplicates across every caller.
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

/// `CioInternalCommon`'s own `isSuccess` is internal to that module.
private extension Result {
    var succeeded: Bool {
        if case .success = self { return true }
        return false
    }
}
