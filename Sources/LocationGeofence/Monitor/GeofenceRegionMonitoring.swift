import CioInternalCommon
import CoreLocation
import Foundation

/// Callback when a geofence transition occurs.
/// Parameters: region identifier, transition type, user's current location (from CLLocationManager.location, may be nil).
///
/// Invoked synchronously on the main actor (CLLocationManager delegate callbacks arrive on main).
/// The closure body is not statically isolated — callers are free to hop to whatever actor they
/// need: `Task.detached { ... }` for off-main work, `MainActor.assumeIsolated { ... }` for direct
/// main-actor reads, or an `await someActor.method()` to hand off to another isolation domain.
/// `occurredAt` is when the crossing happened — the OS event's date, or the fix's timestamp for a
/// synthesized heal. Lets a consumer order a late or replayed transition against what it believes,
/// which is why every dispatch site owes one: a consumer handed no date writes unordered.
///
/// `locationIsFresh` says whether the attached coordinates came from a fix delivered for THIS event
/// rather than a cached one. A movement pass falls back to the cached fix when its request fails or
/// times out, and that fix is by definition the stale one that prompted the request — a consumer
/// sizing anything to those coordinates has to know the difference.
typealias GeofenceTransitionHandler = @Sendable (String, GeofenceTransition, LocationData?, Date, Bool) -> Void

/// Callback when iOS reports a change to the location authorization status.
/// Invoked on the main actor — same isolation domain as `CLLocationManagerDelegate`.
typealias GeofenceAuthorizationChangedHandler = @MainActor () -> Void

/// Callback once the monitor has reconciled its owned set against the OS's live truth.
/// Invoked on the main actor.
typealias GeofenceReconciledHandler = @MainActor () -> Void

/// A circular region the caller wants monitored, as handed to `setMonitoredRegions`.
struct GeofenceRegionRequest: Equatable, Sendable {
    let identifier: String
    let center: LocationData
    let radius: Double
    let transitionTypes: Set<GeofenceTransition>
}

extension GeofenceRegionRequest {
    /// Latitude/longitude slack, ~1cm. Absorbs float round-tripping through CoreLocation and JSON.
    private static let coordinateTolerance = 1e-7
    /// Radius slack in meters.
    private static let radiusTolerance = 0.5

    /// Whether an already-registered circle matches this request closely enough to leave alone.
    /// Compares against the radius the OS would actually hold, so a fence larger than the cap
    /// doesn't read as "changed" on every pass and churn forever.
    func matchesRegistered(
        center: LocationData,
        radius: Double,
        transitionTypes: Set<GeofenceTransition>,
        clampedTo maximumRadius: Double
    ) -> Bool {
        abs(center.latitude - self.center.latitude) < Self.coordinateTolerance
            && abs(center.longitude - self.center.longitude) < Self.coordinateTolerance
            && abs(radius - min(self.radius, maximumRadius)) < Self.radiusTolerance
            && transitionTypes == self.transitionTypes
    }
}

/// What `setMonitoredRegions` changed. Everything in the desired set that isn't listed here was
/// already registered with the same circle and was left untouched — the point of the call.
struct GeofenceRegionDiff: Equatable, Sendable {
    let added: Set<String>
    let removed: Set<String>
}

/// Abstracts CLLocationManager's region monitoring.
///
/// The monitor owns a CLLocationManager and handles the delegate callbacks for region events.
/// Business logic decides which regions to monitor; this component only manages the OS registrations.
///
/// Main-actor isolated because CLLocationManager must be created and called on the main thread,
/// and its delegate callbacks arrive on main. Keeping the monitor's bookkeeping state in the
/// same isolation domain as the OS calls removes the need for locks, fire-and-forget Tasks,
/// or reentrancy reasoning between state mutations and OS dispatches.
@MainActor
protocol GeofenceRegionMonitoring: AnyObject, Sendable {
    /// Sets the handler called when a geofence transition (enter/exit) occurs.
    func setOnTransition(_ handler: GeofenceTransitionHandler?)

    /// Sets the handler invoked when iOS reports an authorization status change. Lets callers
    /// re-attempt registration when permission improves mid-process (e.g. host's permission
    /// prompt resolved, or the user toggled the setting in Settings).
    func setOnAuthorizationChanged(_ handler: GeofenceAuthorizationChangedHandler?)

    /// Sets the handler called once the monitor reconciles its owned set against the OS's live truth.
    /// Only the CLMonitor path needs it: its live identifiers are async, so the fast synchronous
    /// adopt/re-register decision runs off a cached mirror, and a drift correction must re-trigger
    /// that decision. The classic monitor reads `monitoredRegions` synchronously — default no-op.
    func setOnReconciled(_ handler: GeofenceReconciledHandler?)

    /// Starts monitoring a circular geofence region.
    /// - Parameters:
    ///   - identifier: Unique identifier for the region.
    ///   - center: Center coordinate.
    ///   - radius: Radius in meters. Clamped to `CLLocationManager.maximumRegionMonitoringDistance` if exceeded.
    ///   - transitionTypes: Which transitions to monitor (enter, exit, or both).
    func startMonitoring(identifier: String, center: LocationData, radius: Double, transitionTypes: Set<GeofenceTransition>)

    /// Stops monitoring the region with the given identifier.
    func stopMonitoring(identifier: String)

    /// Reconciles the monitored set to exactly `regions`: stops what is no longer wanted, starts
    /// what is new or whose circle changed, and leaves everything else registered as-is.
    ///
    /// Leaving unchanged regions untouched is part of the contract, not an optimization: stopping
    /// and re-adding a region discards any boundary crossing the OS has detected but not yet
    /// delivered, and neither monitor replays it. Implementations must not re-register a region
    /// whose circle is unchanged.
    @discardableResult
    func setMonitoredRegions(_ regions: [GeofenceRegionRequest]) -> GeofenceRegionDiff

    /// Stops monitoring all regions managed by this monitor.
    func stopMonitoringAll()

    /// Returns the set of region identifiers currently being monitored by this monitor.
    var monitoredRegionIdentifiers: Set<String> { get }

    /// The largest radius the OS actually monitors; every registered region's radius is clamped to
    /// this (`CLLocationManager.maximumRegionMonitoringDistance`). Apple defines no floor for it, so
    /// a fence radius can exceed it — callers deciding whether the device is inside a registered
    /// circle must clamp to it too, or they'd treat a device outside the monitored circle as inside.
    var maximumMonitoringRadius: Double { get }

    /// Region identifiers the OS still actively monitors app-wide (`CLLocationManager.monitoredRegions`).
    /// These persist across process launch and device reboot, so on a fresh process this is populated
    /// even though `monitoredRegionIdentifiers` (the in-memory ownership filter) starts empty.
    var osMonitoredRegionIdentifiers: Set<String> { get }

    /// Re-claims the OS-persisted regions whose identifiers are in `identifiers` as owned by this
    /// monitor, restoring transition recognition on a fresh process where the OS kept monitoring
    /// but the in-memory ownership set was lost. `records` is the persisted per-condition
    /// bookkeeping (`GeofenceStorage.getMonitorRegionRecords`); the CLMonitor path seeds its
    /// geometry map from it synchronously, so a sync arriving before the queued re-arm drains
    /// reads adopted regions as unchanged instead of re-registering them all. Adoption must not
    /// emit events for unchanged regions; the OS-side mechanism is implementation-specific (the
    /// classic monitor adopts in place and ignores `records`, the CLMonitor path re-arms each
    /// condition — see `rearmConditions`).
    func adoptExistingRegions(matching identifiers: Set<String>, records: [String: MonitorRegionRecord])

    /// Logs the current authorization tier (background delivery / foreground only / blocked),
    /// deduped so it emits only when the tier changes since the last report.
    func reportPermissionTier()
}

extension GeofenceRegionMonitoring {
    /// Default no-op: only the CLMonitor path reconciles asynchronously against live OS truth.
    func setOnReconciled(_ handler: GeofenceReconciledHandler?) {}
}
