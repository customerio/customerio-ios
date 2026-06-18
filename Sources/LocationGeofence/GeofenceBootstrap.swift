import CioInternalCommon
import Foundation

/// Wires the geofence monitor into the SDK and (optionally) emits a discoverability log
/// about cold-wake real-time delivery. Shared by `LocationModule.initialize` (foreground)
/// and `LocationModule.bootstrapForBackgroundDelivery` (cold-wake) so both paths run the
/// same setup against the same DI-resolved singletons.
@MainActor
enum GeofenceBootstrap {
    static func wireMonitor(di: DIGraphShared) async {
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

        // Phase 2: synchronous on the main actor. No `await` between handler-bind and
        // `startMonitoring`, so `ownedRegionIdentifiers` is populated before any new
        // delegate call can land.
        let monitor = di.geofenceMonitor
        let tracker = di.geofenceEventTracker
        let coordinator = di.geofenceSyncCoordinator
        GeofenceMonitorBinder.bind(monitor: monitor, tracker: tracker, coordinator: coordinator)
        let registration = coordinator.applyCachedRegistration(
            cachedRegions: cachedRegions,
            anchor: restoreAnchor,
            config: cachedConfig,
            userId: userId
        )
        // Persist what was registered as the ranking-staleness reference. The await is safe here:
        // applyCachedRegistration already ran startMonitoring synchronously, so the cold-wake
        // no-await window has closed and a queued transition can't land in an empty filter.
        if let registration {
            await di.geofenceStorage.recordRegistration(
                center: registration.center,
                businessIds: registration.businessIds
            )
        }

        // Self-heal mid-process permission changes (Settings toggle, late prompt response).
        // The handler replaces any prior one — no stacking when both foreground init and
        // cold-wake bootstrap run in the same process.
        monitor.setOnAuthorizationChanged {
            Task { @MainActor in
                await GeofenceBootstrap.wireMonitor(di: di)
            }
        }
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
