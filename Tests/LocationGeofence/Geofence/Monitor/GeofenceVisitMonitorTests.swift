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

@MainActor
@Suite("GeofenceVisitMonitor arming")
struct GeofenceVisitMonitorTests {
    @MainActor
    private final class Fixture {
        let manager = RecordingLocationManager()
        var status: CLAuthorizationStatus = .authorizedAlways
        lazy var monitor = GeofenceVisitMonitor(
            logger: LoggerMock(),
            manager: manager,
            authorizationStatus: { [unowned self] in status }
        )
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
        f.status = .authorizedWhenInUse
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
    func start_givenNeverAuthorized_expectNothingStopped() {
        let f = Fixture()
        f.status = .denied
        f.monitor.start()

        #expect(f.manager.startCount == 0)
        #expect(f.manager.stopCount == 0)
    }

    @Test
    func start_givenAlwaysRestoredAfterDowngrade_expectVisitsRequestedAgain() {
        let f = Fixture()
        f.monitor.start()
        f.status = .denied
        f.monitor.start()
        f.status = .authorizedAlways
        f.monitor.start()

        #expect(f.manager.startCount == 2)
    }
}
