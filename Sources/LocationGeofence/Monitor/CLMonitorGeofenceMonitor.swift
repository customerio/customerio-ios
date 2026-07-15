import CioInternalCommon
import CoreLocation
import Foundation

/// `CLMonitor`-backed implementation of `GeofenceRegionMonitoring`, where the classic
/// `CLLocationManager` region-monitoring APIs are deprecated. Available at iOS 17, but the DI
/// accessor only routes to it on iOS 18+ (13–17 keep the classic monitor) — iOS 18 is the floor
/// because only there does `CLServiceSession` keep background delivery alive (see the accessor).
///
/// Behavioral contract: match the classic monitor — deliver only genuine boundary crossings, only
/// for the registered transition types. `CLMonitor` differs from classic in ways this type has to
/// compensate for:
/// - It re-emits a condition's CURRENT state on process start and system re-evaluation
///   (unlock/foreground), not just on crossings → per-condition dedup baseline, persisted in
///   `GeofenceStorage` so a cold-wake compares against the pre-kill state.
/// - It has no `notifyOnEntry`/`notifyOnExit` equivalent → the delivery filter is stored per
///   condition and applied here.
/// - Its API is async (an actor + `events` sequence) while the protocol is synchronous → mutations
///   run on a serialized FIFO pipeline so a re-registration's removes can never overtake its adds.
/// - On iOS 18+, `events` yields nothing in the background unless a `CLServiceSession` asserts the
///   app's continued interest → hold one for the monitor's lifetime, created only when Always is
///   already granted so the SDK never triggers a permission prompt (the host owns permission).
/// - Its conditions persist in the app container under our private monitor name, so everything in
///   it is SDK-owned by construction (classic `monitoredRegions` is shared app-wide).
///
/// Not unit-tested directly: it adapts a real `CLMonitor` actor (keyed by a process-global name),
/// a real `CLLocationManager`, and an async event stream — none substitutable, and constructing one
/// persists to the app container. Its decision logic (dedup baseline, delivery filter) lives in
/// `GeofenceStorage` and the shared permission-tier function, both unit-tested; the adapter is
/// validated on-device (background delivery, cold-wake, reboot).
@available(iOS 17.0, *)
@MainActor
final class CLMonitorGeofenceMonitor: NSObject, GeofenceRegionMonitoring, @preconcurrency CLLocationManagerDelegate {
    // CLMonitor names must be alphanumeric — dots/special chars throw "Monitor name is not valid".
    private static let monitorName = "CustomerIOGeofenceMonitor"
    /// UserDefaults key mirroring the monitor's condition identifiers. `CLMonitor` only exposes
    /// them async, but the bootstrap decides adopt-vs-re-register from a synchronous read right
    /// after construction — without the mirror that read is empty on every cold launch and the
    /// adopt path is unreachable.
    private static let conditionMirrorKey = "io.customer.sdk.geofence.clmonitor.conditionIdentifiers"

    private let logger: Logger
    /// Persists the per-condition dedup baseline + delivery filter (see `MonitorRegionRecord`).
    private let storage: GeofenceStorage
    private let userDefaults: UserDefaults
    /// Only for auth status/changes + current-location reads; region monitoring is on `CLMonitor`.
    private let authManager: CLLocationManager
    private var onTransition: GeofenceTransitionHandler?
    private var onAuthorizationChanged: GeofenceAuthorizationChangedHandler?
    private var lastLoggedPermissionTier: CoreLocationGeofenceMonitor.PermissionTier?

    /// In-memory ownership filter, mirrors `ownedRegionIdentifiers` in the classic monitor.
    private var ownedRegionIdentifiers: Set<String> = []
    /// Synchronous view of the monitor's condition identifiers: seeded from the UserDefaults mirror
    /// at init, reconciled against `CLMonitor.identifiers` by the pipeline's first operation, then
    /// maintained by every add/remove.
    private var knownConditionIdentifiers: Set<String> = []

    /// Memoized `CLMonitor` creation so every caller shares one instance — creating a second
    /// monitor with the same name throws "Monitor named ... is already in use".
    private var monitorTask: Task<CLMonitor, Never>?
    /// Single long-lived consumer of `monitor.events`. Never cancelled or recreated: a second
    /// subscription steals events from the first rather than duplicating them.
    private var consumeTask: Task<Void, Never>?
    /// Tail of the FIFO mutation pipeline; each enqueued operation awaits the previous one.
    private var lastQueuedOperation: Task<Void, Never>?
    /// Held `CLServiceSession` (iOS 18+), stored untyped because stored properties can't carry
    /// availability. Non-nil only while Always authorization is granted.
    private var serviceSession: AnyObject?

    init(logger: Logger, storage: GeofenceStorage, userDefaults: UserDefaults = .standard) {
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
        let task = Task { await CLMonitor(name) }
        monitorTask = task
        return task
    }

    /// Runs `operation` after every previously enqueued operation has finished. All monitor
    /// mutations go through here so caller-side ordering (stop-all, then re-register) is preserved
    /// across the async hops to the `CLMonitor` actor.
    private func enqueueMonitorOperation(_ operation: @escaping @MainActor (CLMonitor) async -> Void) {
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
        knownConditionIdentifiers = persisted
        ownedRegionIdentifiers.formUnion(persisted)
        persistConditionMirror()
    }

    private func startConsuming() {
        consumeTask = Task { [weak self] in
            guard let self else { return }
            let monitor = await self.monitorInstance().value
            do {
                for try await event in await monitor.events {
                    await self.handle(event: event)
                }
            } catch {
                self.logger.geofenceMonitorEventStreamFailed(error: error)
            }
        }
    }

    private func handle(event: CLMonitor.Event) async {
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
            // CLMonitor gave up on the condition (e.g. the ~20-condition budget was exceeded).
            // Mirror the classic monitoringDidFail handling: drop ownership so later events for a
            // half-alive condition aren't delivered; the next sync re-registers a fresh set. Also
            // drop it from the condition mirror so `osMonitoredRegionIdentifiers` doesn't keep
            // claiming a condition the OS no longer holds.
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

    var osMonitoredRegionIdentifiers: Set<String> {
        knownConditionIdentifiers
    }

    func adoptExistingRegions(matching identifiers: Set<String>) {
        let adopted = identifiers.intersection(knownConditionIdentifiers)
        guard !adopted.isEmpty else { return }
        ownedRegionIdentifiers.formUnion(adopted)
        logger.geofenceRegionsAdopted(count: adopted.count)
    }

    func setOnTransition(_ handler: GeofenceTransitionHandler?) {
        onTransition = handler
    }

    func setOnAuthorizationChanged(_ handler: GeofenceAuthorizationChangedHandler?) {
        onAuthorizationChanged = handler
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

        // Parity with the classic monitor, which clamps to the same cap. `maximumRegionMonitoringDistance`
        // lives on the (deprecated) CLLocationManager, but it's a harmless property read and there is no
        // CLMonitor equivalent, so use it to keep both paths registering identical geometry.
        let clampedRadius = min(radius, authManager.maximumRegionMonitoringDistance)

        // The device's ACTUAL state relative to the circle seeds both CLMonitor's `assuming:` hint and
        // the stored baseline (see `recordMonitorRegistration` for why that keeps registration silent
        // yet the first real crossing delivers). Fall back to the geometric expectation when there's no
        // fix: the movement trigger is centered on the device (inside); business geofences are outside.
        let isMovementTrigger = identifier == GeofenceConstants.movementTriggerIdentifier
        let isInside = isDeviceInside(center: coordinate, radius: clampedRadius) ?? isMovementTrigger
        let initialTransition: GeofenceTransition = isInside ? .enter : .exit
        let assumedState: CLMonitor.Event.State = isInside ? .satisfied : .unsatisfied

        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            // Unchanged geometry → leave the condition in place and PRESERVE the baseline. Re-adding
            // resets CLMonitor's own state tracking and provokes a re-evaluation event for nothing.
            if let existing = await monitor.record(for: identifier)?.condition as? CLMonitor.CircularGeographicCondition,
               existing.center.latitude == coordinate.latitude,
               existing.center.longitude == coordinate.longitude,
               existing.radius == clampedRadius {
                self.knownConditionIdentifiers.insert(identifier)
                await self.storage.recordMonitorRegistration(
                    identifier: identifier,
                    transitionTypes: transitionTypes,
                    initialState: initialTransition,
                    resetBaseline: false
                )
                return
            }
            // Fresh circle (new condition or changed geometry): reset the baseline to the device's
            // actual state for this circle BEFORE the OS add, so a changed geofence doesn't carry the
            // stale baseline from its old geometry.
            await self.storage.recordMonitorRegistration(
                identifier: identifier,
                transitionTypes: transitionTypes,
                initialState: initialTransition,
                resetBaseline: true
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
        let identifiers = ownedRegionIdentifiers
        ownedRegionIdentifiers.removeAll()
        guard !identifiers.isEmpty else { return }
        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            for identifier in identifiers {
                await monitor.remove(identifier)
                self.knownConditionIdentifiers.remove(identifier)
            }
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
    /// asserts the app's continued interest — Always authorization alone no longer suffices. Hold
    /// one for the monitor's lifetime, but only while Always is ALREADY granted: creating a session
    /// above the granted tier can put up a permission prompt, and prompting is the host's decision,
    /// never the SDK's. iOS 17 has no sessions and delivers background events without one.
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

    /// Whether the device is currently inside the circle, from the last known location — used to seed
    /// a registration's baseline to reality. `nil` when there's no usable fix, so the caller falls
    /// back to the geometric expectation. Compares against `radius` directly (no accuracy padding):
    /// a wrong guess only costs one corrective event, which the baseline absorbs on the next crossing.
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

// MARK: - DI

@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    /// Process-wide singleton, same lifetime rationale as `CoreLocationGeofenceMonitor.shared`.
    @MainActor
    static let shared = CLMonitorGeofenceMonitor(
        logger: DIGraphShared.shared.logger,
        storage: DIGraphShared.shared.geofenceStorage
    )
}
