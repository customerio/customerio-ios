@testable import CioLocationGeofence
import Foundation

/// `GeofenceVisitMonitor`, without CoreLocation.
///
/// Visits are the one wake source that is not a registered edge, so a drive recorded on a build
/// that monitors them carries `visit.reported` stimuli the replay must be able to push in. The SDK
/// already publishes the seam — `DIGraphShared.geofenceVisitMonitor` checks for an override the
/// same way `geofenceMonitor` does — so nothing in production changes to make this substitutable.
@available(iOS 17.0, *)
@MainActor
final class ReplayVisitMonitor: GeofenceVisitMonitoring {
    private(set) var isStarted = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    /// A visit pushed while nothing was listening. Visit monitoring is armed asynchronously off
    /// `identify`, so a drive whose first visit lands before that arming leaves the SDK unwoken —
    /// the same hazard `FakeConditionMonitor.deliveredWithNoSubscriber` guards for OS callbacks.
    /// A run that reports this handled while the SDK never saw the visit is asserting nothing.
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
    /// Returns false when nothing is listening, which the runner reports rather than swallows: a
    /// drive whose visits land before the SDK subscribed is a finding about the wiring, not a
    /// stimulus to drop. Mirrors the handler contract — answering `false` disarms monitoring, so
    /// `stop()` is called here exactly as the real monitor calls it.
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
