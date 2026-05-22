import CioInternalCommon
import Foundation

/// Sends geofence transition events through a three-layer delivery flow:
/// 1. Cooldown-based deduplication (keyed by "geofenceId:transitionType")
/// 2. Persist to `PendingGeofenceMetricStore` before any send attempt
/// 3. Dispatch in `deliver`:
///    - No HttpClient → EventBus, drain row
///    - No userId yet → retain row for the next flush
///    - HTTP attempt → success drains; failure retains for retry
///
/// `flushPending()` replays queued rows on module init and on every `ProfileIdentifiedEvent`.
/// Concurrent deliveries for the same row are deduplicated in-process via the active-delivery
/// ID set; on app kill the row stays on disk and is retried in the next process.
final class GeofenceEventTracker {
    private let storage: GeofenceStorage
    private let pendingStore: PendingGeofenceMetricStore
    private let deliveryTracker: GeofenceDeliveryTracker?
    private let contextStore: BackgroundDeliveryContextStore
    private let eventBusHandler: EventBusHandler
    private let dateUtil: DateUtil
    private let logger: Logger
    private let cooldownInterval: TimeInterval
    private let activeDeliveryIds: Synchronized<Set<UUID>> = Synchronized([])

    init(
        storage: GeofenceStorage,
        pendingStore: PendingGeofenceMetricStore,
        deliveryTracker: GeofenceDeliveryTracker?,
        contextStore: BackgroundDeliveryContextStore,
        eventBusHandler: EventBusHandler,
        dateUtil: DateUtil,
        logger: Logger,
        cooldownInterval: TimeInterval = GeofenceConstants.eventCooldownInterval
    ) {
        self.storage = storage
        self.pendingStore = pendingStore
        self.deliveryTracker = deliveryTracker
        self.contextStore = contextStore
        self.eventBusHandler = eventBusHandler
        self.dateUtil = dateUtil
        self.logger = logger
        self.cooldownInterval = cooldownInterval
    }

    /// Tracks a geofence transition event, suppressing duplicates within the cooldown window.
    /// Persists the metric, then dispatches to one of the three delivery paths
    /// (EventBus drain / queue-retain / direct HTTP) per the rules in `deliver`.
    func trackTransition(
        geofenceId: String,
        transition: GeofenceTransition,
        location: LocationData? = nil
    ) async {
        let cooldownKey = "\(geofenceId):\(transition.rawValue)"
        let now = dateUtil.now

        guard await storage.tryAcquireCooldown(key: cooldownKey, now: now, interval: cooldownInterval) else {
            logger.geofenceEventSuppressed(geofenceId: geofenceId, transition: transition)
            return
        }

        let metric = PendingGeofenceMetric(
            geofenceId: geofenceId,
            transition: transition,
            latitude: location?.latitude,
            longitude: location?.longitude,
            timestamp: now
        )
        _ = await pendingStore.append(metric)

        await deliver(metric: metric)
        await storage.purgeExpiredCooldowns(now: now, interval: cooldownInterval)
    }

    /// Replays every queued metric through `deliver`.
    func flushPending() async {
        let pending = await pendingStore.loadAll()
        for metric in pending {
            await deliver(metric: metric)
        }
    }

    // MARK: - Private

    private func deliver(metric: PendingGeofenceMetric) async {
        // Claim before delivering so two concurrent callers (e.g. trackTransition and a
        // ProfileIdentifiedEvent-triggered flush, or two flushes) can't both send the
        // same row. The claim set is in-memory only — on app kill the row stays on
        // disk and is retried by flushPending in the next process.
        guard activeDeliveryIds.mutating({ $0.insert(metric.id).inserted }) else { return }
        defer { activeDeliveryIds.mutating { _ = $0.remove(metric.id) } }

        guard let deliveryTracker else {
            // No HTTP path will ever be available in this process (MessagingPush not
            // initialized). Deliver via EventBus and drain; nothing would recover this
            // row otherwise.
            postEventBus(metric: metric)
            _ = await pendingStore.remove(id: metric.id)
            return
        }

        guard let userId = contextStore.currentUserId, !userId.isEmpty else {
            // No userId yet (signed out / not yet identified). Leave the row so a later
            // ProfileIdentifiedEvent → flushPending can deliver it via direct HTTP with
            // the right userId. No EventBus — that would attribute the event to the
            // anonymous profile and duplicate when the flush succeeds.
            return
        }

        let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            deliveryTracker.deliver(metric: metric, userId: userId) { result in
                switch result {
                case .success:
                    continuation.resume(returning: true)
                case .failure:
                    continuation.resume(returning: false)
                }
            }
        }

        if success {
            _ = await pendingStore.remove(id: metric.id)
            logger.geofenceEventTracked(geofenceId: metric.geofenceId, transition: metric.transition)
        }
        // HTTP failure: row stays for next flush. No EventBus — same duplicate
        // risk if a later flush succeeds.
    }

    private func postEventBus(metric: PendingGeofenceMetric) {
        eventBusHandler.postEvent(TrackGeofenceMetricEvent(
            geofenceId: metric.geofenceId,
            transition: metric.transition
        ))
        logger.geofenceEventTracked(geofenceId: metric.geofenceId, transition: metric.transition)
    }
}
