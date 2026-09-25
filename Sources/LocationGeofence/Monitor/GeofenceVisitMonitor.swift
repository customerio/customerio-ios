import CioInternalCommon
import CoreLocation
import Foundation

/// What iOS reported about a place the device settled at or left.
///
/// Deliberately not a `CLVisit`. The coordinate is the only part worth carrying, and the dates are
/// here to say which edge of the visit this is — not to be used as a fix timestamp. A visit is
/// routinely reported minutes after the fact (16 minutes, measured in the field), so `coordinate`
/// is a WAKE SIGNAL and never an anchor. Anything sizing a radius or judging containment resolves
/// its own fix.
struct GeofenceVisit: Equatable, Sendable {
    let coordinate: LocationData
    let horizontalAccuracy: Double
    /// `.distantPast` when iOS does not know when the device arrived.
    let arrivalDate: Date
    /// `.distantFuture` while the device is still there, which is what makes this an arrival.
    let departureDate: Date

    var isArrival: Bool { departureDate == .distantFuture }
}

/// Invoked on the main actor — same isolation domain as `CLLocationManagerDelegate`.
///
/// Returns whether the SDK still wants visits. `false` disarms monitoring, which is how this
/// stops itself after sign-out without a teardown hook: see `GeofenceVisitMonitor`.
typealias GeofenceVisitHandler = @MainActor (GeofenceVisit) -> Bool

/// Wakes the SDK when the device settles at or leaves a place.
///
/// The one wake source we have that does not depend on crossing a registered edge. Region
/// monitoring is edge-triggered and there is no "still inside" callback, so a device that enters a
/// polygon's covering circle while outside the polygon, roams, then walks in produces nothing —
/// measured at 11 min 33 s of silence, with the arrival landing only when the device left again.
/// At the smallest venue in the live set, 86% of the covering circle carries no containment
/// information, so this is the common case rather than an edge.
///
/// Costs no background-location mode and no standing location request, and needs the same Always
/// authorization region monitoring already requires. That is what makes it the cheap half of the
/// gap.
@MainActor
protocol GeofenceVisitMonitoring: AnyObject {
    /// Wire before `start()` so a cold-wake visit has somewhere to land.
    func setOnVisit(_ handler: GeofenceVisitHandler?)
    /// Idempotent. A caller need not check authorization; the implementation does.
    func start()
    func stop()
}

@MainActor
final class GeofenceVisitMonitor: NSObject, GeofenceVisitMonitoring, @preconcurrency CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private let logger: Logger
    private let authorizationStatus: @MainActor () -> CLAuthorizationStatus
    private var onVisit: GeofenceVisitHandler?
    private var started = false
    /// Whether this instance has pushed a stop to CoreLocation. Separate from `started` because
    /// the OS state survives process death; see `stop()`.
    private var hasRequestedStop = false

    /// - Parameter authorizationStatus: overridable only so a test can drive a permission change.
    ///   The real status is the process's, and no unit test can move it.
    init(
        logger: Logger,
        manager: CLLocationManager? = nil,
        authorizationStatus: (@MainActor () -> CLAuthorizationStatus)? = nil
    ) {
        let manager = manager ?? CLLocationManager()
        self.logger = logger
        self.manager = manager
        self.authorizationStatus = authorizationStatus ?? { Self.systemAuthorizationStatus(manager) }
        super.init()
        self.manager.delegate = self
    }

    func setOnVisit(_ handler: GeofenceVisitHandler?) {
        onVisit = handler
    }

    func start() {
        // Always, not whenInUse: visit delivery to a suspended or terminated app is the entire
        // point, and `whenInUse` would report only while the app is already awake — which is the
        // case that needs no help.
        // Read once: the guard and the log must report the same answer, and the status can change
        // between two reads.
        let status = authorizationStatus()
        // Checked BEFORE `started`, not after: `started` records the last request we made, the
        // status is what the OS will honour, and a downgrade from Always moves only the second.
        // Every rewire routes through here, so an early return on our own bookkeeping would leave
        // the monitor running against a permission that no longer backs it.
        guard status == .authorizedAlways else {
            logger.geofenceVisitMonitoringSkipped(status: status.rawValue)
            stop()
            return
        }
        guard !started else { return }
        started = true
        manager.startMonitoringVisits()
        logger.geofenceVisitMonitoringStarted()
    }

    /// The availability split mirrors `CoreLocationGeofenceMonitor` — the instance property is
    /// iOS 14+ and this package still supports iOS 13.
    private static func systemAuthorizationStatus(_ manager: CLLocationManager) -> CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return manager.authorizationStatus
        } else {
            return CLLocationManager.authorizationStatus()
        }
    }

    func stop() {
        // `started` describes THIS instance, and visit monitoring outlives the process: the OS
        // keeps delivering to a relaunched app that never re-armed. So on a fresh instance
        // `started == false` says nothing about whether the service is running, and the first
        // disarm has to reach CoreLocation regardless — a cold launch that refreshes a
        // kill-switched config before arming would otherwise leave the previous session's visit
        // service alive with nothing to turn it off. Later no-op stops are still suppressed.
        guard started || !hasRequestedStop else { return }
        started = false
        hasRequestedStop = true
        manager.stopMonitoringVisits()
        logger.geofenceVisitMonitoringStopped()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_: CLLocationManager, didVisit visit: CLVisit) {
        let reported = GeofenceVisit(
            coordinate: LocationData(
                latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude
            ),
            horizontalAccuracy: visit.horizontalAccuracy,
            arrivalDate: visit.arrivalDate,
            departureDate: visit.departureDate
        )
        logger.geofenceVisitReported(
            coordinate: reported.coordinate,
            isArrival: reported.isArrival,
            horizontalAccuracy: reported.horizontalAccuracy,
            reportDelay: reported.isArrival
                ? -reported.arrivalDate.timeIntervalSinceNow
                : -reported.departureDate.timeIntervalSinceNow
        )
        // A handler answering `false` means the SDK has nothing registered to act for — sign-out,
        // or a kill-switched account. Disarming here rather than from a teardown hook keeps this
        // out of `reset()`: at most one wake is spent discovering there is no work, and the next
        // bootstrap re-arms.
        if onVisit?(reported) != true { stop() }
    }
}

// MARK: - DI

extension DIGraphShared {
    /// Hand-written + `@MainActor`-isolated for the same reason as `geofenceMonitor`: it owns a
    /// `CLLocationManager`. Override-check mirrors the generated accessors so tests can substitute
    /// via `di.override(value:forType:)`.
    @MainActor
    var geofenceVisitMonitor: GeofenceVisitMonitoring {
        let overridden: GeofenceVisitMonitoring? = getOverriddenInstance()
        return overridden ?? GeofenceVisitMonitor.shared
    }
}

extension GeofenceVisitMonitor {
    /// Process-wide singleton so one `CLLocationManager` serves visit monitoring, matching
    /// `PolygonMembershipResolver.shared`.
    @MainActor
    static let shared = GeofenceVisitMonitor(logger: DIGraphShared.shared.logger)
}
