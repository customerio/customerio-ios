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
    /// Delivers a region crossing the way CoreLocation would.
    ///
    /// **No coordinates.** A `CLMonitor` event carries an identifier, a state and a date; the
    /// `lat`/`lon` on a recorded `os.callback` are the SDK's own cache read, answered from the
    /// pull timeline.
    ///
    /// **`identity` wins when the capture has it.** Elsewhere the harness converts recorded
    /// absolutes into durations, but an event's date is the OS's identity for the observation, and
    /// CoreLocation re-delivers the same one more than once. Rebuilding it per copy from `evage`
    /// would hand the SDK two events where the phone saw one.
    ///
    /// - Parameters:
    ///   - identity: the OS's own `edate`, offset onto the scenario's timeline. Older captures have
    ///     none and fall back to the reconstruction.
    ///   - evage: how long the OS held the event before the SDK saw it. Only used for the fallback.
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

    /// CoreLocation giving a condition up — `CLMonitor` reporting `.unmonitored`.
    ///
    /// Delivered through the same event stream as a crossing, as the OS does. The tail carries no
    /// date for these, so the current virtual instant is used; the `.unmonitored` branch does not
    /// read it.
    func deliverMonitorStopped(fence: String) {
        conditionMonitor.deliver(identifier: fence, state: .unmonitored, at: clock.givenNow)
    }

    /// Changes the granted tier, as the OS would when the host app's prompt is answered.
    ///
    /// A real input: `permissionTier` treats `.notDetermined` as blocked, so a drive that starts
    /// before the prompt registers nothing until it is answered.
    func setAuthorization(_ status: CLAuthorizationStatus) {
        authority.setAuthorization(status)
        monitor.reportPermissionTier()
    }

    /// The app coming back to the foreground, by the route the SDK listens on.
    ///
    /// `CLMonitorGeofenceMonitor` observes `willEnterForegroundNotification` to re-arm conditions
    /// locationd may have wedged during suspension; posting it is the only seam for that path.
    func enterForeground() {
        #if canImport(UIKit)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        #endif
    }

    /// Signs a user in or out: updates the stored identity, then calls the trigger as the
    /// `ProfileIdentifiedEvent` / `ResetEvent` observers do. It does not flush pending rows or
    /// re-arm visit monitoring, which those observers also do.
    ///
    /// The id is not in the capture and does not need to be: identity-gated paths only check that
    /// one is present.
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
