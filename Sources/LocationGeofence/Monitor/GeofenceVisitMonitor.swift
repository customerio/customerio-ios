import CioInternalCommon
import CoreLocation
import Foundation

/// What iOS reported about a place the device settled at or left.
///
/// The dates say which edge of the visit this is, never a fix timestamp. A visit is routinely
/// reported minutes late, so `coordinate` is a WAKE SIGNAL and never an anchor: anything sizing a
/// radius or judging containment resolves its own fix.
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
/// Returns whether the SDK still wants visits. `false` disarms monitoring, which is how it stops
/// after sign-out without a teardown hook.
typealias GeofenceVisitHandler = @MainActor (GeofenceVisit) -> Bool

/// Wakes the SDK when the device settles at or leaves a place.
///
/// The one wake source that does not depend on crossing a registered edge. A device that enters a
/// polygon's covering circle while outside the polygon, then walks in, gets no region callback.
/// For a small venue most of the covering circle lies outside the polygon, so this is the common
/// case.
///
/// Needs no background-location mode or standing location request, only the Always authorization
/// region monitoring already requires.
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
        // Always, not whenInUse: delivery to a suspended or terminated app is the point.
        // Read once so the guard and the log agree.
        let status = authorizationStatus()
        // Checked BEFORE `started`: a downgrade from Always changes only the status, and every
        // rewire routes through here, so it must be able to stop a running monitor.
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

    /// The instance property is iOS 14+; this package supports iOS 13.
    private static func systemAuthorizationStatus(_ manager: CLLocationManager) -> CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return manager.authorizationStatus
        } else {
            return CLLocationManager.authorizationStatus()
        }
    }

    func stop() {
        // Visit monitoring outlives the process, so on a fresh instance `started == false` says
        // nothing about the OS; the first stop always reaches CoreLocation, later no-op ones don't.
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
        // `false` means nothing to act for (sign-out, kill switch). Disarming here keeps this out
        // of `reset()`: at most one wake is spent, and the next bootstrap re-arms.
        if onVisit?(reported) != true { stop() }
    }
}

// MARK: - DI

extension DIGraphShared {
    /// Hand-written and `@MainActor` for the same reason as `geofenceMonitor`.
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
