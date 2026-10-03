import CioInternalCommon
import CoreLocation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// `CLMonitor`-backed monitor, used on iOS 18+ only (see the DI accessor). Must deliver only genuine
/// crossings like the classic monitor; `CLMonitor` re-emits CURRENT state on relaunch/unlock, so
/// events dedup against a persisted baseline.
@available(iOS 17.0, *)
@MainActor
final class CLMonitorGeofenceMonitor: NSObject, GeofenceRegionMonitoring {
    // Alphanumeric only: dots/special chars throw "Monitor name is not valid".
    private static let monitorName = "CustomerIOGeofenceMonitor"
    /// `CLMonitor` only exposes its identifiers async; bootstrap needs a synchronous read at launch.
    static let conditionMirrorKey = "io.customer.sdk.geofence.clmonitor.conditionIdentifiers"

    let logger: Logger
    let storage: GeofenceStorage
    let userDefaults: UserDefaults
    let authManager: GeofenceLocationAuthority
    let movementFixResolver: MovementFixResolver
    var onTransition: GeofenceTransitionHandler?
    /// Internal (not private) for the `+Authorization` extension, which fires it.
    var onAuthorizationChanged: GeofenceAuthorizationChangedHandler?
    private var onReconciled: GeofenceReconciledHandler?
    /// Internal (not private) for the `+Authorization` extension, which fires it on access loss.
    var onMonitoringInterrupted: GeofenceMonitoringInterruptedHandler?
    /// Internal (not private) for the `+Authorization` extension's tier dedup.
    var lastLoggedPermissionTier: CoreLocationGeofenceMonitor.PermissionTier?
    /// Internal (not private) for the `+Authorization` extension: only a drop from it interrupts.
    var lastObservedAccess: GeofenceLocationAccess?

    var ownedRegionIdentifiers: Set<String> = []
    var knownConditionIdentifiers: Set<String> = []
    /// Geometry each condition was added with; `CLMonitor` can't read a condition back. Not seeded
    /// at init: leaving an inherited condition absent makes the first sync re-add it.
    var conditionLedger = RegisteredConditionLedger()
    var conditionsNeedingBaselineReseed: Set<String> = []

    /// Stamped at drain. The contradiction gate judges against this, not the ledger, which may hold
    /// a staged reshape the OS hasn't taken yet.
    var conditionReadds: [String: ConditionReadd] = [:]
    var gateFixRequestFailedAt: Date?

    /// Created once: a second `CLMonitor` with the same name throws.
    private var monitorTask: Task<GeofenceConditionMonitoring, Never>?

    /// Never cancelled or recreated: a second subscription steals events from the first.
    private var consumeTask: Task<Void, Never>?
    private var lastQueuedOperation: Task<Void, Never>?
    private var pendingEvents: [GeofenceConditionEvent] = []
    private var isDrainingPendingEvents = false
    private static let maxPendingEvents = 64
    /// Reset only by full rebuilds (init, adopt, foreground re-arm); regular syncs leave unchanged
    /// conditions untouched.
    var lastRearmAt: Date
    var foregroundObserverToken: NSObjectProtocol?

    /// Every timing decision reads this clock, never `Date()`.
    let dateUtil: DateUtil
    /// The dwell coordinator's clock, read as an event is recorded, so the visit it ends is ordered
    /// against it as the coordinator orders its own EXITs.
    private let clock: GeofenceClock

    private let makeConditionMonitor: @Sendable (String) async -> GeofenceConditionMonitoring

    init(
        logger: Logger,
        storage: GeofenceStorage,
        userDefaults: UserDefaults = .standard,
        dateUtil: DateUtil = DIGraphShared.shared.dateUtil,
        authority: GeofenceLocationAuthority = CoreLocationAuthority(),
        makeConditionMonitor: @escaping @Sendable (String) async -> GeofenceConditionMonitoring = { name in
            await CoreLocationConditionMonitor(monitor: CLMonitor(name))
        },
        clock: GeofenceClock = SystemGeofenceClock()
    ) {
        self.logger = logger
        self.clock = clock
        self.storage = storage
        self.userDefaults = userDefaults
        self.dateUtil = dateUtil
        self.lastRearmAt = dateUtil.now
        self.authManager = authority
        self.makeConditionMonitor = makeConditionMonitor
        self.movementFixResolver = MovementFixResolver(
            logger: logger,
            backgroundTaskRunner: GeofenceBackgroundTime.runner(name: "io.customer.geofence.movement-fix"),
            dateUtil: dateUtil
        )
        super.init()
        self.lastObservedAccess = locationAccess
        let mirrored = Set(userDefaults.stringArray(forKey: Self.conditionMirrorKey) ?? [])
        self.knownConditionIdentifiers = mirrored
        // Owned from process start: a cold-wake event must pass the filter before any async work.
        self.ownedRegionIdentifiers = mirrored
        authManager.onAuthorizationChange = { [weak self] in
            MainActor.assumeIsolated { self?.handleAuthorizationChange() }
        }
        updateServiceSession()
        enqueueMonitorOperation { [weak self] monitor in
            await self?.reconcileKnownConditions(with: monitor)
        }
        startConsuming()
        registerForegroundRearm()
        startConditionMirrorSampling()
    }

    deinit {
        if let foregroundObserverToken {
            NotificationCenter.default.removeObserver(foregroundObserverToken)
        }
    }

    // MARK: - CLMonitor lifecycle

    private func monitorInstance() -> Task<GeofenceConditionMonitoring, Never> {
        if let monitorTask { return monitorTask }
        let name = Self.monitorName
        // Don't defer on protected-data availability despite the CLMonitor header: it reads false
        // while locked (the usual background wake), so the events consumer would never attach.
        let task = Task { [makeConditionMonitor] in await makeConditionMonitor(name) }
        monitorTask = task
        return task
    }

    /// FIFO. All monitor mutations go through here so a remove can't overtake its re-add.
    func enqueueMonitorOperation(_ operation: @escaping @MainActor (GeofenceConditionMonitoring) async -> Void) {
        let previous = lastQueuedOperation
        let monitorTask = monitorInstance()
        lastQueuedOperation = Task { @MainActor in
            await previous?.value
            await operation(monitorTask.value)
        }
    }

    /// Assigned wholesale: as the first pipeline op, no add/remove can have run yet.
    private func reconcileKnownConditions(with monitor: GeofenceConditionMonitoring) async {
        let persisted = Set(await monitor.identifiers)
        let drifted = persisted != knownConditionIdentifiers
        knownConditionIdentifiers = persisted
        ownedRegionIdentifiers.formUnion(persisted)
        // Don't filter the ledger against `persisted`: its only entries were staged while loading,
        // and their adds are still queued behind this op.
        persistConditionMirror()
        if drifted { onReconciled?() }
    }

    private func startConsuming() {
        consumeTask = Task { [weak self] in
            guard let self else { return }
            let monitor = await self.monitorInstance().value
            // Re-subscribe on throw or end, or delivery stops for the process. Sequential, so there
            // is never a second consumer stealing events.
            var backoffNanos: UInt64 = 1000000000
            let maxBackoffNanos: UInt64 = 30000000000
            while !Task.isCancelled {
                do {
                    for try await event in await monitor.events {
                        await self.handle(event: event)
                        backoffNanos = 1000000000
                    }
                } catch {
                    self.logger.geofenceMonitorEventStreamFailed(error: error)
                }
                self.onMonitoringInterrupted?(nil)
                self.logger.geofenceInfo("event_stream_resubscribing", fields: [("s", String(backoffNanos / 1000000000))])
                try? await Task.sleep(nanoseconds: backoffNanos)
                backoffNanos = min(backoffNanos * 2, maxBackoffNanos)
            }
        }
    }

    private func handle(event: GeofenceConditionEvent) async {
        // Hold until `onTransition` is bound (processing earlier advances the baseline and drops the
        // delivery). Queue behind any backlog or in-flight drain to keep per-condition order.
        if onTransition == nil || !pendingEvents.isEmpty || isDrainingPendingEvents {
            pendingEvents.append(event)
            if pendingEvents.count > Self.maxPendingEvents { logOverflowedEvent(pendingEvents.removeFirst()) }
            drainPendingEventsIfReady()
            return
        }
        await process(event: event)
    }

    private func drainPendingEventsIfReady() {
        guard onTransition != nil, !isDrainingPendingEvents, !pendingEvents.isEmpty else { return }
        isDrainingPendingEvents = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            while self.onTransition != nil, !self.pendingEvents.isEmpty {
                let next = self.pendingEvents.removeFirst()
                await self.process(event: next)
            }
            self.isDrainingPendingEvents = false
        }
    }

    private func process(event: GeofenceConditionEvent) async {
        let identifier = event.identifier
        guard ownedRegionIdentifiers.contains(identifier) else { return logUnownedEvent(event) }
        let transition: GeofenceTransition
        switch event.state {
        case .satisfied:
            transition = .enter
        case .unsatisfied:
            transition = .exit
        case .unknown:
            return logger.geofenceInfo("os_state_unusable", fields: [("id", identifier), ("state", "unknown")])
        case .unmonitored:
            handleUnmonitored(identifier: identifier)
            return
        @unknown default:
            return logger.geofenceInfo("os_state_unusable", fields: [("id", identifier), ("state", "unhandled")])
        }
        // Logged before the gate and dedup: a refused or deduped event was still delivered by the OS.
        logReceivedCallback(identifier: identifier, transition: transition, eventDate: event.date)
        // BEFORE the baseline advance, so re-evaluation dedups against an untouched baseline. The
        // trigger is exempt: once wake-sized small, a genuine exit's cached fix can still read the
        // centre.
        if identifier != GeofenceConstants.movementTriggerIdentifier,
           await isEventContradictedByFreshFix(identifier: identifier, transition: transition, eventDate: event.date) {
            return
        }
        // Dated by the OS, not by receipt, so no guard depends on drain speed. Read before the
        // write: it is when this event was processed, under the cap the circle was registered with.
        let reading = clock.read()
        let maximumRadius = authManager.maximumRegionMonitoringDistance
        let (outcome, crossingObserved) = await storage.recordMonitorTransition(
            transition, forIdentifier: identifier,
            onlyIfBaselinePredates: event.date, osEventDate: event.date, now: event.date,
            processedAt: reading, maximumRadius: maximumRadius
        )
        guard case .deliver = outcome else {
            logDiscardedCallback(identifier: identifier, transition: transition, outcome: outcome)
            return
        }
        // No ownership re-check after the await: the baseline already advanced, so dropping here
        // would lose a genuine crossing that raced a sync's re-add.
        if identifier == GeofenceConstants.movementTriggerIdentifier, transition == .exit {
            // The pass re-centres on these coords, so resolve a fresh fix; fire-and-forget so a slow
            // fix can't stall the pending-event drain.
            movementFixResolver.resolve(cached: bestKnownFix(), purpose: .movement) { [weak self] location, isFresh in
                self?.logger.geofenceCallbackDispatched(identifier: identifier, transition: transition)
                self?.onTransition?(identifier, transition, location, event.date, isFresh, self?.eventCircle(for: identifier, raisedAt: event.date) ?? .unknown, crossingObserved)
            }
            return
        }
        logger.geofenceCallbackDispatched(identifier: identifier, transition: transition)
        onTransition?(
            identifier, transition, currentLocationData(), event.date, false,
            eventCircle(for: identifier, raisedAt: event.date), crossingObserved
        )
    }

    private func handleUnmonitored(identifier: String) {
        // Ownership is KEPT: the condition revives once budget frees, and refusing the movement
        // trigger's events would remove the only thing that restores it.
        logger.geofenceMonitorStoppedMonitoringRegion(identifier)
        knownConditionIdentifiers.remove(identifier)
        conditionLedger.forget(identifier)
        conditionReadds.removeValue(forKey: identifier)
        conditionsNeedingBaselineReseed.insert(identifier)
        persistConditionMirror()
        // Unwatched, so a stored entry time can no longer vouch for a continuous stay, as on the
        // classic path. The movement trigger carries no visit.
        if identifier != GeofenceConstants.movementTriggerIdentifier {
            onMonitoringInterrupted?(identifier)
        }
        // Skipped if a registration re-added it since, or this would delete that add's baseline.
        // Keyed on our own completed adds: `CLMonitor.identifiers` still lists a dropped condition.
        enqueueMonitorOperation { [weak self] _ in
            guard let self, !self.knownConditionIdentifiers.contains(identifier) else { return }
            await self.storage.clearMonitorRegionRecord(identifier: identifier)
        }
    }

    // MARK: - GeofenceRegionMonitoring

    var monitoredRegionIdentifiers: Set<String> {
        ownedRegionIdentifiers
    }

    var maximumMonitoringRadius: Double {
        authManager.maximumRegionMonitoringDistance
    }

    var osMonitoredRegionIdentifiers: Set<String> {
        knownConditionIdentifiers
    }

    func setOnTransition(_ handler: GeofenceTransitionHandler?) {
        onTransition = handler
        drainPendingEventsIfReady()
    }

    func setOnAuthorizationChanged(_ handler: GeofenceAuthorizationChangedHandler?) {
        onAuthorizationChanged = handler
    }

    func setOnReconciled(_ handler: GeofenceReconciledHandler?) {
        onReconciled = handler
    }

    func setOnMonitoringInterrupted(_ handler: GeofenceMonitoringInterruptedHandler?) {
        onMonitoringInterrupted = handler
    }
}
