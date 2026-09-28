@testable import CioLocationGeofence
import Foundation

@available(iOS 17.0, *)
@MainActor
final class ReplayVisitMonitor: GeofenceVisitMonitoring {
    private(set) var isStarted = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
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

    /// A handler answering `false` disarms monitoring, so `stop()` is called as the real monitor does.
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
