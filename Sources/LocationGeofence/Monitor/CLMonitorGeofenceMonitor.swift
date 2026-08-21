import CioInternalCommon
import CoreLocation
import Foundation

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
///
/// Not unit-tested directly — it adapts real, non-substitutable CoreLocation objects. The decision
/// logic lives in `GeofenceStorage` (unit-tested); the adapter is validated on-device.
@available(iOS 17.0, *)
@MainActor
final class CLMonitorGeofenceMonitor: NSObject, GeofenceRegionMonitoring, @preconcurrency CLLocationManagerDelegate {
    // CLMonitor names must be alphanumeric — dots/special chars throw "Monitor name is not valid".
    private static let monitorName = "CustomerIOGeofenceMonitor"
    /// UserDefaults mirror of the monitor's condition identifiers. `CLMonitor` only exposes them
    /// async, but the bootstrap's adopt-vs-re-register decision needs a synchronous read right
    /// after construction — without the mirror that read is empty on every cold launch.
    private static let conditionMirrorKey = "io.customer.sdk.geofence.clmonitor.conditionIdentifiers"

    /// Internal for the `+Registration` extension.
    let logger: Logger
    /// Persists the per-condition dedup baseline + delivery filter (see `MonitorRegionRecord`).
    /// Internal (not private) so the `+Rearm` extension can read it; immutable injected dependency.
    let storage: GeofenceStorage
    private let userDefaults: UserDefaults
    /// Only for auth status/changes + current-location reads; region monitoring is on `CLMonitor`.
    /// Internal for the `+Registration` extension.
    let authManager: CLLocationManager
    /// Freshens the fix behind movement-trigger EXIT dispatches (see `MovementFixResolver`).
    /// Internal (not private) for the `+ContradictionGate` extension's gate-fix resolution.
    let movementFixResolver: MovementFixResolver
    private var onTransition: GeofenceTransitionHandler?
    private var onAuthorizationChanged: GeofenceAuthorizationChangedHandler?
    private var onReconciled: GeofenceReconciledHandler?
    private var lastLoggedPermissionTier: CoreLocationGeofenceMonitor.PermissionTier?

    /// In-memory ownership filter, mirrors `ownedRegionIdentifiers` in the classic monitor.
    /// The three below are internal for the `+Registration` extension.
    var ownedRegionIdentifiers: Set<String> = []
    /// Synchronous view of the monitor's condition identifiers: seeded from the mirror at init,
    /// reconciled against `CLMonitor.identifiers` by the pipeline's first operation, then maintained.
    var knownConditionIdentifiers: Set<String> = []
    /// Geometry each condition was added with, post-clamp. `CLMonitor` exposes no way to read a
    /// condition back, so this is the only record `setMonitoredRegions` can diff against.
    ///
    /// Deliberately NOT seeded from the mirror at init (which has no geometry anyway). A condition
    /// inherited from a previous process may be a reboot zombie — still listed, no longer monitored
    /// (see `rearmConditions`) — and only re-adding revives it. Leaving it absent here makes the
    /// first pass re-register it; when the bootstrap adopts instead, `adoptExistingRegions` seeds it
    /// from the persisted records the re-arm then imposes at the OS.
    var registeredConditions: [String: RegisteredCondition] = [:]
    /// Conditions the OS stopped monitoring since their last registration. The next registration
    /// reseeds their stored baseline instead of preserving it — see `recordMonitorRegistration`.
    var conditionsNeedingBaselineReseed: Set<String> = []
    /// When each condition was last (re)added at the OS, stamped at the add's drain time. The
    /// contradiction gate only vets events landing shortly after an add — the daemon's belief
    /// replays — so this is the gate's applicability check (see `+ContradictionGate`).
    var conditionReaddTimestamps: [String: Date] = [:]

    /// The circle a condition was added with.
    struct RegisteredCondition: Equatable {
        let center: LocationData
        let radius: Double
        let transitionTypes: Set<GeofenceTransition>
    }

    /// Memoized `CLMonitor` creation so every caller shares one instance — creating a second
    /// monitor with the same name throws "Monitor named ... is already in use".
    private var monitorTask: Task<CLMonitor, Never>?
    /// Single long-lived consumer of `monitor.events`. Never cancelled or recreated: a second
    /// subscription steals events from the first rather than duplicating them.
    private var consumeTask: Task<Void, Never>?
    /// Tail of the FIFO mutation pipeline; each enqueued operation awaits the previous one.
    private var lastQueuedOperation: Task<Void, Never>?
    /// Events received before the bootstrap bound `onTransition` (see `handle(event:)`).
    private var pendingEvents: [CLMonitor.Event] = []
    private var isDrainingPendingEvents = false
    private static let maxPendingEvents = 64
    /// Held `CLServiceSession` (iOS 18+), stored untyped because stored properties can't carry
    /// availability. Non-nil only while Always authorization is granted.
    private var serviceSession: AnyObject?

    init(
        logger: Logger,
        storage: GeofenceStorage,
        userDefaults: UserDefaults = .standard
    ) {
        self.logger = logger
        self.storage = storage
        self.userDefaults = userDefaults
        self.authManager = CLLocationManager()
        self.movementFixResolver = MovementFixResolver(
            logger: logger,
            backgroundTaskRunner: GeofenceBackgroundTime.runner(name: "io.customer.geofence.movement-fix")
        )
        super.init()
        let mirrored = Set(userDefaults.stringArray(forKey: Self.conditionMirrorKey) ?? [])
        self.knownConditionIdentifiers = mirrored
        // Everything under our private monitor name was registered by the SDK, so persisted
        // conditions are owned as soon as the process starts — a cold-wake event must find its
        // identifier in the filter before any async work has run.
        self.ownedRegionIdentifiers = mirrored
        // Auth-status changes only; no region callbacks arrive here.
        authManager.delegate = self
        updateServiceSession()
        enqueueMonitorOperation { [weak self] monitor in
            await self?.reconcileKnownConditions(with: monitor)
        }
        startConsuming()
    }

    // MARK: - CLMonitor lifecycle

    private func monitorInstance() -> Task<CLMonitor, Never> {
        if let monitorTask { return monitorTask }
        let name = Self.monitorName
        // Created immediately and unconditionally. Despite the CLMonitor header's note, do NOT defer
        // creation on protected-data availability: the flag is false while the device is locked —
        // the normal state for a background crossing wake — and can read false on prewarmed launches
        // with no notification following; either way the events consumer would never attach. An
        // empty pre-first-unlock conditions read self-heals via reconcile.
        let task = Task { await CLMonitor(name) }
        monitorTask = task
        return task
    }

    /// Runs `operation` after every previously enqueued operation has finished. All monitor
    /// mutations go through here so caller-side ordering (stop-all, then re-register) is preserved
    /// across the async hops to the `CLMonitor` actor. Internal (not private) for `+Rearm`.
    func enqueueMonitorOperation(_ operation: @escaping @MainActor (CLMonitor) async -> Void) {
        let previous = lastQueuedOperation
        let monitorTask = monitorInstance()
        lastQueuedOperation = Task { @MainActor in
            await previous?.value
            await operation(monitorTask.value)
        }
    }

    /// First pipeline operation: replace the mirror-seeded snapshot with `CLMonitor`'s persisted
    /// truth. Safe to assign wholesale because no add/remove can have run yet (FIFO).
    private func reconcileKnownConditions(with monitor: CLMonitor) async {
        let persisted = Set(await monitor.identifiers)
        // A drifted mirror means bootstrap's synchronous adopt/re-register decision may have been
        // wrong — notify so it re-evaluates against live truth, not at the next sync.
        let drifted = persisted != knownConditionIdentifiers
        knownConditionIdentifiers = persisted
        ownedRegionIdentifiers.formUnion(persisted)
        // `registeredConditions` is deliberately not filtered against `persisted`. It starts empty
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
                try? await Task.sleep(nanoseconds: backoffNanos)
                backoffNanos = min(backoffNanos * 2, maxBackoffNanos)
            }
        }
    }

    private func handle(event: CLMonitor.Event) async {
        // Hold events until the bootstrap binds `onTransition`: processing earlier would advance the
        // persisted dedup baseline and then drop the delivery on the nil handler, suppressing the
        // later re-emission of the same state. New arrivals queue behind any backlog — including
        // while the drain has popped its last event but is still awaiting `process`, where the queue
        // reads empty — so per-condition order holds. Capped against a process that never binds —
        // dropping oldest is safe because CLMonitor re-emits current state.
        if onTransition == nil || !pendingEvents.isEmpty || isDrainingPendingEvents {
            pendingEvents.append(event)
            if pendingEvents.count > Self.maxPendingEvents { pendingEvents.removeFirst() }
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

    private func process(event: CLMonitor.Event) async {
        let identifier = event.identifier
        guard ownedRegionIdentifiers.contains(identifier) else { return }
        let transition: GeofenceTransition
        switch event.state {
        case .satisfied:
            transition = .enter
        case .unsatisfied:
            transition = .exit
        case .unknown:
            return
        case .unmonitored:
            // CLMonitor gave up on the condition (e.g. condition budget exceeded). Drop the mirror
            // entry and the recorded circle so the next sync re-registers it. The stored baseline
            // goes too — the region stays in the desired set, so nothing else prunes it, and the
            // device can cross while it is unmonitored.
            //
            // Ownership is deliberately KEPT. It only gates which events this process accepts, and
            // the OS sends events solely for conditions it monitors, so keeping it can't admit a
            // spurious one. Dropping it strands the region instead: an add already queued here
            // revives the condition without restoring ownership, and a condition the OS gave up on
            // stays listed and revives on its own once budget frees (measured). Worst case is the
            // movement trigger — its events are what drive the next sync, so dropping its ownership
            // removes the only thing that would restore it before the process restarts.
            logger.geofenceMonitorStoppedMonitoringRegion(identifier)
            knownConditionIdentifiers.remove(identifier)
            registeredConditions.removeValue(forKey: identifier)
            // Whichever registration comes next must reseed the baseline rather than preserve it.
            // The clear below only covers the case where none comes: a re-registration with the same
            // circle preserves the stored state by design, and after the OS gave up that state is no
            // longer known to match reality.
            conditionsNeedingBaselineReseed.insert(identifier)
            persistConditionMirror()
            // On the pipeline, and skipped if a registration has re-added the identifier since the
            // line above cleared it — deleting a baseline that add just wrote would cost the next
            // crossing. Keyed on this monitor's own record of completed adds rather than on
            // `CLMonitor.identifiers`: a condition the OS gave up on stays listed there (measured),
            // so reading that would make this clear permanently inert.
            enqueueMonitorOperation { [weak self] _ in
                guard let self, !self.knownConditionIdentifiers.contains(identifier) else { return }
                await self.storage.clearMonitorRegionRecord(identifier: identifier)
            }
            return
        @unknown default:
            return
        }
        // Runs BEFORE the baseline advance below: a refused event must leave the stored baseline
        // untouched so the daemon's own re-evaluation dedups against it (see `+ContradictionGate`).
        if identifier != GeofenceConstants.movementTriggerIdentifier,
           await isEventContradictedByFreshFix(identifier: identifier, transition: transition) {
            return
        }
        guard case .deliver = await storage.recordMonitorEvent(transition, forIdentifier: identifier) else { return }
        // No ownership re-check after the await: the baseline already advanced, so dropping here
        // loses the transition permanently — a sync's stop-all + re-add swap would eat a genuine
        // crossing that raced it. A region truly removed in that window delivers one last gated event.
        if identifier == GeofenceConstants.movementTriggerIdentifier, transition == .exit {
            // The movement pass re-centers the trigger and measures displacement at these coords, so
            // a frozen cached fix pins the whole pipeline to a stale point — freshen it first.
            // Fire-and-forget so a slow fix can't stall the pending-event drain behind it.
            movementFixResolver.resolve(cached: bestKnownFix()) { [weak self] location in
                self?.onTransition?(identifier, transition, location)
            }
            return
        }
        onTransition?(identifier, transition, currentLocationData())
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

    // MARK: - CLLocationManagerDelegate

    // Fires once when the delegate is set (harmless — the bootstrap installs its handler after
    // reading status synchronously) and again on every change. Keeps the service session in step
    // with the granted tier and lets the bootstrap re-attempt registration when permission improves.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateServiceSession()
        onAuthorizationChanged?()
    }

    // MARK: - Service session (iOS 18+)

    /// On iOS 18+, `CLMonitor.events` stops yielding in the background unless a `CLServiceSession`
    /// asserts continued interest — Always authorization alone no longer suffices. Held for the
    /// monitor's lifetime, but only while Always is ALREADY granted: a session above the granted
    /// tier can put up a permission prompt, and prompting is the host's decision, never the SDK's.
    private func updateServiceSession() {
        guard #available(iOS 18.0, *) else { return }
        let isAlwaysAuthorized = authManager.authorizationStatus == .authorizedAlways
        if isAlwaysAuthorized {
            guard serviceSession == nil else { return }
            serviceSession = CLServiceSession(authorization: .always)
        } else if let session = serviceSession as? CLServiceSession {
            session.invalidate()
            serviceSession = nil
        }
    }

    // MARK: - Private

    func persistConditionMirror() {
        userDefaults.set(knownConditionIdentifiers.sorted(), forKey: Self.conditionMirrorKey)
    }

    /// Newest usable fix across the auth manager's cache and the resolver's requested fixes.
    /// The manager's cache can freeze at process start on a long-suspended process, so a fresher
    /// resolver fix must win wherever cached position is read. Internal (not private) for the
    /// `+ContradictionGate` extension's gate-fix resolution.
    func bestKnownFix() -> CLLocation? {
        let cached = authManager.location.flatMap { CLLocationCoordinate2DIsValid($0.coordinate) ? $0 : nil }
        guard let resolved = movementFixResolver.latestFix else { return cached }
        guard let cached else { return resolved }
        return resolved.timestamp > cached.timestamp ? resolved : cached
    }

    private func currentLocationData() -> LocationData? {
        guard let location = bestKnownFix() else { return nil }
        return LocationData(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    /// Whether the device is inside the circle per the last known location; `nil` without a usable
    /// fix. No accuracy padding: a wrong guess costs one corrective event, absorbed by the baseline.
    func isDeviceInside(center: CLLocationCoordinate2D, radius: CLLocationDistance) -> Bool? {
        guard let location = bestKnownFix() else { return nil }
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return location.distance(from: centerLocation) <= radius
    }
}
