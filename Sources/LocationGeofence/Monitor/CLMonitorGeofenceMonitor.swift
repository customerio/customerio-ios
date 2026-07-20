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

    private let logger: Logger
    /// Persists the per-condition dedup baseline + delivery filter (see `MonitorRegionRecord`).
    /// Internal (not private) so the `+Rearm` extension can read it; immutable injected dependency.
    let storage: GeofenceStorage
    private let userDefaults: UserDefaults
    /// Only for auth status/changes + current-location reads; region monitoring is on `CLMonitor`.
    private let authManager: CLLocationManager
    private var onTransition: GeofenceTransitionHandler?
    private var onAuthorizationChanged: GeofenceAuthorizationChangedHandler?
    private var onReconciled: GeofenceReconciledHandler?
    private var lastLoggedPermissionTier: CoreLocationGeofenceMonitor.PermissionTier?

    /// In-memory ownership filter, mirrors `ownedRegionIdentifiers` in the classic monitor.
    private var ownedRegionIdentifiers: Set<String> = []
    /// Synchronous view of the monitor's condition identifiers: seeded from the mirror at init,
    /// reconciled against `CLMonitor.identifiers` by the pipeline's first operation, then maintained.
    private var knownConditionIdentifiers: Set<String> = []

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
            // CLMonitor gave up on the condition (e.g. condition budget exceeded). As with classic
            // monitoringDidFail: drop ownership and the mirror entry so nothing claims a condition
            // the OS no longer holds; the next sync re-registers a fresh set.
            ownedRegionIdentifiers.remove(identifier)
            knownConditionIdentifiers.remove(identifier)
            persistConditionMirror()
            return
        @unknown default:
            return
        }
        guard case .deliver = await storage.recordMonitorEvent(transition, forIdentifier: identifier) else { return }
        // The await hopped off the main actor; re-check ownership so a region removed during that
        // window isn't delivered (parity with the classic delegate's synchronous ownership check).
        guard ownedRegionIdentifiers.contains(identifier) else { return }
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

    func adoptExistingRegions(matching identifiers: Set<String>) {
        let adopted = identifiers.intersection(knownConditionIdentifiers)
        guard !adopted.isEmpty else { return }
        ownedRegionIdentifiers.formUnion(adopted)
        rearmConditions(adopted)
        logger.geofenceRegionsAdopted(count: adopted.count)
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

    func startMonitoring(identifier: String, center: LocationData, radius: Double, transitionTypes: Set<GeofenceTransition>) {
        reportPermissionTier()
        guard CoreLocationGeofenceMonitor.permissionTier(for: authManager.authorizationStatus) != .blocked else { return }

        let coordinate = CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            logger.geofenceInvalidCoordinatesForRegion(identifier)
            return
        }

        // Populate the ownership filter synchronously so a fast-arriving event isn't dropped.
        ownedRegionIdentifiers.insert(identifier)

        // Parity with the classic monitor's clamp; `maximumRegionMonitoringDistance` is a deprecated
        // but harmless read with no CLMonitor equivalent — both paths register identical geometry.
        let clampedRadius = min(radius, authManager.maximumRegionMonitoringDistance)

        // The device's ACTUAL state seeds both CLMonitor's `assuming:` hint and the stored baseline
        // (see `recordMonitorRegistration`: registration stays silent, the first real crossing
        // delivers). No fix → geometric expectation: trigger is device-centered (inside),
        // business geofences outside.
        let isMovementTrigger = identifier == GeofenceConstants.movementTriggerIdentifier
        let isInside = isDeviceInside(center: coordinate, radius: clampedRadius) ?? isMovementTrigger
        let initialTransition: GeofenceTransition = isInside ? .enter : .exit
        let assumedState: CLMonitor.Event.State = isInside ? .satisfied : .unsatisfied

        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            // Persist before the OS add: storage keys off recorded geometry to preserve the baseline
            // on an unchanged re-register and reseed on a new/changed circle. The decision lives in
            // storage because this runs after stop-all, when CLMonitor's own record is already gone.
            await self.storage.recordMonitorRegistration(
                identifier: identifier,
                transitionTypes: transitionTypes,
                initialState: initialTransition,
                center: LocationData(latitude: coordinate.latitude, longitude: coordinate.longitude),
                radius: clampedRadius
            )
            let condition = CLMonitor.CircularGeographicCondition(center: coordinate, radius: clampedRadius)
            await monitor.add(condition, identifier: identifier, assuming: assumedState)
            self.knownConditionIdentifiers.insert(identifier)
            self.persistConditionMirror()
        }
    }

    func stopMonitoring(identifier: String) {
        guard ownedRegionIdentifiers.remove(identifier) != nil else { return }
        // The storage record intentionally survives removal: a stop-all + re-register cycle relies
        // on the persisted baseline to suppress CLMonitor's re-evaluation of an unchanged state.
        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            await monitor.remove(identifier)
            self.knownConditionIdentifiers.remove(identifier)
            self.persistConditionMirror()
        }
    }

    func stopMonitoringAll() {
        ownedRegionIdentifiers.removeAll()
        // Clear against CLMonitor's LIVE identifiers, not the owned/mirror snapshot: an empty owned
        // set or a lossy mirror must not leave a stale SDK condition holding an OS slot.
        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            for identifier in await monitor.identifiers {
                await monitor.remove(identifier)
            }
            self.knownConditionIdentifiers.removeAll()
            self.persistConditionMirror()
        }
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

    private func persistConditionMirror() {
        userDefaults.set(knownConditionIdentifiers.sorted(), forKey: Self.conditionMirrorKey)
    }

    private func currentLocationData() -> LocationData? {
        guard let location = authManager.location,
              CLLocationCoordinate2DIsValid(location.coordinate)
        else {
            return nil
        }
        return LocationData(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    /// Whether the device is inside the circle per the last known location; `nil` without a usable
    /// fix. No accuracy padding: a wrong guess costs one corrective event, absorbed by the baseline.
    private func isDeviceInside(center: CLLocationCoordinate2D, radius: CLLocationDistance) -> Bool? {
        guard let location = authManager.location,
              CLLocationCoordinate2DIsValid(location.coordinate)
        else {
            return nil
        }
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return location.distance(from: centerLocation) <= radius
    }
}
