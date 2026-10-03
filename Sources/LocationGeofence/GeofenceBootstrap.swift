import CioInternalCommon
import Foundation

@MainActor
enum GeofenceBootstrap {
    /// Runs are chained: a re-run can start while a prior one is mid-await, and they must not
    /// interleave adopt/register work.
    private static var lastRun: Task<Void, Never>?
    private static var lastArm: Task<Void, Never>?
    /// Tail of the dwell-continuity chain; see `reconcileDwellContinuity`.
    private static var lastDwellReconcile: Task<Void, Never>?

    static func wireMonitor(di: DIGraphShared) async {
        let previous = lastRun
        let run = Task { @MainActor in
            await previous?.value
            await performWireMonitor(di: di)
        }
        lastRun = run
        await run.value
    }

    private static func performWireMonitor(di: DIGraphShared) async {
        // CLMonitor delivers only while `events` is iterated, so its consumer must attach before the
        // reads below; the cold-wake window is short. The classic monitor buffers until bound.
        if #available(iOS 18.0, *) {
            _ = di.geofenceMonitor
        }

        // Phase 1: every async read, before the handler is bound.
        let cachedRegions = await di.geofenceStorage.getCachedGeofences()
        let cachedConfig = await di.geofenceStorage.getCachedConfig()
        let lastSync = await di.geofenceStorage.getLastSync()
        // Not `lastSync` first: a local re-rank moves the registration centre but not `lastSync`,
        // so restoring from it would revert to an older nearest-set.
        let restoreAnchor = await di.geofenceStorage.getLastRegistrationCenter() ?? lastSync?.location
        let userId = di.backgroundDeliveryContextStore.currentUserId

        // Mirrors the register condition, so a kill-switched account reclaims nothing.
        let lastRegisteredBusinessIds = await di.geofenceStorage.getRegisteredBusinessIds()
        di.logger.geofenceStorageLoaded(regionCount: cachedRegions.count, hasAnchor: restoreAnchor != nil)
        let expectedOwnedRegions = (cachedConfig ?? .fallback).maxBusinessGeofences > 0
            ? lastRegisteredBusinessIds.union([GeofenceConstants.movementTriggerIdentifier])
            : []
        let monitorRecords = await di.geofenceStorage.getMonitorRegionRecords()

        // Phase 2: no `await` from binding the handler through adopt/register, so ownership is set
        // before a delivered event is checked against it.
        let monitor = di.geofenceMonitor
        let coordinator = di.geofenceSyncCoordinator
        bindDeliveryHandlers(di: di, monitor: monitor, coordinator: coordinator)

        // Before adopt/register: CLMonitor's first reconciliation can fire as soon as this yields.
        installRerunHandlers(di: di, monitor: monitor, coordinator: coordinator)

        // Adopt only the COMPLETE set; a partial overlap re-registers so missing geofences return.
        // Fences the OS stopped monitoring since last session; their visits lost continuity.
        var droppedBusinessRegions: Set<String> = []
        if di.backgroundDeliveryContextStore.currentUserId != userId {
            // Identity changed during the reads: adopting now could resurrect regions a sign-out
            // reset just removed. The next identify registers instead.
            di.logger.geofenceSyncSkipped(reason: .userChangedDuringBootstrap)
        } else if !expectedOwnedRegions.isEmpty, expectedOwnedRegions.isSubset(of: monitor.osMonitoredRegionIdentifiers) {
            monitor.adoptExistingRegions(matching: expectedOwnedRegions, records: monitorRecords)
        } else {
            // Read before registering, which re-adds them.
            droppedBusinessRegions = lastRegisteredBusinessIds.subtracting(monitor.osMonitoredRegionIdentifiers)
            let registration = coordinator.applyCachedRegistration(
                cachedRegions: cachedRegions,
                anchor: restoreAnchor,
                config: cachedConfig,
                userId: userId
            )
            // Safe to await: `applyCachedRegistration` already populated ownership synchronously.
            if let registration {
                await di.geofenceStorage.recordRegistration(
                    center: registration.center,
                    businessIds: registration.businessIds
                )
            }
        }

        // Adopt skips `startMonitoring`, which otherwise logs the tier.
        monitor.reportPermissionTier()
        reconcileDwellContinuity(di: di, droppedGeofenceIds: droppedBusinessRegions, cachedRegions: cachedRegions)

        // Re-reads the config: a refresh since phase 1 may have landed a kill switch.
        await armVisitMonitoring(di: di)
    }

    /// Drops the visits of fences the OS stopped monitoring, then re-arms the deadlines of the
    /// rest. Launched, not awaited: dwell is best-effort bookkeeping, and every await it adds to
    /// the run chain delays the rest of setup — and every later setup queued behind it — by storage
    /// round trips, which is the window a sign-out or a queued crossing lands in. Chained so two
    /// setups' invalidate-then-resume pairs cannot interleave.
    private static func reconcileDwellContinuity(
        di: DIGraphShared,
        droppedGeofenceIds: Set<String>,
        cachedRegions: [Geofence]
    ) {
        let dwellCoordinator = di.geofenceDwellCoordinator
        let previous = lastDwellReconcile
        lastDwellReconcile = Task { @MainActor in
            await previous?.value
            for geofenceId in droppedGeofenceIds {
                await dwellCoordinator.invalidateContinuity(geofenceId: geofenceId)
            }
            await dwellCoordinator.resumePendingVisits(geofences: cachedRegions)
        }
    }

    /// Binds the transition and visit handlers. Synchronous on purpose: it runs inside the
    /// no-`await` window of `performWireMonitor`, and must stay free of suspension points.
    private static func bindDeliveryHandlers(
        di: DIGraphShared,
        monitor: GeofenceRegionMonitoring,
        coordinator: GeofenceSyncCoordinator
    ) {
        let resolver = di.polygonMembershipResolver
        GeofenceMonitorBinder.bind(
            monitor: monitor,
            resolver: resolver,
            coordinator: coordinator,
            logger: di.logger,
            dwellCoordinator: di.geofenceDwellCoordinator
        )
        // Bound now (a cold wake can deliver a visit immediately) but armed at the end of
        // `performWireMonitor`.
        GeofenceMonitorBinder.bindVisits(
            visitMonitor: di.geofenceVisitMonitor,
            resolver: resolver,
            contextStore: di.backgroundDeliveryContextStore,
            dwellCoordinator: di.geofenceDwellCoordinator
        )
    }

    private static func installRerunHandlers(
        di: DIGraphShared,
        monitor: GeofenceRegionMonitoring,
        coordinator: GeofenceSyncCoordinator
    ) {
        let rewire: @MainActor () -> Void = {
            Task { @MainActor in await GeofenceBootstrap.wireMonitor(di: di) }
        }
        monitor.setOnAuthorizationChanged(rewire)
        monitor.setOnReconciled(rewire)
        // A background refresh can land a new config without reaching `GeofenceModuleState`.
        coordinator.setOnConfigPersisted {
            Task { @MainActor in await GeofenceBootstrap.armVisitMonitoring(di: di) }
        }
    }

    /// A `nil` config arms: first launch has none yet, and a refresh reconciles later.
    static func armVisitMonitoring(di: DIGraphShared, config: GeofenceConfig?) {
        let registrationEnabled = (config ?? .fallback).maxBusinessGeofences > 0
        if di.backgroundDeliveryContextStore.currentUserId != nil, registrationEnabled {
            di.geofenceVisitMonitor.start()
        } else {
            di.geofenceVisitMonitor.stop()
        }
    }

    /// The read stays INSIDE the chain, or a stale read could re-arm after a kill-switch disarm.
    static func armVisitMonitoring(di: DIGraphShared) async {
        let previous = lastArm
        let run = Task { @MainActor in
            await previous?.value
            armVisitMonitoring(di: di, config: await readCachedConfig(di))
        }
        lastArm = run
        await run.value
    }

    /// Test seam; never reassigned in production.
    static var readCachedConfig: (DIGraphShared) async -> GeofenceConfig? = {
        await $0.geofenceStorage.getCachedConfig()
    }

    static func awaitPendingWorkForTesting() async {
        await lastRun?.value
        await lastArm?.value
        await lastDwellReconcile?.value
    }

    static func emitDiscoverabilityLogIfNeeded(di: DIGraphShared) {
        if di.backgroundDeliveryContextStore.currentCdpApiKey == nil {
            di.logger.info(
                "Geofence cold-wake transitions will queue until next foreground session. Enable real-time delivery with SDKConfigBuilder.allowBackgroundDelivery(true).",
                "Location"
            )
        }
    }
}
