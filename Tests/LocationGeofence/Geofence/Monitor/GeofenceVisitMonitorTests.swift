@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
import CoreLocation
import Foundation
import Testing

/// Records what the monitor asked CoreLocation to do. The real calls are no-ops in a test process,
/// so the override is the only place the request is observable.
private final class RecordingLocationManager: CLLocationManager {
    var startCount = 0
    var stopCount = 0

    override func startMonitoringVisits() {
        startCount += 1
    }

    override func stopMonitoringVisits() {
        stopCount += 1
    }
}

/// Holds the status the injected reader returns, so the closure captures this rather than the
/// fixture — no `self` capture, and no `unowned`.
private final class StatusBox {
    var value: CLAuthorizationStatus = .authorizedAlways
}

@MainActor
@Suite("GeofenceVisitMonitor arming")
struct GeofenceVisitMonitorTests {
    @MainActor
    private final class Fixture {
        let manager = RecordingLocationManager()
        let logger = LoggerMock()
        let status = StatusBox()
        lazy var monitor = GeofenceVisitMonitor(
            logger: logger,
            manager: manager,
            authorizationStatus: { [status] in status.value }
        )

        /// Matched on PROSE, not on the `state=skipped` tail: `GeofenceLog.tail` returns "" unless
        /// diagnostics are enabled, and this suite does not touch that process-global gate.
        var skippedLogCount: Int {
            logger.infoReceivedInvocations
                .filter { $0.message.contains("Visit monitoring needs Always authorization") }
                .count
        }
    }

    @Test
    func start_givenAlways_expectVisitsRequested() {
        let f = Fixture()
        f.monitor.start()

        #expect(f.manager.startCount == 1)
    }

    @Test
    func start_givenAlwaysDowngradedAfterArming_expectVisitsStopped() {
        let f = Fixture()
        f.monitor.start()
        // What the authorization-changed rewire does: the same `start()`, now under a permission
        // that no longer backs it.
        f.status.value = .authorizedWhenInUse
        f.monitor.start()

        #expect(f.manager.stopCount == 1)
    }

    @Test
    func start_givenStillAlways_expectNoSecondRequest() {
        let f = Fixture()
        f.monitor.start()
        f.monitor.start()

        #expect(f.manager.startCount == 1)
        #expect(f.manager.stopCount == 0)
    }

    @Test
    func start_givenNeverAuthorized_expectSkipRecorded() {
        // Asserts the skip is RECORDED, not that `stopMonitoringVisits` went uncalled: production
        // does reach `stop()` on this branch and it is swallowed by `stop()`'s own `guard started`,
        // so a stop-count assertion would be measuring that unrelated guard, not this branch.
        let f = Fixture()
        f.status.value = .denied
        f.monitor.start()

        #expect(f.manager.startCount == 0)
        #expect(f.skippedLogCount == 1)
    }

    @Test
    func start_givenAlwaysRestoredAfterDowngrade_expectVisitsRequestedAgain() {
        let f = Fixture()
        f.monitor.start()
        f.status.value = .denied
        f.monitor.start()
        f.status.value = .authorizedAlways
        f.monitor.start()

        #expect(f.manager.startCount == 2)
    }
}
