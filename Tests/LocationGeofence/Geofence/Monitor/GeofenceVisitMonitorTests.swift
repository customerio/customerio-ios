@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
import CoreLocation
import Foundation
import Testing

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

private final class StatusBox {
    var value: CLAuthorizationStatus = .authorizedAlways
}

/// `CLVisit` has no public initializer.
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

        /// Matches prose, not the `state=skipped` tail: the tail is empty with diagnostics off.
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
        // The authorization-change rewire calls `start()` again.
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
        let f = Fixture()
        f.status.value = .denied
        f.monitor.start()

        #expect(f.manager.startCount == 0)
        #expect(f.skippedLogCount == 1)
        // A fresh instance under denied permission disarms once, in case a previous process armed
        // visits.
        #expect(f.manager.stopCount == 1)
    }

    /// Visit monitoring outlives the process, so a disarm before any arm must still reach CoreLocation.
    @Test
    func stop_givenARecreatedMonitorThatNeverStarted_expectCoreLocationStopped() {
        let f = Fixture()

        f.monitor.stop()

        #expect(f.manager.stopCount == 1)
    }

    @Test
    func stop_givenRepeatedStopsWithoutStarting_expectOnlyTheFirstReachesCoreLocation() {
        let f = Fixture()

        f.monitor.stop()
        f.monitor.stop()
        f.monitor.stop()

        #expect(f.manager.stopCount == 1)
    }

    // MARK: - Delivery

    /// The handler's answer is the disarm decision; sign-out relies on it.
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

    /// Both edges: a departure alone also passes with a constant `isArrival` or swapped dates.
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
