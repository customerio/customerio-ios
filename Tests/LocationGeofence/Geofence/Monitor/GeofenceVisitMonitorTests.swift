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

/// `CLVisit` has no public initializer, so the delegate callback is only reachable through a
/// subclass that overrides the four properties the monitor reads.
private final class FakeVisit: CLVisit {
    private let coord: CLLocationCoordinate2D
    private let arrival: Date
    private let departure: Date

    init(arrivalDate: Date = Date(), departureDate: Date = .distantFuture) {
        self.coord = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
        self.arrival = arrivalDate
        self.departure = departureDate
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("unused")
    }

    override var coordinate: CLLocationCoordinate2D { coord }
    override var arrivalDate: Date { arrival }
    override var departureDate: Date { departure }
    override var horizontalAccuracy: CLLocationAccuracy { 30 }
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
        // Asserts the skip is RECORDED, because that log is the only thing unique to this branch.
        // The disarm below is real but not distinctive — the first `stop()` on any fresh instance
        // reaches CoreLocation whatever brought us there.
        let f = Fixture()
        f.status.value = .denied
        f.monitor.start()

        #expect(f.manager.startCount == 0)
        #expect(f.skippedLogCount == 1)
        // Pinned, not incidental: a fresh instance under denied permission pushes one disarm, so
        // a previous process's visit service does not outlive the permission that backed it.
        #expect(f.manager.stopCount == 1)
    }

    /// Visit monitoring outlives the process. On a relaunch this instance has never armed, but
    /// the OS service from the previous session is still running — so a disarm before any arm
    /// must still reach CoreLocation, or a kill-switched account keeps waking.
    @Test
    func stop_givenARecreatedMonitorThatNeverStarted_expectCoreLocationStopped() {
        let f = Fixture()

        f.monitor.stop()

        #expect(f.manager.stopCount == 1)
    }

    /// The suppression still works after that first one, so a repeated disarm is not chatty.
    @Test
    func stop_givenRepeatedStopsWithoutStarting_expectOnlyTheFirstReachesCoreLocation() {
        let f = Fixture()

        f.monitor.stop()
        f.monitor.stop()
        f.monitor.stop()

        #expect(f.manager.stopCount == 1)
    }

    // MARK: - Delivery

    /// The handler's answer IS the disarm decision — that is how sign-out stops the monitor
    /// without a teardown hook. Nothing else asserts the monitor acts on it: the binder tests
    /// check what the handler returns, not what the monitor does with it.
    @Test
    func didVisit_givenTheHandlerRefuses_expectDisarmed() {
        let f = Fixture()
        f.monitor.start()
        f.monitor.setOnVisit { _ in false }

        f.monitor.locationManager(f.manager, didVisit: FakeVisit())

        #expect(f.manager.stopCount == 1)
    }

    @Test
    func didVisit_givenTheHandlerAccepts_expectStillArmed() {
        let f = Fixture()
        f.monitor.start()
        f.monitor.setOnVisit { _ in true }

        f.monitor.locationManager(f.manager, didVisit: FakeVisit())

        #expect(f.manager.stopCount == 0)
    }

    /// Both edges, in one test on purpose. A departure must reach the handler as well as an
    /// arrival — the binder re-judges membership on either. Asserting only the departure passes
    /// against a constant `isArrival` and against the two dates being carried across swapped,
    /// because neither date on a departure is `.distantFuture`; the arrival case is what
    /// separates them.
    @Test
    func didVisit_givenEitherEdge_expectTheEdgeReportedAsGiven() {
        let f = Fixture()
        f.monitor.start()
        var seen: [Bool] = []
        f.monitor.setOnVisit { visit in
            seen.append(visit.isArrival)
            return true
        }

        f.monitor.locationManager(f.manager, didVisit: FakeVisit())
        f.monitor.locationManager(
            f.manager, didVisit: FakeVisit(arrivalDate: Date().addingTimeInterval(-600), departureDate: Date())
        )

        #expect(seen == [true, false])
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
