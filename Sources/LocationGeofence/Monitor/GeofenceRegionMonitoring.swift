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
///
/// The last parameter is the circle the OS was monitoring when it RAISED this event — not the one
/// registered now, which a refresh may already have replaced. A consumer reasoning about what the
/// crossing PROVES needs it, since the guarantee a covering circle gives only holds for its own ring.
typealias GeofenceTransitionHandler = @Sendable (String, GeofenceTransition, LocationData?, Date, Bool, GeofenceEventCircle) -> Void

/// Callback when iOS reports a change to the location authorization status.
/// Invoked on the main actor — same isolation domain as `CLLocationManagerDelegate`.
typealias GeofenceAuthorizationChangedHandler = @MainActor () -> Void

/// Callback once the monitor has reconciled its owned set against the OS's live truth.
/// Invoked on the main actor.
typealias GeofenceReconciledHandler = @MainActor () -> Void

/// What the monitor can say about the circle an event was raised against.
///
/// `unknown` and `expired` must not collapse into one "no circle" case. `unknown` is a cold wake:
/// the OS is evaluating a condition this process never recorded, so the event has to be taken as
/// current or real crossings are dropped. `expired` is the monitor knowing the circle is gone, and
/// an event that cannot name its own circle proves nothing about the fence's geometry now.
enum GeofenceEventCircle: Equatable, Sendable {
    case circle(MonitoredCircle)
    case unknown
    case expired

    /// Maps what the ledger holds onto what a consumer is told. Here rather than at the lookup so
    /// it can be exercised: the monitor owning that lookup cannot be built in a unit test, and a
    /// mapping living inside it leaves the ledger's output and the consumer's input pinned only in
    /// isolation, with nothing failing if the chain between them breaks.
    init(_ attribution: EventAttribution, maximumRadius: Double) {
        switch attribution {
        case .generation(let condition):
            self = .circle(MonitoredCircle(
                center: condition.center, radius: condition.radius, maximumRadius: maximumRadius
            ))
        case .noneHeld:
            self = .unknown
        case .expired:
            self = .expired
        }
    }
}

/// The circle the OS was monitoring when it raised an event. Carried with the event because a
/// refresh can replace a fence under the same id, and a consumer reasoning about what the crossing
/// PROVES has to know which circle it crossed — the current fence's circle may be a different one.
struct MonitoredCircle: Equatable, Sendable {
    let center: LocationData
    /// As REGISTERED, so already clamped to `maximumRadius`. Comparing it to a fence's own radius
    /// without clamping that too reads every over-cap fence as changed, forever.
    let radius: Double
    /// The cap the producer clamped against, carried so a consumer can reconstruct what the OS
    /// would hold for a given fence.
    let maximumRadius: Double

    /// Whether this is the circle `geofence` is currently monitored by. Same comparison
    /// `GeofenceRegionRequest.matchesRegistered` makes, and for the same reasons: clamp the fence's
    /// radius to what the OS would actually hold, and allow for the float round trip through
    /// CoreLocation rather than assuming it is exact.
    func matches(_ geofence: Geofence) -> Bool {
        abs(center.latitude - geofence.latitude) < Self.coordinateTolerance
            && abs(center.longitude - geofence.longitude) < Self.coordinateTolerance
            && abs(radius - min(geofence.radius, maximumRadius)) < Self.radiusTolerance
    }

    /// Same slack as `GeofenceRegionRequest`; kept in step with it deliberately — the two answer the
    /// same question about the same round trip.
    private static let coordinateTolerance = 1e-7
    private static let radiusTolerance = 0.5
}

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
