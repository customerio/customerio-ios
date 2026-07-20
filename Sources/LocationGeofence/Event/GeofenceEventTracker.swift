import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "GeofenceEventTracker"
// sourcery: InjectCustomShared
/// Delivers geofence transition events. Anonymous crossings are dropped (geofencing is
/// identified-only); survivors are deduped by a cooldown, fanned out per geoset, and persisted
/// before any send. Two delivery channels drain the row, deduped server-side by the shared
/// transitionId:
/// - Fresh transition → direct HTTP (`deliverFresh`): works before DataPipeline is up (cold-wake);
///   failure retains the row for the next flush.
/// - Replay (`flushPending`) → EventBus when DataPipeline is live, else direct HTTP off the
///   persisted context; routing rationale on the method.
///
/// `flushPending()` runs on module init, cold-wake bootstrap, `ProfileIdentifiedEvent`, and after
/// every tracked transition (once its own rows are persisted and sent) — so a backlog retries
/// whenever a crossing wakes the device, without the fresh crossing's durability waiting on it.
/// Concurrent deliveries of the same row are deduped via the in-memory active-delivery set.
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

    /// Tracks a geofence transition, suppressing duplicates within the cooldown window.
    /// Fans the transition out to one metric per geoset the geofence belongs to (a single
    /// metric without a geosetId when it belongs to none), persists every row, then delivers.
    /// The cooldown is evaluated once per geofence, before fan-out, so all rows of one
    /// transition are suppressed or emitted together.
    func trackTransition(
        geofenceId: String,
        transition: GeofenceTransition
    ) async {
        // Persist and send the current crossing before any backlog work: the monitor's dedup
        // baseline has already advanced, so a crossing suspended away un-persisted can never
        // re-emit — its durability must not wait on a slow replay.
        let freshKeys = await deliverCurrentCrossing(geofenceId: geofenceId, transition: transition)
        // Then retry the backlog: queued rows are self-contained (stamped userId), so this
        // crossing's gates don't apply. Excluding the rows just written keeps a failed fresh
        // send on disk for the next trigger instead of re-attempting it on the same network.
        await flushPending(excluding: freshKeys)
    }

    /// Gates, fans out, persists, and sends the crossing's rows over direct HTTP; returns the
    /// persisted keys (empty when gated) so the caller can exclude them from the backlog flush.
    private func deliverCurrentCrossing(
        geofenceId: String,
        transition: GeofenceTransition
    ) async -> Set<String> {
        // Identified-only: the backend rejects anonymous geofence tracks, so drop before cooldown or
        // persist. Snapshot the userId so a later sign-out/sign-in can't reattribute the row.
        guard let stampedUserId = contextStore.currentUserId, !stampedUserId.isEmpty else {
            logger.geofenceTransitionDroppedAnonymous(geofenceId: geofenceId, transition: transition)
            return []
        }

        let cooldownKey = "\(geofenceId):\(transition.rawValue)"
        let now = dateUtil.now
        // Cached config wins when present so a workspace can tune the dedup window without
        // an SDK release; constructor default applies otherwise.
        let interval = await storage.getCachedConfig()?.duplicateEventsExpiry ?? cooldownInterval

        guard await storage.tryAcquireCooldown(key: cooldownKey, now: now, interval: interval) else {
            logger.geofenceEventSuppressed(geofenceId: geofenceId, transition: transition)
            return []
        }
        // Resolve the geofence name and geoset membership now and carry them on the metric;
        // name is nil when the geofence has none so the event omits `geofenceName`.
        let cachedGeofence = await storage.getCachedGeofences().first { $0.id == geofenceId }
        let geofenceName = cachedGeofence?.name
        // One event per geoset (scalar geosetId + geofence id/name as metadata) so matching needs no
        // joins; no geosets (or the fence left the cache) → one event without a geosetId.
        // Dedupe geoset ids, and drop blanks, so a fence listing the same one twice — or an empty
        // id — doesn't emit a duplicate or a stray empty-geoset event.
        var seenGeosetIds = Set<String>()
        let memberGeosetIds = (cachedGeofence?.geosetIds ?? []).filter { !$0.isEmpty && seenGeosetIds.insert($0).inserted }
        let geosetIds: [String?] = memberGeosetIds.isEmpty ? [nil] : memberGeosetIds
        // One transitionId for the whole crossing so downstream correlates the fan-out as one
        // transition; geosetId distinguishes the rows.
        let transitionId = UUID().uuidString
        let metrics = geosetIds.map { geosetId in
            PendingGeofenceMetric(
                geofenceId: geofenceId,
                transition: transition,
                timestamp: now,
                userId: stampedUserId,
                name: geofenceName,
                transitionId: transitionId,
                geosetId: geosetId,
                // Snapshot as the fallback for an evicted geofence; delivery prefers the live cache.
                metadata: cachedGeofence?.metadata
            )
        }
        // Persist all rows in one atomic write: a per-row loop could save some and lose the rest on
        // an app kill, and the cooldown is already spent so the lost ones would never retry. Done
        // before requesting background time so durability never depends on the assertion.
        let persisted = await pendingStore.append(metrics)
        if !persisted {
            // Persist-first failed (disk error): release the just-claimed cooldown so the next
            // crossing retries from a clean state instead of being suppressed. Skip delivery — a row
            // that never reached disk has nothing to retry, and sending it anyway would let its
            // success-path remove(key:) drop a later same-second crossing's row (keys omit transitionId).
            logger.geofencePendingPersistFailed(geofenceId: geofenceId, transition: transition)
            await storage.releaseCooldown(key: cooldownKey)
            return []
        }

        // Hold a background-task assertion across delivery so the OS doesn't suspend us mid-send when
        // it woke us only briefly for the transition. Deliver concurrently so N geosets don't
        // serialize N round-trips inside that window. Safe: distinct keys (no dedup-claim collision),
        // and rows are already persisted so any that don't finish are retried by flushPending.
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

    /// Replays every queued row, routed by who owns delivery best right now:
    /// - DataPipeline live → EventBus: its durable queue retries on its own cadence and batches the rows.
    /// - Else persisted key → direct HTTP: an uninitialized cold-wake (wrapper before JS/Dart init)
    ///   ships the backlog in the wake window; failed rows stay queued for the next trigger.
    /// - Neither → EventBus persists to disk; DataPipeline replays at next init.
    ///
    /// `excluding` skips rows the caller just persisted and already attempted itself.
    func flushPending(excluding excludedKeys: Set<String> = []) async {
        let metrics = await pendingStore.loadAll().filter { !excludedKeys.contains($0.key) }
        guard !metrics.isEmpty else { return }
        let persistedKey = contextStore.currentCdpApiKey
        if !contextStore.hasLiveCdpApiKeyProvider, let persistedKey, !persistedKey.isEmpty {
            // Same assertion + concurrent fan-out rationale as the fresh send in `trackTransition`.
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

    /// Fresh-transition delivery via direct HTTP. Failure leaves the row for `flushPending`.
    private func deliverFresh(metric: PendingGeofenceMetric) async {
        // Claim so a concurrent flush of the same row can't also send it.
        guard activeDeliveryKeys.mutating({ $0.insert(metric.key).inserted }) else { return }
        defer { activeDeliveryKeys.mutating { _ = $0.remove(metric.key) } }

        let effective = await resolvingLiveValues(metric)

        let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            deliveryTracker.trackMetric(metric: effective, userId: effective.userId) { result in
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
            logger.geofenceEventTracked(geofenceId: effective.geofenceId, transition: effective.transition)
        }
        // HTTP failure: row stays for next flush.
    }

    /// Replay via EventBus → DataPipeline, which then owns delivery and retry. We drop our copy
    /// once the handoff resolves (observer invoked, or written to the EventBus cache when none
    /// exists yet). That is not a durable-persistence ack — the strongest signal EventBus exposes
    /// today — so a crash before DataPipeline persists re-delivers on the next flush (deduped by
    /// transitionId).
    private func deliverViaEventBus(metric: PendingGeofenceMetric) async {
        guard activeDeliveryKeys.mutating({ $0.insert(metric.key).inserted }) else { return }
        defer { activeDeliveryKeys.mutating { _ = $0.remove(metric.key) } }

        let effective = await resolvingLiveValues(metric)
        await postEventBus(metric: effective)
        _ = await pendingStore.remove(key: metric.key)
    }

    /// Prefers the freshest cached `name`/`metadata` at send, falling back to the row snapshot when
    /// the geofence has left the cache. All other fields — including the dedup key inputs — are
    /// unchanged, so the returned copy addresses the same persisted row.
    private func resolvingLiveValues(_ metric: PendingGeofenceMetric) async -> PendingGeofenceMetric {
        guard let live = await storage.getCachedGeofences().first(where: { $0.id == metric.geofenceId }) else {
            return metric
        }
        // Re-resolve name and metadata from the live cache; name is nil when the geofence has none.
        return metric.withResolved(name: live.name, metadata: live.metadata)
    }

    /// Hands a row to DataPipeline via EventBus, carrying the snapshot userId + timestamp so a
    /// delayed replay attributes to the right person and time, not the current identity/send time.
    /// `postEventAndWait` (not `postEvent`) so the caller drains the row only once the handoff has
    /// resolved — `postEvent` returns before its detached delivery/persist task even runs.
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
        logger.geofenceEventTracked(geofenceId: metric.geofenceId, transition: metric.transition)
    }
}

// MARK: - Transition emitter seam

/// Delivers a transition through the tracked path (cooldown dedup, per-geoset fan-out, persistence).
/// Lets a caller such as `GeofenceSyncCoordinator` fire a synthetic initial ENTER for a newly
/// registered geofence the device is already inside, without depending on the concrete tracker.
protocol GeofenceTransitionEmitting: Sendable {
    /// See `GeofenceEventTracker.trackTransition(geofenceId:transition:)`.
    func trackTransition(geofenceId: String, transition: GeofenceTransition) async
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

    /// Real background-task assertion in the app; no-op where `UIApplication` is unavailable.
    private static var defaultBackgroundTaskRunner: BackgroundTaskRunner {
        #if canImport(UIKit)
        UIKitBackgroundTaskRunner(name: "io.customer.geofence.delivery")
        #else
        NoBackgroundTaskRunner()
        #endif
    }

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
                logger: di.logger,
                backgroundTaskRunner: Self.defaultBackgroundTaskRunner
            )
            current = tracker
            return tracker
        }
    }
}
