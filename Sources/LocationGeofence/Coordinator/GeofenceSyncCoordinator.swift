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
enum HandleMovementTier: String, Sendable, CaseIterable {
    /// Re-rank cached regions for the new location; no API call.
    case localRerank
    /// Refetch from the server — when no anchor exists yet (first EXIT after install / clearAll /
    /// sign-out).
    case remoteRefresh
}

/// Sync pipeline for the on-device geofence cache. Entry points:
///
/// - `refresh(latitude:longitude:anchorIsLiveFix:)` — identify / app-launch entry. Routes through
///   `refreshAction`: re-fetch when stale, re-rank locally when the ranking is stale or the cache is
///   unregistered, else skip. Gated on identified user and in-flight dedup. `anchorIsLiveFix` says
///   whether the coordinates describe where the device is NOW or are a stored value standing in for
///   it; only the caller knows, and the movement trigger cannot be sized to a polygon boundary
///   around a point the device may not be at.
/// - `handleMovement(latitude:longitude:anchorIsLiveFix:)` — movement-trigger EXIT entry. Re-ranks
///   the cached set for the new location; bootstraps from the server only when there's no anchor.
///   Shares the same dedup gate as `refresh`. A movement pass whose fresh-fix request failed carries
///   the cached fix that prompted it, so this entry is not automatically live either.
/// - `applyCachedRegistration(...)` — synchronously register from caller-fetched state,
///   used by cold-wake / boot / auth-change paths. Synchronous on the main actor so
///   `ownedRegionIdentifiers` is populated before the next yield — otherwise the OS may
///   deliver a queued cold-wake transition into an empty filter set. Returns what it
///   registered so the caller can persist it once the no-await window has closed.
/// - `reset()` — sign-out cleanup. Stops OS-side monitoring and clears user-scoped store
///   state (cooldowns, last-sync). Preserves the workspace cache.
protocol GeofenceSyncCoordinator: AutoMockable, AnyObject, Sendable {
    func refresh(latitude: Double, longitude: Double, anchorIsLiveFix: Bool) async -> Result<Void, GeofenceSyncError>
    func handleMovement(latitude: Double, longitude: Double, anchorIsLiveFix: Bool) async -> Result<Void, GeofenceSyncError>
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
    // `internal`, not `private`, only because the gate helpers live in a split extension file.
    let refreshInProgress = Synchronized<Bool>(false)

    /// A movement pass that lost the gate, replayed when the holder releases it.
    ///
    /// Only movement is deferred, and the asymmetry is the point. A refresh that loses the gate is
    /// redundant — whoever holds it is refreshing the same catalog from a fix of the same moment.
    /// A movement pass that loses it is not: it is the only path that re-centres the movement
    /// trigger, and nothing else re-arms it. A business crossing and a trigger EXIT routinely
    /// arrive from the SAME movement, so the two race, and without this the EXIT can be dropped
    /// with `alreadyInProgress` and no retry — leaving the trigger on the circle the device just
    /// left, where no further EXIT can fire.
    ///
    /// Last writer wins: two movements queued behind one holder describe the same journey, and the
    /// newer coordinates are the ones worth re-arming against.
    let deferredMovement = Synchronized<DeferredMovement?>(nil)

    /// Arrival order for movements, so a replay can tell whether it has been overtaken.
    ///
    /// Ordered by ARRIVAL, not by completion: a movement that lost the gate is NEWER than the one
    /// holding it, so a completion counter would discard exactly the replay the deferral exists to
    /// preserve.
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
        // A refresh re-centres the trigger just as a movement pass does, and a replay that does
        // not know it happened walks the trigger back to an older point. Stamped as part of
        // taking the gate: see `acquireGateWithSequence` for why the two cannot be separate steps.
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

    /// The refresh body, extracted so `refresh` has a single exit at which `cleanupIfUserChanged`
    /// runs while the gate is still held — covering every path (freshness-skip, fetch failure,
    /// post-fetch supersede, success alike).
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
        // A non-live anchor only means "not obtained for this event", so it can be an OS cache
        // value hours old. Ranking, planting and persisting around one can drop the fence that
        // just fired and leave a movement trigger the device is not inside — which on the classic
        // path never fires again. The registration centre is the point the live registration is
        // already built around, so anchoring there still lets a time-expired catalog refetch
        // without moving anything. Callers holding a live fix are unaffected, and so is the
        // launch path, which already passes this same centre.
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

    func handleMovement(latitude: Double, longitude: Double, anchorIsLiveFix: Bool) async -> Result<Void, GeofenceSyncError> {
        // No sequence here: a fresh movement is stamped inside the gate, so a pass acquiring
        // later can never hold an earlier number. See `acquireGateOrDefer`.
        await handleMovement(latitude: latitude, longitude: longitude, anchorIsLiveFix: anchorIsLiveFix, replaySequence: nil)
    }

    /// The movement body, extracted for a single gated exit — same rationale as `performRefresh`.
    /// `internal` only because the gated caller lives in `+Gate`.
    func performMovement(
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
        let anchor = await storage.getLastSync()?.location
        let effectiveConfig = cachedConfig ?? .fallback
        let movement = LocationData(latitude: latitude, longitude: longitude)

        // No anchor (first EXIT after install / clearAll / sign-out) bootstraps from the server;
        // otherwise refetch only once the device has moved beyond the cached nearby set.
        if anchor == nil || movedBeyondRefetchRadius(from: anchor, to: movement, config: effectiveConfig) {
            logger.geofenceMovementTrigger(tier: .remoteRefresh)
            let remote = await performRemoteRefresh(
                expectedUserId: userId,
                anchor: movement,
                cachedConfig: cachedConfig,
                anchorIsLiveFix: anchorIsLiveFix
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
                    anchorIsLiveFix: anchorIsLiveFix
                )
                // The fetch failed but the re-arm may still have moved the trigger, and it is the
                // MOVE an older replay must not undo. Reporting this as "nothing happened" is what
                // let one through.
                return MovementPassOutcome(result: remote.result, reCentred: rearm.reCentred)
            }
            return remote
        } else if await !movedBeyondRerankRadius(to: movement, config: effectiveConfig) {
            // Always registers the trigger at `movement` before returning.
            return await performPolygonWakePass(expectedUserId: userId, at: movement, config: effectiveConfig, anchorIsLiveFix: anchorIsLiveFix)
        } else {
            logger.geofenceMovementTrigger(tier: .localRerank)
            let cachedRegions = await storage.getCachedGeofences()
            return await performLocalRefresh(
                expectedUserId: userId,
                anchor: movement,
                config: effectiveConfig,
                cachedRegions: cachedRegions,
                anchorIsLiveFix: anchorIsLiveFix
            )
        }
    }

    func reset() async -> Result<Void, GeofenceSyncError> {
        guard acquireGate() else {
            logger.geofenceSyncSkipped(reason: .refreshInProgress)
            return .failure(.alreadyInProgress)
        }
        // Discarded, not drained: a movement queued behind a reset belongs to the profile this
        // reset is clearing, and re-registering for it would undo the sign-out.
        // One step, not two: see `discardDeferredAndReleaseGate`.
        defer { discardDeferredAndReleaseGate() }

        // If a new user signed in between sign-out and this handler firing, skip — their
        // own refresh path will register the right state for them, and clearing here
        // would undo it.
        if let currentUserId = contextStore.currentUserId, !currentUserId.isEmpty {
            logger.geofenceResetSuperseded()
            return .success(())
        }

        // Clear BEFORE the OS stop, not after. They are separate awaits, and a polygon pass
        // resuming between them would read a still-populated `monitoredGeofenceIds`, pass the
        // create guard in `recordPolygonMembership` and emit an enter for a fence being torn down.
        // Clearing first makes that pass fail closed; a callback arriving in the reversed gap is
        // suppressed instead, which is the safe direction.
        await storage.clearUserScopedState()
        await MainActor.run { monitor.stopMonitoringAll() }
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
        let syncStartedAt = GeofenceLog.monotonicNow()
        guard let userId, !userId.isEmpty else {
            logger.geofenceSyncSkipped(reason: .noIdentifiedUser)
            return nil
        }
        // No early return on an empty cache: an empty nearby response clears it while the movement
        // trigger stays armed, so this is what re-arms the trigger if the OS dropped our regions.
        // Need an anchor to distance-filter and to center the movement trigger. Skipping
        // when absent is safer than re-using an arbitrary location.
        guard let anchor else {
            logger.geofenceSyncSkipped(reason: .noLastSyncAnchor)
            return nil
        }
        // Stamped with the gate, not after registering: a movement arriving while this restore
        // is talking to the OS would otherwise hold the lower sequence and be retired by the
        // older restore coordinates.
        guard let restoreSequence = acquireGateWithSequence() else {
            logger.geofenceSyncSkipped(reason: .restoreInProgress)
            return nil
        }
        // Drains like every other gate holder: a movement that lost the gate to a cache restore
        // is still the only thing that re-centres the trigger.
        defer {
            releaseGate()
            drainDeferredMovement(userChanged: false)
        }

        let effectiveConfig = config ?? .fallback
        let nearest = distanceFilter.nearest(monitorableRegions(cachedRegions), to: anchor, limit: effectiveConfig.maxBusinessGeofences, maxDistance: effectiveConfig.maxMonitoringDistance)
        let registerMovementTrigger = effectiveConfig.maxBusinessGeofences > 0
        let nearestIds = Set(nearest.map(\.id))
        logRanking(candidates: cachedRegions, nearest: nearest, nearestIds: nearestIds, anchor: anchor)
        let osRegistration = registerWithOsSync(
            businessRegions: nearest,
            movementTriggerLocation: anchor,
            // The full refresh radius, NOT a boundary-sized one: this path has no live fix. While
            // monitoring is live the recorded centre stays within `localRefreshTriggerRadius` of
            // the device, but this path exists precisely because the OS dropped the regions and the
            // process died — nothing re-recorded it, so the device can be arbitrarily far away. A
            // boundary-sized circle there would be one the device already stands outside. The first
            // movement pass re-arms against a live fix.
            movementTriggerRadius: effectiveConfig.localRefreshTriggerRadius,
            registerMovementTrigger: registerMovementTrigger
        )
        let registration = logRegistration(
            registeredIds: osRegistration.registeredIds,
            anchor: anchor,
            registerMovementTrigger: registerMovementTrigger,
            triggerRadius: effectiveConfig.localRefreshTriggerRadius
        )
        logSyncCompleted(registration, requested: (nearest.count, registerMovementTrigger), startedAt: syncStartedAt)
        // Same reason as `refresh`: this planted the trigger, so a replay older than it must be
        // retired rather than allowed to move it back. The sequence is the one taken at entry, not
        // a fresh one — allocating here would rank this restore above a movement that arrived
        // while it was registering, and retire the newer coordinates.
        //
        // Keyed on what the OS holds, not on `registerMovementTrigger`: that flag is the intent to
        // register, and the OS still drops the trigger for blocked permission or invalid
        // coordinates. Retiring a replay off an intent that did not land strands the trigger.
        if osRegistration.movementTriggerPlanted { noteMovementApplied(restoreSequence) }
        // No initial-enter here: a cold-wake restore of the pre-kill set (not new registrations) off a
        // possibly-stale anchor. Genuinely-new fences come from a refresh fetch, which emits there.
        // Only what the OS took, for the same reason as the refresh paths: an oversized polygon is
        // deliberately unregistered, and recording it would have the resolver decide membership for
        // a fence with no wake behind it.
        return GeofenceRegistration(center: anchor, businessIds: nearestIds.intersection(osRegistration.registeredIds))
    }

    // `internal`, not `private`, only because the gate helpers live in a split extension file.
    /// The identified user a gated operation runs for (`nil` when signed out); the exit cleanup compares against it.
    var identifiedUserId: String? {
        guard let userId = contextStore.currentUserId, !userId.isEmpty else { return nil }
        return userId
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

/// `CioInternalCommon`'s own `isSuccess` is internal to that module.
private extension Result {
    var succeeded: Bool {
        if case .success = self { return true }
        return false
    }
}
