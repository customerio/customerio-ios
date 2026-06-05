import CioInternalCommon
import Foundation

/// Wires the geofence monitor into the SDK and (optionally) emits a discoverability log
/// about cold-wake real-time delivery. Shared by `LocationModule.initialize` (foreground)
/// and `LocationModule.bootstrapForBackgroundDelivery` (cold-wake) so both paths run the
/// same setup against the same DI-resolved singletons.
@MainActor
enum GeofenceBootstrap {
    static func wireMonitor(di: DIGraphShared) async {
        // Fetch cache BEFORE touching the monitor: once CLLocationManager exists, its delegate
        // is live and the OS can deliver queued cold-wake region callbacks. Any `await`
        // between delegate-set and `startMonitoring` would drop those events.
        let geofences = await di.geofenceStorage.getCachedGeofences()
        let monitor = di.geofenceMonitor
        let tracker = di.geofenceEventTracker
        GeofenceMonitorBinder.bind(monitor: monitor, geofences: geofences, tracker: tracker)
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
