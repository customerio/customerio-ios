import CioInternalCommon
import CoreLocation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// `CLMonitor`-backed implementation of `GeofenceRegionMonitoring`. Available at iOS 17, but the DI
/// accessor routes to it on iOS 18+ only — the floor where `CLServiceSession` keeps background
/// delivery alive (see the accessor); 13–17 keep the classic monitor.
///
/// Behavioral contract: match the classic monitor — deliver only genuine boundary crossings, only
/// for the registered transition types. `CLMonitor` differences this type compensates for:
/// - Re-emits a condition's CURRENT state on process start and re-evaluation (relaunch, unlock),
///   not just on crossings → per-condition dedup baseline persisted in `GeofenceStorage`, so a
///   cold-wake compares against the pre-kill state.
/// - No `notifyOnEntry`/`notifyOnExit` equivalent → per-condition delivery filter applied here.
/// - Async API (actor + `events` sequence) behind a synchronous protocol → mutations run on a
///   serialized FIFO pipeline so a re-registration's removes can never overtake its adds.
/// - On iOS 18+, `events` yields nothing in the background without a `CLServiceSession` → hold one
///   for the monitor's lifetime, created only when Always is already granted (never prompts —
///   permission is the host's decision).
/// - Conditions persist in the app container under our private monitor name → everything in it is
///   SDK-owned by construction (classic `monitoredRegions` is shared app-wide).
@available(iOS 17.0, *)
@MainActor
final class CLMonitorGeofenceMonitor: NSObject, GeofenceRegionMonitoring {
    // CLMonitor names must be alphanumeric — dots/special chars throw "Monitor name is not valid".
    private static let monitorName = "CustomerIOGeofenceMonitor"
    /// UserDefaults mirror of the monitor's condition identifiers. `CLMonitor` only exposes them
    /// async, but the bootstrap's adopt-vs-re-register decision needs a synchronous read right
    /// after construction — without the mirror that read is empty on every cold launch.
    static let conditionMirrorKey = "io.customer.sdk.geofence.clmonitor.conditionIdentifiers"

    // Members used by the `+*` extensions are `internal` only because they live in other files.
    let logger: Logger
    /// Persists the per-condition dedup baseline + delivery filter (see `MonitorRegionRecord`).
    let storage: GeofenceStorage
    let userDefaults: UserDefaults
    let authManager: GeofenceLocationAuthority
    /// Fresh fixes for movement-trigger exits, the contradiction gate and the baseline heal.
    let movementFixResolver: MovementFixResolver
    var onTransition: GeofenceTransitionHandler?
    private var onAuthorizationChanged: GeofenceAuthorizationChangedHandler?
    private var onReconciled: GeofenceReconciledHandler?
    private var lastLoggedPermissionTier: CoreLocationGeofenceMonitor.PermissionTier?

    /// In-memory ownership filter, mirrors `ownedRegionIdentifiers` in the classic monitor.
    var ownedRegionIdentifiers: Set<String> = []
    /// Synchronous view of the monitor's condition identifiers: seeded from the mirror at init,
    /// reconciled against `CLMonitor.identifiers` by the pipeline's first operation, then maintained.
    var knownConditionIdentifiers: Set<String> = []
    /// Geometry each condition was added with, post-clamp. `CLMonitor` exposes no way to read a
    /// condition back, so this is the only record `setMonitoredRegions` can diff against.
    ///
    /// Not seeded at init: an inherited condition may be listed but no longer monitored (see
    /// `rearmConditions`), and leaving it absent makes the first sync re-add it. Adoption seeds it
    /// from the persisted records the re-arm imposes.
    var conditionLedger = RegisteredConditionLedger()
    /// Conditions the OS stopped monitoring since their last registration. The next registration
    /// reseeds their stored baseline instead of preserving it — see `recordMonitorRegistration`.
    var conditionsNeedingBaselineReseed: Set<String> = []

    /// When each condition was last (re)added at the OS and the circle that add imposed, stamped
    /// at drain. The contradiction gate judges against this rather than the ledger, which already
    /// holds any staged reshape the OS has not taken yet.
    var conditionReadds: [String: ConditionReadd] = [:]
    /// When the last gate-fix request completed without producing a fresh fix; see `resolveGateFix`.
    var gateFixRequestFailedAt: Date?

    /// The one condition monitor, created once and shared by every caller: a second `CLMonitor`
    /// with the same name throws "Monitor named ... is already in use".
    private var monitorTask: Task<GeofenceConditionMonitoring, Never>?

    /// Single long-lived consumer of `monitor.events`. Never cancelled or recreated: a second
    /// subscription steals events from the first rather than duplicating them.
    private var consumeTask: Task<Void, Never>?
    /// Tail of the FIFO mutation pipeline; each enqueued operation awaits the previous one.
    private var lastQueuedOperation: Task<Void, Never>?
    /// Events received before the bootstrap bound `onTransition` (see `handle(event:)`).
    private var pendingEvents: [GeofenceConditionEvent] = []
    private var isDrainingPendingEvents = false
    private static let maxPendingEvents = 64
    /// When the armed conditions were last rebuilt at the OS (init, adopt, or a foreground re-arm).
    /// Regular syncs don't reset it: they leave unchanged conditions untouched, which is exactly
    /// what lets a wedged promotion record persist.
    var lastRearmAt: Date
    var foregroundObserverToken: NSObjectProtocol?

    /// Every timing decision in this wrapper reads this clock, never `Date()`.
    let dateUtil: DateUtil

    private let makeConditionMonitor: @Sendable (String) async -> GeofenceConditionMonitoring

    init(
        logger: Logger,
        storage: GeofenceStorage,
        userDefaults: UserDefaults = .standard,
        dateUtil: DateUtil = DIGraphShared.shared.dateUtil,
        authority: GeofenceLocationAuthority = CoreLocationAuthority(),
        makeConditionMonitor: @escaping @Sendable (String) async -> GeofenceConditionMonitoring = { name in
            await CoreLocationConditionMonitor(monitor: CLMonitor(name))
        }
    ) {
        self.logger = logger
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
        let mirrored = Set(userDefaults.stringArray(forKey: Self.conditionMirrorKey) ?? [])
        self.knownConditionIdentifiers = mirrored
        // Everything under our private monitor name was registered by the SDK, so persisted
        // conditions are owned as soon as the process starts — a cold-wake event must find its
        // identifier in the filter before any async work has run.
        self.ownedRegionIdentifiers = mirrored
        // Auth-status changes only; no region callbacks arrive here.
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
        // Created immediately and unconditionally. Despite the CLMonitor header's note, do NOT defer
        // creation on protected-data availability: the flag is false while the device is locked —
        // the normal state for a background crossing wake — and can read false on prewarmed launches
        // with no notification following; either way the events consumer would never attach. An
        // empty pre-first-unlock conditions read self-heals via reconcile.
        let task = Task { [makeConditionMonitor] in await makeConditionMonitor(name) }
        monitorTask = task
        return task
    }

    /// Runs `operation` after every previously enqueued operation has finished. All monitor
    /// mutations go through here so caller-side ordering (e.g. a remove before a re-add) is
    /// preserved across the async hops to the `CLMonitor` actor.
    func enqueueMonitorOperation(_ operation: @escaping @MainActor (GeofenceConditionMonitoring) async -> Void) {
        let previous = lastQueuedOperation
        let monitorTask = monitorInstance()
        lastQueuedOperation = Task { @MainActor in
            await previous?.value
            await operation(monitorTask.value)
        }
    }

    /// First pipeline operation: replace the mirror-seeded snapshot with `CLMonitor`'s persisted
    /// truth. Safe to assign wholesale because no add/remove can have run yet (FIFO).
    private func reconcileKnownConditions(with monitor: GeofenceConditionMonitoring) async {
        let persisted = Set(await monitor.identifiers)
        // A drifted mirror means bootstrap's synchronous adopt/re-register decision may have been
        // wrong — notify so it re-evaluates against live truth, not at the next sync.
        let drifted = persisted != knownConditionIdentifiers
        knownConditionIdentifiers = persisted
        ownedRegionIdentifiers.formUnion(persisted)
        // The ledger is deliberately not filtered against `persisted`. It starts empty
        // each process, so its only entries are ones staged while CLMonitor was still loading,
        // whose adds are queued behind this operation — exactly the identifiers `persisted` lacks.
        persistConditionMirror()
        if drifted { onReconciled?() }
    }

    private func startConsuming() {
        consumeTask = Task { [weak self] in
            guard let self else { return }
            let monitor = await self.monitorInstance().value
            // Re-subscribe with bounded backoff if the sequence throws or ends — otherwise all
            // delivery silently stops for the process. Sequential (the prior loop has ended), so
            // there is never a second concurrent consumer stealing events.
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
                // A sequence that ENDS rather than throws took this path in silence, and that is
                // indistinguishable in a capture from the OS having nothing to report.
                self.logger.geofenceInfo("event_stream_resubscribing", fields: [("s", String(backoffNanos / 1000000000))])
                try? await Task.sleep(nanoseconds: backoffNanos)
                backoffNanos = min(backoffNanos * 2, maxBackoffNanos)
            }
        }
    }

    private func handle(event: GeofenceConditionEvent) async {
        // Hold events until the bootstrap binds `onTransition`: processing earlier would advance the
        // baseline and drop the delivery, suppressing the later re-emission. New arrivals queue
        // behind any backlog and an in-flight drain (whose queue can read empty), so per-condition
        // order holds. Dropping the oldest past the cap is safe: CLMonitor re-emits current state.
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
            // CLMonitor gave up on the condition (budget exceeded). Drop the mirror entry and recorded
            // circle so the next sync re-registers it with a reseeded baseline. Ownership is KEPT: a
            // dropped condition stays listed and revives on its own once budget frees, and
            // refusing the movement trigger's events would remove the only thing that restores it.
            logger.geofenceMonitorStoppedMonitoringRegion(identifier)
            knownConditionIdentifiers.remove(identifier)
            conditionLedger.forget(identifier)
            conditionReadds.removeValue(forKey: identifier)
            conditionsNeedingBaselineReseed.insert(identifier)
            persistConditionMirror()
            // Skipped if a registration re-added it since, or this would delete that add's baseline.
            // Keyed on our own completed adds: `CLMonitor.identifiers` still lists a dropped condition.
            enqueueMonitorOperation { [weak self] _ in
                guard let self, !self.knownConditionIdentifiers.contains(identifier) else { return }
                await self.storage.clearMonitorRegionRecord(identifier: identifier)
            }
            return
        @unknown default:
            return logger.geofenceInfo("os_state_unusable", fields: [("id", identifier), ("state", "unhandled")])
        }
        // Logged before the gate and dedup: a refused or deduped event was still delivered by the OS.
        logReceivedCallback(identifier: identifier, transition: transition, eventDate: event.date)
        // Runs BEFORE the baseline advance below so the daemon's re-evaluation dedups against an
        // untouched baseline. The movement trigger is exempt: polygon wake-sizing can shrink it to
        // `polygonWakeMinRadius`, so a genuine exit lands inside the gate's window while the cached
        // fix still reads the centre.
        if identifier != GeofenceConstants.movementTriggerIdentifier,
           await isEventContradictedByFreshFix(identifier: identifier, transition: transition, eventDate: event.date) {
            return
        }
        // Dated by the OS, not by receipt, so no guard depends on drain speed. The evidence guard
        // catches a newer heal; see `enqueueBaselineHeal`.
        let outcome = await storage.recordMonitorEvent(
            transition, forIdentifier: identifier,
            onlyIfBaselinePredates: event.date, osEventDate: event.date, now: event.date
        )
        guard case .deliver = outcome else {
            logDiscardedCallback(identifier: identifier, transition: transition, outcome: outcome)
            return
        }
        // No ownership re-check after the await: the baseline already advanced, so dropping here
        // would lose a genuine crossing that raced a sync's re-add. A region truly removed in that
        // window delivers one last event.
        if identifier == GeofenceConstants.movementTriggerIdentifier, transition == .exit {
            // The movement pass re-centers on these coords, so a frozen cache would pin it to a stale
            // point. Fire-and-forget so a slow fix can't stall the pending-event drain.
            movementFixResolver.resolve(cached: bestKnownFix(), purpose: .movement) { [weak self] location, isFresh in
                self?.logger.geofenceCallbackDispatched(identifier: identifier, transition: transition)
                self?.onTransition?(identifier, transition, location, event.date, isFresh, self?.eventCircle(for: identifier, raisedAt: event.date) ?? .unknown)
            }
            return
        }
        logger.geofenceCallbackDispatched(identifier: identifier, transition: transition)
        // Business events carry the captured location for context only; nothing sizes to it.
        onTransition?(identifier, transition, currentLocationData(), event.date, false, eventCircle(for: identifier, raisedAt: event.date))
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

    func reportPermissionTier() {
        let status = authManager.authorizationStatus
        let tier = CoreLocationGeofenceMonitor.permissionTier(for: status)
        guard tier != lastLoggedPermissionTier else { return }
        lastLoggedPermissionTier = tier
        switch tier {
        case .blocked:
            logger.geofencePermissionUnavailable(currentStatus: status)
        case .foregroundOnly:
            logger.geofenceBackgroundDeliveryUnavailable(currentStatus: status)
        case .backgroundDelivery:
            logger.geofenceBackgroundDeliveryAvailable(currentStatus: status)
        }
    }

    // MARK: - Authorization

    // Surfaced UNFILTERED in both directions: an improvement lets the bootstrap re-attempt
    // registration, and a downgrade is what disarms visit monitoring.
    private func handleAuthorizationChange() {
        updateServiceSession()
        onAuthorizationChanged?()
    }

    // MARK: - Service session (iOS 18+)

    /// Held only while Always is ALREADY granted: a session above the granted tier can prompt, and
    /// prompting is the host's decision. See the type doc for why iOS 18+ needs one.
    private func updateServiceSession() {
        authManager.updateServiceSession(isAlwaysAuthorized: authManager.authorizationStatus == .authorizedAlways)
    }
}
