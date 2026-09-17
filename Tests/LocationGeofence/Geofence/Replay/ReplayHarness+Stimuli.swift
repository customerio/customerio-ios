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
    /// **No coordinates.** A `CLMonitor` event carries an identifier, a state and a date and
    /// nothing else; the position attached to a crossing is one the SDK goes and reads for itself.
    /// The `lat`/`lon` on a recorded `os.callback` are that read, not something the OS handed over,
    /// so they belong to the cache the drive also recorded — and passing them in here would hand
    /// the SDK an answer it is supposed to fetch.
    ///
    /// **`identity` wins when the capture has it, and R10 does not apply to it.** Everywhere else
    /// the harness converts a recorded absolute into a duration, because the recording's clock and
    /// the replay's clock are different clocks. An event's date is the exception: it is not a
    /// measurement of elapsed time, it is the OS's *identity* for the observation, and CoreLocation
    /// re-delivers the same one more than once. Rebuilding it per copy from `evage` hands the SDK
    /// two different events where the phone saw one, which is exactly what made the re-delivery
    /// check unreachable in replay.
    ///
    /// - Parameters:
    ///   - identity: the OS's own `edate`, offset onto the scenario's timeline. Captures made
    ///     before that field shipped have none, and fall back to the reconstruction.
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
    /// Delivered through the same event stream as a crossing, because that is the door the OS uses:
    /// the wrapper's `.unmonitored` branch runs off `process(event:)` like everything else, and a
    /// harness that reached around it would be testing its own bookkeeping.
    ///
    /// No date is recorded for these — the tail carries only `id` — so the virtual clock's current
    /// instant is the honest stamp. Nothing downstream reads it: the branch drops the condition's
    /// baseline and stages a re-register, neither of which weighs the event's age.
    func deliverMonitorStopped(fence: String) {
        conditionMonitor.deliver(identifier: fence, state: .unmonitored, at: clock.givenNow)
    }

    /// Changes the granted tier, as the OS would when the host app's prompt is answered.
    ///
    /// A real input, not a no-op: `permissionTier` calls `.notDetermined` blocked, so a drive that
    /// starts before the prompt registers nothing until it is answered — which is exactly what the
    /// 2026-09-10 iPhone drive recorded, sitting unregistered for the first 1.9 seconds.
    func setAuthorization(_ status: CLAuthorizationStatus) {
        authority.setAuthorization(status)
        monitor.reportPermissionTier()
    }

    /// The app coming back to the foreground, by the route the SDK listens on.
    ///
    /// `CLMonitorGeofenceMonitor` observes `willEnterForegroundNotification` to re-arm conditions
    /// that locationd may have wedged while the process was suspended. Posting the real
    /// notification is what makes that path reachable; there is no other seam for it.
    func enterForeground() {
        #if canImport(UIKit)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        #endif
    }

    /// Signs a user in or out, doing exactly what `ProfileIdentifiedEvent` / `ResetEvent` do in
    /// production: update the stored identity, then let the trigger decide what follows.
    ///
    /// The id is not in the capture and does not need to be: every identity-gated path checks only
    /// that one is present.
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
