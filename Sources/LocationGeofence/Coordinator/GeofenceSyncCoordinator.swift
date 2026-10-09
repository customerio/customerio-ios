import CioInternalCommon
import CoreLocation
import Foundation

enum GeofenceSyncError: Error, Equatable {
    case noIdentifiedUser
    case alreadyInProgress
    case fetchFailed(GeofenceApiError)
}

/// Which branch `handleMovement` took, for the log.
enum HandleMovementTier: String, Sendable, CaseIterable {
    case localRerank
    case remoteRefresh
}

/// Keeps OS geofence registration in sync with the cached catalog. All entry points share one
/// in-flight gate; all except `reset` need an identified user.
protocol GeofenceSyncCoordinator: AutoMockable, AnyObject, Sendable {
    /// Identify / app-launch entry. `anchorIsLiveFix`: the coordinates are where the device is now,
    /// so the trigger may be sized to a polygon boundary around them.
    func refresh(latitude: Double, longitude: Double, anchorIsLiveFix: Bool) async -> Result<Void, GeofenceSyncError>
    /// Movement-trigger EXIT entry. `heldFix`: a fix the caller already obtained, reused rather than
    /// requesting another.
    func handleMovement(
        latitude: Double, longitude: Double, anchorIsLiveFix: Bool, heldFix: ResolvedFix?
    ) async -> Result<Void, GeofenceSyncError>
    /// Sign-out: stops monitoring and clears user-scoped state, keeping the workspace cache.
    func reset() async -> Result<Void, GeofenceSyncError>
    /// Called after a remote refresh saves a new config.
    func setOnConfigPersisted(_ handler: (@Sendable () -> Void)?)
    /// Cold-wake registration from cached state. Synchronous so ownership is set before a queued OS
    /// event can be delivered.
    @MainActor
    func applyCachedRegistration(
        cachedRegions: [Geofence],
        anchor: LocationData?,
        config: GeofenceConfig?,
        userId: String?
    ) -> GeofenceRegistration?
}

/// `@unchecked Sendable`: `Logger` and `DateUtil` aren't `Sendable` but are immutable `let`s; all
/// mutable state is `Synchronized`.
final class GeofenceSyncCoordinatorImpl: GeofenceSyncCoordinator, @unchecked Sendable {
    let distanceFilter: GeofenceDistanceFilter
    let logger: Logger
    let apiService: GeofenceApiService
    let monitor: GeofenceRegionMonitoring
    let storage: GeofenceSyncStorage
    let dateUtil: DateUtil
    let transitionEmitter: GeofenceTransitionEmitting
    let contextStore: BackgroundDeliveryContextStore
    let dwellCoordinator: GeofenceDwellCoordinator?
    /// The resolver the post-refresh polygon passes run on. Injected, not read from
    /// `DIGraphShared.shared` at the call: a composition with its own resolver (replay) otherwise
    /// had every such pass — and, through the singleton's construction, a production dwell
    /// coordinator — run against the process-wide graph mid-drive.
    let polygonResolver: @MainActor @Sendable () -> PolygonMembershipResolver
    let refreshInProgress = Synchronized<Bool>(false)

    /// A movement that lost the gate, replayed when it frees. Refreshes aren't deferred: a dropped
    /// refresh is redundant, but a dropped movement leaves the trigger where no EXIT can fire.
    let deferredMovement = Synchronized<DeferredMovement?>(nil)

    let onConfigPersisted = Synchronized<(@Sendable () -> Void)?>(nil)
    /// Arrival order, not completion order: a movement that lost the gate is newer than the holder.
    let movementSequence = Synchronized<UInt64>(0)
    /// Arrival sequence of the newest movement that has already re-centred the trigger.
    let appliedMovementSequence = Synchronized<UInt64>(0)

    init(
        apiService: GeofenceApiService,
        storage: GeofenceSyncStorage,
        monitor: GeofenceRegionMonitoring,
        contextStore: BackgroundDeliveryContextStore,
        transitionEmitter: GeofenceTransitionEmitting,
        dwellCoordinator: GeofenceDwellCoordinator? = nil,
        polygonResolver: @escaping @MainActor @Sendable () -> PolygonMembershipResolver = {
            DIGraphShared.shared.polygonMembershipResolver
        },
        distanceFilter: GeofenceDistanceFilter = GeofenceDistanceFilter(),
        dateUtil: DateUtil,
        logger: Logger
    ) {
        self.apiService = apiService
        self.storage = storage
        self.monitor = monitor
        self.contextStore = contextStore
        self.transitionEmitter = transitionEmitter
        self.dwellCoordinator = dwellCoordinator
        self.polygonResolver = polygonResolver
        self.distanceFilter = distanceFilter
        self.dateUtil = dateUtil
        self.logger = logger
    }

    func refresh(latitude: Double, longitude: Double, anchorIsLiveFix: Bool) async -> Result<Void, GeofenceSyncError> {
        // Takes a sequence: a refresh re-centres the trigger too, and an older replay must not undo it.
        guard let sequence = acquireGateWithSequence() else {
            logger.geofenceSyncSkipped(reason: .refreshInProgress)
            return .failure(.alreadyInProgress)
        }
        let expectedUserId = identifiedUserId
        let outcome = await performRefresh(expectedUserId: expectedUserId, latitude: latitude, longitude: longitude, anchorIsLiveFix: anchorIsLiveFix)
        let result = outcome.result
        if outcome.reCentred { noteMovementApplied(sequence) }
        let cleaned = await cleanupIfUserChanged(expectedUserId: expectedUserId)
        // Not `defer`: the retry below must find the gate free.
        releaseGate()
        if cleaned { retryForCurrentUser(latitude: latitude, longitude: longitude, anchorIsLiveFix: anchorIsLiveFix) }
        drainDeferredMovement(userChanged: cleaned)
        return result
    }

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
        // A non-live anchor can be hours old; ranking around it can drop the fence that just fired.
        // Use the registration centre the live set is already built around.
        let location = anchorIsLiveFix ? requested : (await storage.getLastRegistrationCenter() ?? requested)
        let action = await refreshAction(location: location, config: effectiveConfig)
        if action != .remote, await storage.cachedCatalogPredatesDwell() {
            return await performCatalogUpgradeRefresh(
                expectedUserId: userId,
                anchor: location,
                cachedConfig: cachedConfig,
                anchorIsLiveFix: anchorIsLiveFix,
                fallback: action
            )
        }
        return await performRefreshAction(
            action,
            expectedUserId: userId,
            anchor: location,
            cachedConfig: cachedConfig,
            anchorIsLiveFix: anchorIsLiveFix
        )
    }

    // Defaulted here because protocol requirements cannot carry default arguments.
    func handleMovement(
        latitude: Double, longitude: Double, anchorIsLiveFix: Bool, heldFix: ResolvedFix? = nil
    ) async -> Result<Void, GeofenceSyncError> {
        // No sequence here: a fresh movement is stamped inside the gate (`acquireGateOrDefer`).
        await handleMovement(
            latitude: latitude, longitude: longitude, anchorIsLiveFix: anchorIsLiveFix,
            replaySequence: nil, heldFix: heldFix
        )
    }

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
                // Re-arm from cache, or the trigger stays on the circle just exited and never fires.
                logger.geofenceMovementRearmedAfterFailedRefresh()
                let rearm = await performLocalRefresh(
                    expectedUserId: userId,
                    anchor: movement,
                    config: effectiveConfig,
                    cachedRegions: await storage.getCachedGeofences(),
                    anchorIsLiveFix: anchorIsLiveFix,
                    heldFix: heldFix
                )
                // The re-arm may have moved the trigger even though the fetch failed.
                return MovementPassOutcome(result: remote.result, reCentred: rearm.reCentred)
            }
            return remote
        }
        if await storage.cachedCatalogPredatesDwell() {
            return await performCatalogUpgradeMovement(
                expectedUserId: userId,
                movement: movement,
                cachedConfig: cachedConfig,
                anchorIsLiveFix: anchorIsLiveFix,
                heldFix: heldFix
            )
        }
        return await performCachedMovementTier(
            expectedUserId: userId,
            movement: movement,
            config: effectiveConfig,
            anchorIsLiveFix: anchorIsLiveFix,
            heldFix: heldFix
        )
    }

    func reset() async -> Result<Void, GeofenceSyncError> {
        guard acquireGate() else {
            logger.geofenceSyncSkipped(reason: .refreshInProgress)
            return .failure(.alreadyInProgress)
        }
        // Discarded, not drained: a queued movement belongs to the user being signed out.
        defer { discardDeferredAndReleaseGate() }

        // A new user already signed in; clearing would undo their registration.
        if let currentUserId = contextStore.currentUserId, !currentUserId.isEmpty {
            logger.geofenceResetSuperseded()
            return .success(())
        }

        // Clear BEFORE the OS stop, so a polygon pass resuming in between can't emit an enter for
        // a fence being torn down.
        await storage.clearUserScopedState()
        await MainActor.run { monitor.stopMonitoringAll() }
        logger.geofenceResetCompleted()
        return .success(())
    }

    var identifiedUserId: String? {
        guard let userId = contextStore.currentUserId, !userId.isEmpty else { return nil }
        return userId
    }
}

// MARK: - DI

extension DIGraphShared {
    /// Hand-written because `geofenceMonitor` is `@MainActor`.
    @MainActor
    var geofenceSyncCoordinator: GeofenceSyncCoordinator {
        let overridden: GeofenceSyncCoordinator? = getOverriddenInstance()
        return overridden ?? GeofenceSyncCoordinatorImpl.shared
    }
}

extension GeofenceSyncCoordinatorImpl {
    /// One instance, so the gate deduplicates across every caller.
    @MainActor
    static let shared = GeofenceSyncCoordinatorImpl(
        apiService: DIGraphShared.shared.geofenceApiService,
        storage: DIGraphShared.shared.geofenceStorage,
        monitor: DIGraphShared.shared.geofenceMonitor,
        contextStore: DIGraphShared.shared.backgroundDeliveryContextStore,
        transitionEmitter: DIGraphShared.shared.geofenceEventTracker,
        dwellCoordinator: DIGraphShared.shared.geofenceDwellCoordinator,
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
