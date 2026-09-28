@testable import CioLocationGeofence
import Foundation

/// `GeofenceVisitMonitor`, without CoreLocation.
///
/// Visits are the one wake source that is not a registered edge, so a drive can carry
/// `visit.reported` stimuli the replay must be able to push in.
@available(iOS 17.0, *)
@MainActor
final class ReplayVisitMonitor: GeofenceVisitMonitoring {
    private(set) var isStarted = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    /// Visits pushed while no handler was bound, so the SDK never saw them. The counterpart of
    /// `FakeConditionMonitor.deliveredWithNoSubscriber`.
    private(set) var deliveredWithNoSubscriber = 0
    private var onVisit: GeofenceVisitHandler?

    func setOnVisit(_ handler: GeofenceVisitHandler?) {
        onVisit = handler
    }

    func start() {
        startCount += 1
        isStarted = true
    }

    func stop() {
        stopCount += 1
        isStarted = false
    }

    /// Pushes a visit in as CoreLocation would.
    ///
    /// Returns false, and counts it in `deliveredWithNoSubscriber`, when no handler is bound. A
    /// handler answering `false` disarms monitoring, so `stop()` is called as the real monitor does.
    @discardableResult
    func deliver(_ visit: GeofenceVisit) -> Bool {
        guard let onVisit else {
            deliveredWithNoSubscriber += 1
            return false
        }
        if onVisit(visit) != true { stop() }
        return true
    }
}
