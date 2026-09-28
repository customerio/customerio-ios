@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import CoreLocation
import Foundation
import SharedTests
#if canImport(UIKit)
import UIKit
#endif

@available(iOS 17.0, *)
@MainActor
extension ReplayHarness {
    /// `identity` (the OS `edate`) wins over `evage`: the OS re-delivers the same event, and rebuilding
    /// the date per copy would make two events out of one.
    func deliverCrossing(
        fence: String,
        transition: GeofenceTransition,
        identity: TimeInterval? = nil,
        evage: TimeInterval = 0
    ) {
        let date = identity.map { epoch.addingTimeInterval($0) }
            ?? clock.givenNow.addingTimeInterval(-evage)
        conditionMonitor.deliver(
            identifier: fence,
            state: transition == .enter ? .satisfied : .unsatisfied,
            at: date
        )
    }

    func deliverMonitorStopped(fence: String) {
        conditionMonitor.deliver(identifier: fence, state: .unmonitored, at: clock.givenNow)
    }

    func setAuthorization(_ status: CLAuthorizationStatus) {
        authority.setAuthorization(status)
        monitor.reportPermissionTier()
    }

    func enterForeground() {
        #if canImport(UIKit)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        #endif
    }

    /// Unlike the real observers, doesn't flush pending rows or re-arm visit monitoring.
    func setIdentified(_ identified: Bool) {
        if identified {
            contextStore.setUserId("replay-user")
            trigger.onIdentified()
        } else {
            contextStore.clearUserId()
            trigger.onReset()
        }
    }
}
