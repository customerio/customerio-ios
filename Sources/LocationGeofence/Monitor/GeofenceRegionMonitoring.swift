import CioInternalCommon
import CoreLocation
import Foundation

/// Callback when a geofence transition occurs. Parameters, in order:
/// - region identifier and transition type;
/// - the device location (may be nil);
/// - `occurredAt`: the OS event's date (receipt time on the classic path, which has none), or the
///   fix's timestamp for a synthesized heal, so a consumer can order a late or replayed transition;
/// - `locationIsFresh`: whether the coordinates came from a fix obtained for THIS event rather than
///   a cached one, which after a failed request is the stale fix that prompted it;
/// - the circle the OS was monitoring when it RAISED the event, which a refresh may since have
///   replaced.
///
/// Invoked on the main actor, but the closure is not statically isolated; hop as needed.
typealias GeofenceTransitionHandler = @Sendable (String, GeofenceTransition, LocationData?, Date, Bool, GeofenceEventCircle) -> Void

/// Callback when iOS reports a change to the location authorization status.
/// Invoked on the main actor — same isolation domain as `CLLocationManagerDelegate`.
typealias GeofenceAuthorizationChangedHandler = @MainActor () -> Void

/// Callback when reconciling against the OS's live conditions found drift. Invoked on the main actor.
typealias GeofenceReconciledHandler = @MainActor () -> Void

/// What the monitor can say about the circle an event was raised against.
///
/// `unknown` (cold wake: a condition this process never recorded) must be taken as current or real
/// crossings are dropped. `expired` means the circle is known to be gone, so the event proves
/// nothing about the fence's geometry now.
enum GeofenceEventCircle: Equatable, Sendable {
    case circle(MonitoredCircle)
    case unknown
    case expired

    /// Maps what the ledger holds onto what a consumer is told.
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

/// The circle the OS was monitoring when it raised an event. A refresh can replace a fence under
/// the same id, so the current fence's circle may be a different one.
struct MonitoredCircle: Equatable, Sendable {
    let center: LocationData
    /// As REGISTERED, so already clamped to `maximumRadius`. Comparing it to a fence's own radius
    /// without clamping that too reads every over-cap fence as changed, forever.
    let radius: Double
    /// The cap the producer clamped against, carried so a consumer can reconstruct what the OS
    /// would hold for a given fence.
    let maximumRadius: Double

    /// Whether this is the circle `geofence` is currently monitored by. Same comparison as
    /// `GeofenceRegionRequest.matchesRegistered`: clamped radius, float round-trip tolerance.
    func matches(_ geofence: Geofence) -> Bool {
        abs(center.latitude - geofence.latitude) < Self.coordinateTolerance
            && abs(center.longitude - geofence.longitude) < Self.coordinateTolerance
            && abs(radius - min(geofence.radius, maximumRadius)) < Self.radiusTolerance
    }

    /// Keep in step with `GeofenceRegionRequest`'s tolerances.
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

/// What `setMonitoredRegions` changed. A desired region missing from `added` was either left
/// registered unchanged or refused by the monitor.
struct GeofenceRegionDiff: Equatable, Sendable {
    let added: Set<String>
    let removed: Set<String>
}

/// Abstracts OS region monitoring: `CLLocationManager` regions (classic) or `CLMonitor` (iOS 18+).
///
/// Business logic decides which regions to monitor; this component only manages the OS
/// registrations and receives their events. Main-actor isolated so the bookkeeping shares one
/// isolation domain with the OS calls and callbacks.
@MainActor
protocol GeofenceRegionMonitoring: AnyObject, Sendable {
    /// Sets the handler called when a geofence transition (enter/exit) occurs.
    func setOnTransition(_ handler: GeofenceTransitionHandler?)

    /// Sets the handler invoked on every authorization status change, in either direction.
    func setOnAuthorizationChanged(_ handler: GeofenceAuthorizationChangedHandler?)

    /// Sets the handler called when reconciling against the OS's live conditions found drift.
    /// Only the CLMonitor path needs it: its synchronous adopt/re-register decision runs off a
    /// cached mirror, so a correction must re-trigger it. Default no-op.
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
    /// Leaving unchanged regions untouched is part of the contract: re-adding a region discards any
    /// crossing the OS has detected but not yet delivered.
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

    /// Region identifiers the OS still holds: app-wide `monitoredRegions` on the classic path, the
    /// SDK's own conditions on CLMonitor. They persist across launch and reboot, so on a fresh
    /// process this can list regions the ownership filter does not yet include.
    var osMonitoredRegionIdentifiers: Set<String> { get }

    /// Re-claims the OS-persisted regions in `identifiers` as owned, on a fresh process where the OS
    /// kept monitoring but the in-memory ownership set was lost. Must not emit events for unchanged
    /// regions. `records` (`GeofenceStorage.getMonitorRegionRecords`) seeds the CLMonitor path's
    /// geometry, which then re-arms each condition; the classic monitor adopts in place and ignores it.
    func adoptExistingRegions(matching identifiers: Set<String>, records: [String: MonitorRegionRecord])

    /// Logs the current authorization tier (background delivery / foreground only / blocked),
    /// deduped so it emits only when the tier changes since the last report.
    func reportPermissionTier()
}

extension GeofenceRegionMonitoring {
    /// Default no-op: only the CLMonitor path reconciles asynchronously against live OS truth.
    func setOnReconciled(_ handler: GeofenceReconciledHandler?) {}
}
