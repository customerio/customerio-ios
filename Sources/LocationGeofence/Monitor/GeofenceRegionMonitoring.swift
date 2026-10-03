import CioInternalCommon
import CoreLocation
import Foundation

/// Args: identifier, transition, location, `occurredAt` (OS event date; receipt time on the classic
/// path, fix time for a heal), `locationIsFresh` (a fix obtained for THIS event), the circle the
/// OS was monitoring when it RAISED the event, and `entryObserved`. Invoked on the main actor but
/// not statically isolated.
///
/// `entryObserved`: an ENTER is a crossing since registration, so a visit may date from it. False
/// when the OS is correcting a state the SDK assumed (`CLMonitor` answering a wrong `assuming:`,
/// for a device that may have been inside all along) or for a heal dated when the SDK noticed. The
/// ENTER is delivered either way; only the visit's start differs.
typealias GeofenceTransitionHandler = @Sendable (String, GeofenceTransition, LocationData?, Date, Bool, GeofenceEventCircle, Bool) -> Void

typealias GeofenceAuthorizationChangedHandler = @MainActor () -> Void

typealias GeofenceReconciledHandler = @MainActor () -> Void

/// Called when the OS stops monitoring one condition, or when the monitor's event stream is
/// interrupted globally or location access drops (Always or precise location lost). A nil
/// identifier means continuity is unknown for every active visit.
typealias GeofenceMonitoringInterruptedHandler = @MainActor (String?) -> Void

/// `unknown` (cold wake, never recorded) must be taken as current or real crossings are dropped.
/// `expired`: the circle is known to be gone, so the event proves nothing about current geometry.
enum GeofenceEventCircle: Equatable, Sendable {
    case circle(MonitoredCircle)
    case unknown
    case expired

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

/// A refresh can replace a fence under the same id, so this may not be the current fence's circle.
struct MonitoredCircle: Equatable, Sendable {
    let center: LocationData
    /// As REGISTERED (clamped); unclamped comparison reads every over-cap fence as changed forever.
    let radius: Double
    let maximumRadius: Double

    /// Same comparison as `GeofenceRegionRequest.matchesRegistered`.
    func matches(_ geofence: Geofence) -> Bool {
        abs(center.latitude - geofence.latitude) < Self.coordinateTolerance
            && abs(center.longitude - geofence.longitude) < Self.coordinateTolerance
            && abs(radius - min(geofence.radius, maximumRadius)) < Self.radiusTolerance
    }

    /// Keep in step with `GeofenceRegionRequest`'s tolerances.
    private static let coordinateTolerance = 1e-7
    private static let radiusTolerance = 0.5
}

struct GeofenceRegionRequest: Equatable, Sendable {
    let identifier: String
    let center: LocationData
    let radius: Double
    let transitionTypes: Set<GeofenceTransition>
}

extension GeofenceRegionRequest {
    /// ~1cm. Absorbs float round-tripping through CoreLocation and JSON.
    private static let coordinateTolerance = 1e-7
    private static let radiusTolerance = 0.5

    /// Compares against the clamped radius the OS holds, or an over-cap fence churns forever.
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

/// A desired region missing from `added` was either left unchanged or refused.
struct GeofenceRegionDiff: Equatable, Sendable {
    let added: Set<String>
    let removed: Set<String>
}

/// OS region monitoring: `CLLocationManager` regions (classic) or `CLMonitor` (iOS 18+). Manages
/// registrations only; callers decide which regions to monitor.
@MainActor
protocol GeofenceRegionMonitoring: AnyObject, Sendable {
    func setOnTransition(_ handler: GeofenceTransitionHandler?)

    /// Fires on every status change, in either direction.
    func setOnAuthorizationChanged(_ handler: GeofenceAuthorizationChangedHandler?)

    /// Fires when reconciling against the OS's live conditions found drift. CLMonitor only.
    func setOnReconciled(_ handler: GeofenceReconciledHandler?)

    /// Fires when the OS stops monitoring a condition; nil when continuity is lost for all of them,
    /// including on a drop in `locationAccess`. Never for a repeated or increased authorization.
    func setOnMonitoringInterrupted(_ handler: GeofenceMonitoringInterruptedHandler?)

    /// `radius` is clamped to the OS maximum.
    func startMonitoring(identifier: String, center: LocationData, radius: Double, transitionTypes: Set<GeofenceTransition>)

    func stopMonitoring(identifier: String)

    /// Must leave unchanged regions untouched: re-adding one discards any crossing the OS has
    /// detected but not yet delivered.
    @discardableResult
    func setMonitoredRegions(_ regions: [GeofenceRegionRequest]) -> GeofenceRegionDiff

    func stopMonitoringAll()

    var monitoredRegionIdentifiers: Set<String> { get }

    /// Callers judging whether the device is inside a registered circle must clamp to this too.
    var maximumMonitoringRadius: Double { get }

    /// App-wide `monitoredRegions` on the classic path, the SDK's own conditions on CLMonitor. On a
    /// fresh process this can list regions not yet owned.
    var osMonitoredRegionIdentifiers: Set<String> { get }

    /// Re-claims OS-persisted regions on a fresh process. Must not emit events for unchanged regions.
    /// `records` seeds CLMonitor's geometry; the classic monitor ignores it.
    func adoptExistingRegions(matching identifiers: Set<String>, records: [String: MonitorRegionRecord])

    /// Logs only when the tier changed since the last report.
    func reportPermissionTier()

    /// What the current location permission lets region monitoring observe.
    var locationAccess: GeofenceLocationAccess { get }
}

extension GeofenceRegionMonitoring {
    func setOnReconciled(_ handler: GeofenceReconciledHandler?) {}
    func setOnMonitoringInterrupted(_ handler: GeofenceMonitoringInterruptedHandler?) {}
}
