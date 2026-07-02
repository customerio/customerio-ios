import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "GeofenceEventTracker"
// sourcery: InjectCustomShared
/// Sends geofence transition events through a three-layer delivery flow:
/// 1. Cooldown-based deduplication (keyed by "geofenceId:transitionType")
/// 2. Persist to `PendingGeofenceMetricStore` before any send attempt, stamping
///    the currently-identified userId so A's transitions always attribute to A
/// 3. Dispatch in `deliver`:
///    - Stamped userId → direct-HTTP path with that userId; success drains the
///      row, failure retains it for the next flush
///    - No stamped userId → post to EventBus and drain; DataPipeline records
///      the transition under its current identity (anonymous tracking when no
///      one is identified). The captured timestamp flows through the event so
///      both paths attribute the transition to when it happened
///
/// `flushPending()` replays queued rows on module init and on every `ProfileIdentifiedEvent`.
/// Concurrent deliveries for the same row are deduplicated in-process via the active-delivery
/// ID set; on app kill the row stays on disk and is retried in the next process.
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
            name: geofenceName,
            transitionId: UUID().uuidString
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
        // Claim before delivering so two concurrent callers (e.g. trackTransition and a
        // ProfileIdentifiedEvent-triggered flush, or two flushes) can't both send the
        // same row. The claim set is in-memory only — on app kill the row stays on
        // disk and is retried by flushPending in the next process.
        guard activeDeliveryKeys.mutating({ $0.insert(metric.key).inserted }) else { return }
        defer { activeDeliveryKeys.mutating { _ = $0.remove(metric.key) } }

        // Rows without a stamped userId (anonymous capture or legacy pre-stamping)
        // route through EventBus instead — DataPipeline tracks anonymously under
        // whatever identity is current at consume time.
        guard let stampedUserId = metric.userId, !stampedUserId.isEmpty else {
            postEventBus(metric: metric)
            _ = await pendingStore.remove(key: metric.key)
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
            _ = await pendingStore.remove(key: metric.key)
            logger.geofenceEventTracked(geofenceId: metric.geofenceId, transition: metric.transition)
        }
        // HTTP failure: row stays for next flush.
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
            name: metric.name,
            transitionId: metric.transitionId
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
