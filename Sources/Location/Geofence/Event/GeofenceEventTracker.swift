import CioInternalCommon
import Foundation

/// Sends geofence transition events to the data pipeline with cooldown-based deduplication.
///
/// Events are keyed by "geofenceId:transitionType" and suppressed if the same event
/// was emitted within the cooldown interval. Cooldowns are persisted to survive app restarts
/// via the `GeofenceStorage` actor.
///
/// Communicates with DataPipeline via `EventBusHandler` (matching the in-app and push
/// metric pattern) so the geofence module has no direct dependency on the DataPipeline module.
final class GeofenceEventTracker {
    private let storage: GeofenceStorage
    private let eventBusHandler: EventBusHandler
    private let dateUtil: DateUtil
    private let logger: Logger
    private let cooldownInterval: TimeInterval

    init(
        storage: GeofenceStorage,
        eventBusHandler: EventBusHandler,
        dateUtil: DateUtil,
        logger: Logger,
        cooldownInterval: TimeInterval = GeofenceConstants.eventCooldownInterval
    ) {
        self.storage = storage
        self.eventBusHandler = eventBusHandler
        self.dateUtil = dateUtil
        self.logger = logger
        self.cooldownInterval = cooldownInterval
    }

    /// Tracks a geofence transition event, suppressing duplicates within the cooldown window.
    /// Also purges expired cooldown entries opportunistically.
    func trackTransition(geofenceId: String, transition: GeofenceTransition) async {
        let cooldownKey = "\(geofenceId):\(transition.rawValue)"
        let now = dateUtil.now

        guard await storage.tryAcquireCooldown(key: cooldownKey, now: now, interval: cooldownInterval) else {
            logger.geofenceEventSuppressed(geofenceId: geofenceId, transition: transition)
            return
        }

        eventBusHandler.postEvent(TrackGeofenceMetricEvent(
            geofenceId: geofenceId,
            transition: transition
        ))
        logger.geofenceEventTracked(geofenceId: geofenceId, transition: transition)

        await storage.purgeExpiredCooldowns(now: now, interval: cooldownInterval)
    }
}
