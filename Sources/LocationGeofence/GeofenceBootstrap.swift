import CioInternalCommon
import Foundation

/// Wires the geofence monitor into the SDK and (optionally) emits a discoverability log
/// about cold-wake real-time delivery. Shared by `LocationModule.initialize` (foreground)
/// and `LocationModule.bootstrapForBackgroundDelivery` (cold-wake) so both paths run the
/// same setup against the same DI-resolved singletons.
@MainActor
enum GeofenceBootstrap {
    /// Tail of the run chain. The authorization-changed and reconciled handlers re-trigger setup
    /// while a prior run may be mid-await; chaining serializes runs so they can't interleave
    /// adopt/re-register work or race the post-register persistence.
    private static var lastRun: Task<Void, Never>?

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
        // iOS 18+ (CLMonitor): construct the monitor NOW. CLMonitor delivers events only while its
        // `events` sequence is iterated — the OS does not queue a crossing for a late consumer — and
        // the cold-wake execution window is short, so the consumer must attach before the reads below.
        // Safe this early: ownership is seeded synchronously from the persisted mirror in `init`.
        // Classic (≤17) stays in phase 2: its delegate goes live on construction, and an `await`
        // before the owned-set is populated drops a queued crossing.
        if #available(iOS 18.0, *) {
            _ = di.geofenceMonitor
        }

        // Phase 1: all async reads BEFORE constructing the monitor. The
        // `CLLocationManager` delegate goes live the moment the monitor exists, so any
        // `await` after that point lets the OS deliver queued cold-wake transitions into
        // an empty `ownedRegionIdentifiers` set — and the delegate drops them.
        let cachedRegions = await di.geofenceStorage.getCachedGeofences()
        let cachedConfig = await di.geofenceStorage.getCachedConfig()
        let lastSync = await di.geofenceStorage.getLastSync()
        // Prefer the last registration center over the fetch anchor: a local re-rank moves the
        // registration center but leaves lastSync at the fetch point, so restoring from lastSync
        // would revert the OS to the older nearest-set. Falls back to lastSync before any re-rank.
        let restoreAnchor = await di.geofenceStorage.getLastRegistrationCenter() ?? lastSync?.location
        let userId = di.backgroundDeliveryContextStore.currentUserId

        // The set we expect to still own: the business geofences registered last session plus the
        // movement trigger registered alongside them. The trigger counts even when the business set
        // is empty — a geofence-free area still arms it, and an unadopted trigger drops the EXIT
        // that is the only path back to a re-rank or re-fetch. It is excluded under the kill switch
        // for the same reason registration excludes it, leaving the set empty and monitoring off.
        // Compared against the OS-retained set below to decide adopt vs re-register.
        let lastRegisteredBusinessIds = await di.geofenceStorage.getRegisteredBusinessIds()
        let expectedOwnedRegions = (cachedConfig ?? .fallback).maxBusinessGeofences > 0
            ? lastRegisteredBusinessIds.union([GeofenceConstants.movementTriggerIdentifier])
            : lastRegisteredBusinessIds

        // Phase 2: synchronous on the main actor. No `await` between handler-bind and
        // `adoptExistingRegions` / `startMonitoring`, so `ownedRegionIdentifiers` is populated
        // before any new delegate call can land.
        let monitor = di.geofenceMonitor
        let tracker = di.geofenceEventTracker
        let coordinator = di.geofenceSyncCoordinator
        GeofenceMonitorBinder.bind(monitor: monitor, tracker: tracker, coordinator: coordinator)

        // Install both re-run handlers BEFORE the adopt/re-register decision so the CLMonitor path's
        // first reconciliation — which can fire right after this synchronous phase yields — finds a
        // handler. Each re-runs this idempotent setup, replacing prior handlers (no stacking):
        // authorization changes re-attempt registration when permission improves; reconciliation
        // re-decides adopt-vs-re-register off live OS truth instead of the pre-reconcile mirror
        // (no-op on classic, whose osMonitoredRegionIdentifiers is already live).
        let rewire: @MainActor () -> Void = {
            Task { @MainActor in await GeofenceBootstrap.wireMonitor(di: di) }
        }
        monitor.setOnAuthorizationChanged(rewire)
        monitor.setOnReconciled(rewire)

        // iOS persists `monitoredRegions` across process launch and device reboot. Adopt only when the
        // OS still holds the COMPLETE set we registered last session — re-claim it instead of
        // re-registering from `restoreAnchor`, which ranks from a possibly-stale anchor and would
        // overwrite the good registration center with a wrong nearest-set. A partial overlap (some
        // regions dropped, e.g. a monitoring failure or only the trigger surviving) falls through to
        // re-register so the missing business geofences come back rather than staying unmonitored
        // until the next refresh.
        if di.backgroundDeliveryContextStore.currentUserId != userId {
            // Identity changed during the reads above: adopting or registering now could resurrect
            // regions a sign-out reset just tore down (adopt's FIFO'd re-adds land after the
            // reset's queued removes). The next identify-driven refresh registers instead.
            di.logger.geofenceSyncSkipped(reason: "identified user changed during bootstrap")
        } else if !expectedOwnedRegions.isEmpty, expectedOwnedRegions.isSubset(of: monitor.osMonitoredRegionIdentifiers) {
            monitor.adoptExistingRegions(matching: expectedOwnedRegions)
        } else {
            // First launch after install, the OS dropped our regions (e.g. permission revoked then
            // re-granted, which clears `monitoredRegions`), or a partial drop. Register fresh from cache.
            let registration = coordinator.applyCachedRegistration(
                cachedRegions: cachedRegions,
                anchor: restoreAnchor,
                config: cachedConfig,
                userId: userId
            )
            // Persist what was registered as the ranking-staleness reference. The await is safe
            // here: applyCachedRegistration already ran startMonitoring synchronously, so the
            // cold-wake no-await window has closed and a queued transition can't land in an empty
            // filter.
            if let registration {
                await di.geofenceStorage.recordRegistration(
                    center: registration.center,
                    businessIds: registration.businessIds
                )
            }
        }

        // The adopt path above skips `startMonitoring` (the other tier-log site), so without this
        // a relaunch that re-claims OS-persisted regions would report nothing about delivery readiness.
        monitor.reportPermissionTier()
    }

    /// Logs a one-line note when cold-wake real-time delivery is unavailable for this
    /// customer (no `cdpApiKey` persisted and no in-memory DataPipeline source). Surfaces
    /// only at bootstrap-time, when the customer's choice has observable consequences.
    static func emitDiscoverabilityLogIfNeeded(di: DIGraphShared) {
        if di.backgroundDeliveryContextStore.currentCdpApiKey == nil {
            di.logger.info(
                "Geofence cold-wake transitions will queue until next foreground session. Enable real-time delivery with SDKConfigBuilder.allowBackgroundDelivery(true).",
                "Location"
            )
        }
    }
}
