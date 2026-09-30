import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "GeofenceEventTracker"
// sourcery: InjectCustomShared
/// Delivers geofence transition events: identified-only, cooldown-deduped, fanned out per geoset,
/// and persisted before any send.
///
/// `@unchecked Sendable`: all stored properties are `let`; mutable state is wrapped in `Synchronized`.
final class GeofenceEventTracker: @unchecked Sendable {
    private let storage: GeofenceStorage
    private let pendingStore: PendingGeofenceMetricStore
    private let deliveryTracker: GeofenceDeliveryTracker
    private let contextStore: BackgroundDeliveryContextStore
    private let eventBusHandler: EventBusHandler
    private let dateUtil: DateUtil
    private let logger: Logger
    private let cooldownInterval: TimeInterval
    private let backgroundTaskRunner: BackgroundTaskRunner
    private let activeDeliveryKeys: Synchronized<Set<String>> = Synchronized([])

    init(
        storage: GeofenceStorage,
        pendingStore: PendingGeofenceMetricStore,
        deliveryTracker: GeofenceDeliveryTracker,
        contextStore: BackgroundDeliveryContextStore,
        eventBusHandler: EventBusHandler,
        dateUtil: DateUtil,
        logger: Logger,
        cooldownInterval: TimeInterval = GeofenceConstants.eventCooldownInterval,
        backgroundTaskRunner: BackgroundTaskRunner = NoBackgroundTaskRunner()
    ) {
        self.storage = storage
        self.pendingStore = pendingStore
        self.deliveryTracker = deliveryTracker
        self.contextStore = contextStore
        self.eventBusHandler = eventBusHandler
        self.dateUtil = dateUtil
        self.logger = logger
        self.cooldownInterval = cooldownInterval
        self.backgroundTaskRunner = backgroundTaskRunner
    }

    /// The cooldown applies before fan-out, so a crossing's rows are suppressed or emitted together.
    /// `occurredAt` is the crossing time the customer sees, not the delivery time.
    func trackTransition(
        geofenceId: String,
        transition: GeofenceTransition,
        occurredAt: Date
    ) async {
        // Current crossing before the backlog: the dedup baseline has advanced, so an un-persisted
        // crossing can never re-emit.
        let freshKeys = await deliverCurrentCrossing(
            geofenceId: geofenceId, transition: transition, occurredAt: occurredAt
        )
        // Excluding the rows just written keeps a failed fresh send on disk for the next trigger.
        await flushPending(excluding: freshKeys)
    }

    private func deliverCurrentCrossing(
        geofenceId: String,
        transition: GeofenceTransition,
        occurredAt: Date
    ) async -> Set<String> {
        // Snapshot the userId so a later sign-out/sign-in can't reattribute the row.
        guard let stampedUserId = contextStore.currentUserId, !stampedUserId.isEmpty else {
            logger.geofenceTransitionDroppedAnonymous(geofenceId: geofenceId, transition: transition)
            return []
        }

        // Per user: a fast re-login must not be suppressed by the previous user's transition.
        let cooldownKey = "\(stampedUserId):\(geofenceId):\(transition.rawValue)"
        // Wall-clock, not `occurredAt`: `purgeExpiredCooldowns` shares this base and would purge a
        // past-dated record at once.
        let now = dateUtil.now
        let interval = await storage.getCachedConfig()?.duplicateEventsExpiry ?? cooldownInterval

        if let remaining = await storage.tryAcquireCooldown(key: cooldownKey, now: now, interval: interval) {
            logger.geofenceEventSuppressed(geofenceId: geofenceId, transition: transition, cooldownRemaining: remaining)
            return []
        }
        let cachedGeofence = await storage.getCachedGeofences().first { $0.id == geofenceId }
        let geofenceName = cachedGeofence?.name
        var seenGeosetIds = Set<String>()
        let memberGeosetIds = (cachedGeofence?.geosetIds ?? []).filter { !$0.isEmpty && seenGeosetIds.insert($0).inserted }
        let geosetIds: [String?] = memberGeosetIds.isEmpty ? [nil] : memberGeosetIds
        // One transitionId for the whole crossing, so downstream correlates the fan-out.
        let transitionId = UUID().uuidString
        let metrics = geosetIds.map { geosetId in
            PendingGeofenceMetric(
                geofenceId: geofenceId,
                transition: transition,
                timestamp: occurredAt,
                userId: stampedUserId,
                name: geofenceName,
                transitionId: transitionId,
                geosetId: geosetId,
                // Fallback for an evicted geofence; delivery prefers the live cache.
                metadata: cachedGeofence?.metadata
            )
        }
        // One atomic write: the cooldown is spent, so rows lost mid-loop would never retry. Before
        // background time, so durability never depends on the assertion.
        let write = await pendingStore.append(metrics)
        guard write == .persisted else {
            await abandonUnpersisted(write, geofenceId: geofenceId, transition: transition, cooldownKey: cooldownKey)
            return []
        }
        // Accepted means persisted; delivery outcomes are the `delivery.*` records.
        logger.geofenceTransitionAccepted(geofenceId: geofenceId, transition: transition, rows: metrics.count)

        // Concurrent is safe: keys are distinct, and unfinished rows are already persisted.
        await backgroundTaskRunner.withBackgroundTime { [self] in
            await withTaskGroup(of: Void.self) { group in
                for metric in metrics {
                    group.addTask { await self.deliverFresh(metric: metric) }
                }
            }
        }
        await storage.purgeExpiredCooldowns(now: now, interval: interval)
        return Set(metrics.map(\.key))
    }

    /// DataPipeline live → EventBus; else a persisted key → direct HTTP (cold wake); neither →
    /// EventBus, which persists for DataPipeline's next init.
    func flushPending(excluding excludedKeys: Set<String> = []) async {
        // An unreadable queue is not an empty one: its rows stay on disk for a later trigger.
        guard case .rows(let rows) = await pendingStore.read() else { return }
        let metrics = rows.filter { !excludedKeys.contains($0.key) }
        guard !metrics.isEmpty else { return }
        let persistedKey = contextStore.currentCdpApiKey
        if !contextStore.hasLiveCdpApiKeyProvider, let persistedKey, !persistedKey.isEmpty {
            await backgroundTaskRunner.withBackgroundTime { [self] in
                await withTaskGroup(of: Void.self) { group in
                    for metric in metrics {
                        group.addTask { await self.deliverFresh(metric: metric) }
                    }
                }
            }
        } else {
            for metric in metrics {
                await deliverViaEventBus(metric: metric)
            }
        }
    }

    // MARK: - Private

    /// Skips delivery. After a failed write, the success-path `remove(key:)` could drop a later
    /// same-second row (keys omit transitionId); after a refused one, a send that failed could
    /// never be retried.
    private func abandonUnpersisted(
        _ write: PendingGeofenceQueueWrite,
        geofenceId: String,
        transition: GeofenceTransition,
        cooldownKey: String
    ) async {
        switch write {
        // Unreachable: the one call site guards on `.persisted`.
        case .persisted: return
        case .writeFailed:
            logger.geofencePendingPersistFailed(geofenceId: geofenceId, transition: transition)
        case .refusedUnreadable:
            logger.geofenceTransitionDroppedQueueUnreadable(geofenceId: geofenceId, transition: transition)
        }
        await storage.releaseCooldown(key: cooldownKey)
    }

    private func deliverFresh(metric: PendingGeofenceMetric) async {
        // Claim so a concurrent flush of the same row can't also send it.
        guard activeDeliveryKeys.mutating({ $0.insert(metric.key).inserted }) else { return }
        defer { activeDeliveryKeys.mutating { _ = $0.remove(metric.key) } }

        let effective = await resolvingLiveValues(metric)

        // Not collapsed to a Bool, so `delivery.failed` can report a reason.
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, BackgroundDeliveryHttpError>, Never>) in
            deliveryTracker.trackMetric(metric: effective, userId: effective.userId) { result in
                continuation.resume(returning: result)
            }
        }

        switch outcome {
        case .success:
            _ = await pendingStore.remove(key: metric.key)
            logger.geofenceDeliverySent(geofenceId: effective.geofenceId, transition: effective.transition, via: "http")
        case .failure(let error):
            logger.geofenceDeliveryFailed(geofenceId: effective.geofenceId, transition: effective.transition, error: error)
        }
    }

    /// Drops our copy once the handoff resolves. Not a durable ack, so a crash can re-deliver
    /// (deduped by transitionId).
    private func deliverViaEventBus(metric: PendingGeofenceMetric) async {
        guard activeDeliveryKeys.mutating({ $0.insert(metric.key).inserted }) else { return }
        defer { activeDeliveryKeys.mutating { _ = $0.remove(metric.key) } }

        let effective = await resolvingLiveValues(metric)
        await postEventBus(metric: effective)
        _ = await pendingStore.remove(key: metric.key)
    }

    /// Only `name`/`metadata` change, so the copy still addresses the same persisted row.
    private func resolvingLiveValues(_ metric: PendingGeofenceMetric) async -> PendingGeofenceMetric {
        guard let live = await storage.getCachedGeofences().first(where: { $0.id == metric.geofenceId }) else {
            return metric
        }
        return metric.withResolved(name: live.name, metadata: live.metadata)
    }

    /// `postEventAndWait`, not `postEvent`: the caller drains the row, and `postEvent` returns before
    /// its delivery task even runs.
    private func postEventBus(metric: PendingGeofenceMetric) async {
        await eventBusHandler.postEventAndWait(TrackGeofenceMetricEvent(
            geofenceId: metric.geofenceId,
            transition: metric.transition,
            timestamp: metric.timestamp,
            name: metric.name,
            transitionId: metric.transitionId,
            userId: metric.userId,
            geosetId: metric.geosetId,
            metadata: metric.metadata
        ))
        logger.geofenceDeliveryQueued(geofenceId: metric.geofenceId, transition: metric.transition, via: "event_bus")
    }
}

// MARK: - Transition emitter seam

/// Delivers a transition through the tracked path (cooldown, per-geoset fan-out, persistence).
protocol GeofenceTransitionEmitting: Sendable {
    /// See `GeofenceEventTracker.trackTransition(geofenceId:transition:occurredAt:)`.
    func trackTransition(geofenceId: String, transition: GeofenceTransition, occurredAt: Date) async
}

extension GeofenceEventTracker: GeofenceTransitionEmitting {}

// MARK: - DI

extension DIGraphShared {
    var customGeofenceEventTracker: GeofenceEventTracker {
        GeofenceEventTracker.shared(di: self)
    }
}

extension GeofenceEventTracker {
    private static let sharedHolder = Synchronized<GeofenceEventTracker?>(nil)

    private static var defaultBackgroundTaskRunner: BackgroundTaskRunner {
        #if canImport(UIKit)
        UIKitBackgroundTaskRunner(name: "io.customer.geofence.delivery")
        #else
        NoBackgroundTaskRunner()
        #endif
    }

    /// One instance for foreground init and cold-wake bootstrap, so both share the active-delivery
    /// set and pending store.
    static func shared(di: DIGraphShared) -> GeofenceEventTracker {
        sharedHolder.mutating { current in
            if let current { return current }
            let deliveryTracker = GeofenceDeliveryTrackerImpl(
                httpClient: di.backgroundDeliveryHttpClient,
                logger: di.logger
            )
            let tracker = GeofenceEventTracker(
                storage: di.geofenceStorage,
                pendingStore: PendingGeofenceMetricStore(logger: di.logger),
                deliveryTracker: deliveryTracker,
                contextStore: di.backgroundDeliveryContextStore,
                eventBusHandler: di.eventBusHandler,
                dateUtil: di.dateUtil,
                logger: di.logger,
                backgroundTaskRunner: Self.defaultBackgroundTaskRunner
            )
            current = tracker
            return tracker
        }
    }
}
