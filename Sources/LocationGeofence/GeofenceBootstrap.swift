import CioInternalCommon
import Foundation

/// Wires the geofence monitor into the SDK. Shared by `GeofenceModule.initialize` (foreground)
/// and `GeofenceModule.bootstrapForBackgroundDelivery` (cold wake) so both run the same setup
/// against the same DI-resolved singletons.
@MainActor
enum GeofenceBootstrap {
    /// Tail of the run chain. The re-run handlers can re-trigger setup while a prior run is
    /// mid-await; chaining keeps runs from interleaving adopt/re-register work or racing the
    /// post-register persistence.
    private static var lastRun: Task<Void, Never>?
    /// Tail of the visit-arming chain; see the async `armVisitMonitoring`.
    private static var lastArm: Task<Void, Never>?

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
        // iOS 18+ (CLMonitor): construct the monitor now. CLMonitor delivers events only while its
        // `events` sequence is iterated, and the cold-wake window is short, so the consumer must
        // attach before the reads below. Safe this early: `init` seeds ownership from the persisted
        // mirror. The classic monitor buffers events until its handler is bound, so it can wait.
        if #available(iOS 18.0, *) {
            _ = di.geofenceMonitor
        }

        // Phase 1: every async read happens here, before the handler is bound in phase 2.
        let cachedRegions = await di.geofenceStorage.getCachedGeofences()
        let cachedConfig = await di.geofenceStorage.getCachedConfig()
        let lastSync = await di.geofenceStorage.getLastSync()
        // Prefer the last registration center over the fetch anchor: a local re-rank moves the
        // registration center but leaves lastSync at the fetch point, so restoring from lastSync
        // would revert the OS to the older nearest-set. Falls back to lastSync before any re-rank.
        let restoreAnchor = await di.geofenceStorage.getLastRegistrationCenter() ?? lastSync?.location
        let userId = di.backgroundDeliveryContextStore.currentUserId

        // What we expect to still own: last session's business geofences plus the movement trigger.
        // Mirrors the register condition, so a kill-switched account reclaims nothing.
        let lastRegisteredBusinessIds = await di.geofenceStorage.getRegisteredBusinessIds()
        di.logger.geofenceStorageLoaded(regionCount: cachedRegions.count, hasAnchor: restoreAnchor != nil)
        let expectedOwnedRegions = (cachedConfig ?? .fallback).maxBusinessGeofences > 0
            ? lastRegisteredBusinessIds.union([GeofenceConstants.movementTriggerIdentifier])
            : []
        // Adopt-time seed for the CLMonitor path's geometry bookkeeping (empty on classic).
        let monitorRecords = await di.geofenceStorage.getMonitorRegionRecords()

        // Phase 2: synchronous on the main actor. No `await` between binding the handler and
        // `adoptExistingRegions` / `startMonitoring`, so ownership is populated before a delivered
        // event is checked against it.
        let monitor = di.geofenceMonitor
        let coordinator = di.geofenceSyncCoordinator
        let resolver = di.polygonMembershipResolver
        GeofenceMonitorBinder.bind(monitor: monitor, resolver: resolver, coordinator: coordinator, logger: di.logger)
        // Wired with the transition handler: a cold wake can deliver a visit immediately. Arming
        // waits for the tail, once adopt-or-register has settled what we monitor.
        GeofenceMonitorBinder.bindVisits(
            visitMonitor: di.geofenceVisitMonitor,
            resolver: resolver,
            contextStore: di.backgroundDeliveryContextStore
        )

        // Before the adopt/re-register decision: the CLMonitor path's first reconciliation can fire
        // as soon as this synchronous phase yields, and must find a handler.
        installRerunHandlers(di: di, monitor: monitor, coordinator: coordinator)

        // The OS persists monitored regions across launches and reboots. Adopt only when it still
        // holds the COMPLETE set from last session: re-registering from `restoreAnchor` ranks from a
        // possibly stale anchor. A partial overlap re-registers so the missing geofences come back.
        if di.backgroundDeliveryContextStore.currentUserId != userId {
            // Identity changed during the reads above: adopting or registering now could resurrect
            // regions a sign-out reset just tore down (adopt's FIFO'd re-adds land after the
            // reset's queued removes). The next identify-driven refresh registers instead.
            di.logger.geofenceSyncSkipped(reason: .userChangedDuringBootstrap)
        } else if !expectedOwnedRegions.isEmpty, expectedOwnedRegions.isSubset(of: monitor.osMonitoredRegionIdentifiers) {
            monitor.adoptExistingRegions(matching: expectedOwnedRegions, records: monitorRecords)
        } else {
            // First launch after install, the OS dropped our regions (e.g. permission revoked then
            // re-granted, which clears `monitoredRegions`), or a partial drop. Register fresh from cache.
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

        // Adopt skips `startMonitoring`, the other place the permission tier is logged.
        monitor.reportPermissionTier()

        // The async form, not the phase-1 `cachedConfig`: a refresh may have landed a kill-switched
        // config since, and arming from the stale value would overwrite its disarm.
        await armVisitMonitoring(di: di)
    }

    /// Replaces any prior handlers, so repeat setups don't stack them. Authorization changes and
    /// reconciliation re-run setup against live OS state.
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
        // Visit arming is gated on the config, and a refresh can land a new one from a background
        // path that never reaches `GeofenceModuleState`.
        coordinator.setOnConfigPersisted {
            Task { @MainActor in await GeofenceBootstrap.armVisitMonitoring(di: di) }
        }
    }

    /// Arms visit monitoring only for an identified user with registration enabled; otherwise
    /// stops it. Visits are a wake source, and waking to evaluate an empty set is pure cost.
    ///
    /// Idempotent both ways: setup usually runs before `identify`, so the identify subscription
    /// arms it and sign-out disarms it. The `bindVisits` handler only refuses a visit for the wrong
    /// user; it never stops the monitor.
    ///
    /// - Parameter config: the effective config, `nil` when none is cached. `nil` arms, because
    ///   first launch has no config yet; a refresh then reconciles. The empty catalog is not the
    ///   gate for the same reason.
    static func armVisitMonitoring(di: DIGraphShared, config: GeofenceConfig?) {
        let registrationEnabled = (config ?? .fallback).maxBusinessGeofences > 0
        if di.backgroundDeliveryContextStore.currentUserId != nil, registrationEnabled {
            di.geofenceVisitMonitor.start()
        } else {
            di.geofenceVisitMonitor.stop()
        }
    }

    /// Reads the cached config, then arms.
    ///
    /// Chained, with the read INSIDE the chain. Unchained, an arm that read a pre-refresh config
    /// could resume after the refresh's disarm and re-arm a kill-switched account.
    static func armVisitMonitoring(di: DIGraphShared) async {
        let previous = lastArm
        let run = Task { @MainActor in
            await previous?.value
            armVisitMonitoring(di: di, config: await readCachedConfig(di))
        }
        lastArm = run
        await run.value
    }

    /// Test seam for the config read. `GeofenceStorage` is a concrete actor, so this is the only way
    /// to stall the suspension point the arm chain orders. Never reassigned in production.
    static var readCachedConfig: (DIGraphShared) async -> GeofenceConfig? = {
        await $0.geofenceStorage.getCachedConfig()
    }

    /// Test-only: awaits the process-global run and arm chains.
    static func awaitPendingWorkForTesting() async {
        await lastRun?.value
        await lastArm?.value
    }

    /// Logs a note when cold-wake real-time delivery is unavailable: no `cdpApiKey` persisted and
    /// no live DataPipeline provider.
    static func emitDiscoverabilityLogIfNeeded(di: DIGraphShared) {
        if di.backgroundDeliveryContextStore.currentCdpApiKey == nil {
            di.logger.info(
                "Geofence cold-wake transitions will queue until next foreground session. Enable real-time delivery with SDKConfigBuilder.allowBackgroundDelivery(true).",
                "Location"
            )
        }
    }
}
