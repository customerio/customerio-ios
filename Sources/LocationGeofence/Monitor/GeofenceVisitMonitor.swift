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
    private var onVisit: GeofenceVisitHandler?
    private var started = false

    init(logger: Logger, manager: CLLocationManager? = nil) {
        self.logger = logger
        self.manager = manager ?? CLLocationManager()
        super.init()
        self.manager.delegate = self
    }

    func setOnVisit(_ handler: GeofenceVisitHandler?) {
        onVisit = handler
    }

    func start() {
        guard !started else { return }
        // Always, not whenInUse: visit delivery to a suspended or terminated app is the entire
        // point, and `whenInUse` would report only while the app is already awake — which is the
        // case that needs no help.
        guard manager.authorizationStatus == .authorizedAlways else {
            logger.geofenceVisitMonitoringSkipped(status: manager.authorizationStatus.rawValue)
            return
        }
        started = true
        manager.startMonitoringVisits()
        logger.geofenceVisitMonitoringStarted()
    }

    func stop() {
        guard started else { return }
        started = false
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
