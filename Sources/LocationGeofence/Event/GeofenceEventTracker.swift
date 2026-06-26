import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "GeofenceEventTracker"
// sourcery: InjectCustomShared
/// Sends geofence transition events through a three-layer delivery flow:
/// 1. Cooldown-based deduplication (keyed by "geofenceId:transitionType")
/// 2. Persist to `PendingGeofenceMetricStore` before any send attempt, stamping
///    the currently-identified userId so A's transitions always attribute to A
/// 3. Dispatch in `deliver`, which claims the row (durably removing it) before sending so a
///    process death after a successful send can't re-deliver it on the next flush:
///    - Stamped userId → direct-HTTP path with that userId; on failure the row is restored
///      for the next flush
///    - No stamped userId → post to EventBus; DataPipeline records the transition under its
///      current identity (anonymous tracking when no one is identified). The captured timestamp
///      flows through the event so both paths attribute the transition to when it happened
///
/// `flushPending()` replays queued rows on module init and on every `ProfileIdentifiedEvent`.
/// Concurrent deliveries are deduplicated in-process via the active-delivery ID set and across
/// processes via the durable claim (atomic remove-before-send): exactly one channel sends a given
/// row. A row killed before it is claimed stays on disk for the next flush; the claim trades a
/// narrow at-most-once window (a crash between claim and the send reaching the backend) for no
/// duplicate deliveries.
///
/// `@unchecked Sendable`: all stored properties are `let`; mutable state is wrapped in
/// `Synchronized`. Required for the weak capture in the `@Sendable` transition handler.
final class GeofenceEventTracker: @unchecked Sendable {
    private let storage: GeofenceStorage
    private let pendingStore: PendingGeofenceMetricStore
    private let deliveryTracker: GeofenceDeliveryTracker
    private let contextStore: BackgroundDeliveryContextStore
    private let eventBusHandler: EventBusHandler
    private let dateUtil: DateUtil
    private let logger: Logger
    private let cooldownInterval: TimeInterval
    private let activeDeliveryKeys: Synchronized<Set<String>> = Synchronized([])

    init(
        storage: GeofenceStorage,
        pendingStore: PendingGeofenceMetricStore,
        deliveryTracker: GeofenceDeliveryTracker,
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
    /// Persists the metric, then hands it to `deliver`.
    func trackTransition(
        geofenceId: String,
        transition: GeofenceTransition
    ) async {
        let cooldownKey = "\(geofenceId):\(transition.rawValue)"
        let now = dateUtil.now
        // Cached config wins when present so a workspace can tune the dedup window without
        // an SDK release; constructor default applies otherwise.
        let interval = await storage.getCachedConfig()?.duplicateEventsExpiry ?? cooldownInterval

        guard await storage.tryAcquireCooldown(key: cooldownKey, now: now, interval: interval) else {
            logger.geofenceEventSuppressed(geofenceId: geofenceId, transition: transition)
            return
        }

        // Stamp the current userId so a row captured under user A always delivers
        // as A — even if B signs in before the flush replays it. Nil when no user
        // is identified at capture time; `deliver` routes nil-stamped rows to EventBus.
        let liveUserId = contextStore.currentUserId
        let stampedUserId: String? = (liveUserId?.isEmpty == false) ? liveUserId : nil
        // Resolve the geofence name now and carry it on the metric; nil when unavailable so the
        // event omits `geofence_name` rather than sending an empty value.
        let cachedName = await storage.getCachedGeofences().first { $0.id == geofenceId }?.name
        let geofenceName = (cachedName?.isEmpty == false) ? cachedName : nil
        let metric = PendingGeofenceMetric(
            geofenceId: geofenceId,
            transition: transition,
            timestamp: now,
            userId: stampedUserId,
            name: geofenceName
        )
        _ = await pendingStore.append(metric)

        await deliver(metric: metric)
        await storage.purgeExpiredCooldowns(now: now, interval: interval)
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
        // Fast in-process guard so concurrent callers don't both attempt the same row.
        // In-memory only; the durable claim below covers separate processes.
        guard activeDeliveryKeys.mutating({ $0.insert(metric.key).inserted }) else { return }
        defer { activeDeliveryKeys.mutating { _ = $0.remove(metric.key) } }

        // Durable claim: remove before sending so a successful send can't be re-delivered after a
        // crash. A lost claim means another channel took it; restored below only on failure.
        guard await pendingStore.remove(key: metric.key) else { return }

        // Rows without a stamped userId (anonymous capture or legacy pre-stamping)
        // route through EventBus instead — DataPipeline tracks anonymously under
        // whatever identity is current at consume time, with its own durable delivery.
        guard let stampedUserId = metric.userId, !stampedUserId.isEmpty else {
            postEventBus(metric: metric)
            return
        }

        let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            deliveryTracker.trackMetric(metric: metric, userId: stampedUserId) { result in
                switch result {
                case .success:
                    continuation.resume(returning: true)
                case .failure:
                    continuation.resume(returning: false)
                }
            }
        }

        if success {
            logger.geofenceEventTracked(geofenceId: metric.geofenceId, transition: metric.transition)
        } else {
            // Send failed: restore the row so the next flush retries it.
            _ = await pendingStore.append(metric)
        }
    }

    /// Anonymous-attribution fallback used when a row carries no stamped userId.
    /// The captured `timestamp` flows through the event so DataPipeline can record
    /// the transition under the moment it actually happened, not the moment the
    /// flush ran.
    private func postEventBus(metric: PendingGeofenceMetric) {
        eventBusHandler.postEvent(TrackGeofenceMetricEvent(
            geofenceId: metric.geofenceId,
            transition: metric.transition,
            timestamp: metric.timestamp,
            name: metric.name
        ))
        logger.geofenceEventTracked(geofenceId: metric.geofenceId, transition: metric.transition)
    }
}

// MARK: - DI

extension DIGraphShared {
    var customGeofenceEventTracker: GeofenceEventTracker {
        GeofenceEventTracker.shared(di: self)
    }
}

extension GeofenceEventTracker {
    private static let sharedHolder = Synchronized<GeofenceEventTracker?>(nil)

    /// Lazily constructs and caches a process-wide singleton. Both `LocationModule.initialize`
    /// (foreground) and `LocationModule.bootstrapForBackgroundDelivery` (cold-wake) resolve
    /// through this DI accessor so they share the same tracker — same active-delivery dedup
    /// set, same `PendingGeofenceMetricStore`, same cooldown actor.
    static func shared(di: DIGraphShared) -> GeofenceEventTracker {
        sharedHolder.mutating { current in
            if let current { return current }
            let deliveryTracker = GeofenceDeliveryTrackerImpl(
                httpClient: di.backgroundDeliveryHttpClient,
                logger: di.logger
            )
            let tracker = GeofenceEventTracker(
                storage: di.geofenceStorage,
                pendingStore: PendingGeofenceMetricStore(),
                deliveryTracker: deliveryTracker,
                contextStore: di.backgroundDeliveryContextStore,
                eventBusHandler: di.eventBusHandler,
                dateUtil: di.dateUtil,
                logger: di.logger
            )
            current = tracker
            return tracker
        }
    }
}
