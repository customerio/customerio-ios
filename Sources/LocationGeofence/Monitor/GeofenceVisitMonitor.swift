import CioInternalCommon
import CoreLocation
import Foundation

/// Visits are reported minutes late, so `coordinate` is a WAKE SIGNAL, never an anchor, and the
/// dates are never a fix timestamp. Anything sizing a radius or judging containment resolves its
/// own fix.
struct GeofenceVisit: Equatable, Sendable {
    let coordinate: LocationData
    let horizontalAccuracy: Double
    /// `.distantPast` when iOS does not know when the device arrived.
    let arrivalDate: Date
    /// `.distantFuture` while the device is still there (an arrival).
    let departureDate: Date

    var isArrival: Bool { departureDate == .distantFuture }
}

/// Returns whether the SDK still wants visits; `false` disarms monitoring.
typealias GeofenceVisitHandler = @MainActor (GeofenceVisit) -> Bool

/// Wakes the SDK when the device settles at or leaves a place: the one wake source that doesn't
/// depend on crossing a registered edge.
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
    /// Separate from `started`: the OS state survives process death.
    private var hasRequestedStop = false

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
        let status = authorizationStatus()
        // Checked BEFORE `started`, so a downgrade can stop a running monitor.
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

    private static func systemAuthorizationStatus(_ manager: CLLocationManager) -> CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return manager.authorizationStatus
        } else {
            return CLLocationManager.authorizationStatus()
        }
    }

    func stop() {
        // Visit monitoring outlives the process, so `started == false` on a fresh instance says
        // nothing about the OS; the first stop always reaches CoreLocation.
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
        // Disarming here keeps this out of `reset()`: at most one wake is spent, and the next
        // bootstrap re-arms.
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
    @MainActor
    static let shared = GeofenceVisitMonitor(logger: DIGraphShared.shared.logger)
}
