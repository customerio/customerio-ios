@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import CoreLocation
import Foundation
import SharedTests
import Testing

/// The fences the durable EXIT tests measure: one circle, one polygon.
enum DurableExitFences {
    /// 150 m around (1, 2), dwell after 600 s.
    static let circle = Geofence(
        id: "circle", latitude: 1, longitude: 2, radius: 150, name: "circle",
        transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1),
        dwellThresholdSeconds: 600
    )
    /// About 180 m square around (5, 6), in a 300 m covering circle.
    static let polygon = Geofence(
        id: "polygon", latitude: 5, longitude: 6, radius: 300, name: "polygon",
        transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1),
        vertices: [
            LocationData(latitude: 4.9992, longitude: 5.9992),
            LocationData(latitude: 4.9992, longitude: 6.0008),
            LocationData(latitude: 5.0008, longitude: 6.0008),
            LocationData(latitude: 5.0008, longitude: 5.9992)
        ],
        dwellThresholdSeconds: 600
    )
}

/// What survives a process: the files, the `CLMonitor` mirror in user defaults, and the device's
/// clocks.
@MainActor
final class DurableExitDevice {
    let contextDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let geofenceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaultsSuite = "io.customer.test.geofence.\(UUID().uuidString)"
    /// Booted `uptime` seconds before `wall`.
    let clock = ManualGeofenceClock(
        wall: Date(timeIntervalSince1970: 1789215000), uptime: 10000,
        boot: GeofenceBootIdentity(bootTime: 1789215000 - 10000, processToken: nil)
    )
    let dateUtil = DateUtilStub()
    var seeded = false
    /// Fresh fixes the dwell coordinator asked for.
    var fixesRequested = 0

    init() {
        dateUtil.givenNow = clock.wall
    }

    func advance(_ seconds: TimeInterval) {
        clock.advance(seconds)
        dateUtil.givenNow = clock.wall
    }

    func stepWall(_ seconds: TimeInterval) {
        clock.stepWall(seconds)
        dateUtil.givenNow = clock.wall
    }

    /// A 10 m fix taken now, `latitudeOffset` degrees north of `geofence`'s centre.
    func fix(at geofence: Geofence = DurableExitFences.circle, latitudeOffset: Double = 0) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: geofence.latitude + latitudeOffset, longitude: geofence.longitude),
            altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: clock.wall
        )
    }
}

/// What a process builds from the device's files: the real context store, geofence store, outbox,
/// event tracker, dwell coordinator, polygon resolver, and `CLMonitor` wrapper (only CoreLocation
/// is faked), all on the device's clock. It starts as a process that dies the moment `CLMonitor`
/// hands it an event: the event is recorded, and nothing routes it. `route()` binds the binder.
@available(iOS 17.0, *)
@MainActor
final class DurableExitProcess {
    let contextStore: BackgroundDeliveryContextStore
    let storage: GeofenceStorage
    let outbox: PendingGeofenceMetricStore
    let dwell: GeofenceDwellCoordinator
    let resolver: PolygonMembershipResolver
    let os = FakeConditionMonitor()
    let authority = FakeLocationAuthority()
    let monitor: CLMonitorGeofenceMonitor
    private let device: DurableExitDevice
    private let sync = GeofenceSyncCoordinatorMock()

    init(device: DurableExitDevice) async {
        self.device = device
        self.contextStore = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: device.contextDirectory)
        self.storage = GeofenceStorage(directoryURL: device.geofenceDirectory, dateUtil: device.dateUtil)
        if !device.seeded {
            device.seeded = true
            contextStore.setUserId("user-a")
            // A key, so a flush sends rows over HTTP, which fails: every row stays in the outbox.
            contextStore.setCdpApiKey("test-key")
            await storage.setCachedGeofences([DurableExitFences.circle, DurableExitFences.polygon])
            await storage.recordRegistration(
                center: LocationData(latitude: 1, longitude: 2),
                businessIds: [DurableExitFences.circle.id, DurableExitFences.polygon.id]
            )
        }
        self.outbox = PendingGeofenceMetricStore(logger: LoggerMock(), directoryURL: device.geofenceDirectory.appendingPathComponent("outbox"))
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.transport)) }
        let tracker = GeofenceEventTracker(
            storage: storage, pendingStore: outbox, deliveryTracker: delivery, contextStore: contextStore,
            eventBusHandler: EventBusHandlerMock(), dateUtil: device.dateUtil, logger: LoggerMock()
        )
        self.dwell = GeofenceDwellCoordinator(
            storage: storage, transitionEmitter: tracker, contextStore: contextStore, logger: LoggerMock(),
            notificationCenter: NotificationCenter(), freshFixProvider: { [weak device] in
                device?.fixesRequested += 1
                return device?.fix()
            },
            evidenceRetryDelay: 3600, clock: device.clock, identityTracker: GeofenceIdentityTracker(contextStore: contextStore)
        )
        self.resolver = PolygonMembershipResolver(
            storage: storage, transitionEmitter: tracker, logger: LoggerMock(), contextStore: contextStore,
            dateUtil: device.dateUtil, notificationCenter: NotificationCenter(), dwellCoordinator: dwell
        )
        let os = os
        self.monitor = CLMonitorGeofenceMonitor(
            logger: LoggerMock(), storage: storage,
            userDefaults: UserDefaults(suiteName: device.defaultsSuite) ?? .standard,
            dateUtil: device.dateUtil, authority: authority, makeConditionMonitor: { _ in os }, clock: device.clock
        )
        monitor.setOnTransition { _, _, _, _, _, _, _ in }
        sync.refreshReturnValue = .success(())
        sync.handleMovementReturnValue = .success(())
        _ = await settleOnMain { os.hasSubscriber }
    }

    /// From here on, events reach the binder, the resolver and the coordinator.
    func route() {
        GeofenceMonitorBinder.bind(monitor: monitor, resolver: resolver, coordinator: sync, logger: LoggerMock(), dwellCoordinator: dwell)
    }

    /// From here on, the process dies the moment `CLMonitor` hands it an event: recorded, never routed.
    func dieOnNextEvent() {
        monitor.setOnTransition { _, _, _, _, _, _, _ in }
    }

    /// Registers `geofence`'s circle with `CLMonitor`, seen from `fix`: inside or outside it is an
    /// observed state; with none, the state is assumed outside. Then lets the contradiction gate's
    /// replay window pass.
    func register(_ geofence: Geofence = DurableExitFences.circle, seenAt fix: CLLocation? = nil) async {
        authority.answerCachedLocation = { fix }
        monitor.startMonitoring(
            identifier: geofence.id, center: LocationData(latitude: geofence.latitude, longitude: geofence.longitude),
            radius: geofence.radius, transitionTypes: [.enter, .exit]
        )
        _ = await settleOnMain { self.os.held[geofence.id] != nil }
        for _ in 0 ..< 200 where await storage.getMonitorRegionRecords()[geofence.id] == nil {
            try? await Task.sleep(nanoseconds: 10000000)
        }
        authority.answerCachedLocation = nil
        device.advance(20)
    }

    /// The OS reports `state` for `identifier`, dated `date` (now by default). Returns once
    /// `CLMonitor` has recorded it, and whatever routing it triggered has run.
    func deliver(_ state: GeofenceConditionState, to identifier: String = DurableExitFences.circle.id, at date: Date? = nil) async {
        let date = date ?? device.clock.wall
        os.deliver(identifier: identifier, state: state, at: date)
        for _ in 0 ..< 200 where await storage.getMonitorRegionRecords()[identifier]?.lastEventDate != date {
            try? await Task.sleep(nanoseconds: 10000000)
        }
        await settleQuietly(0.3)
    }

    func visit(_ geofence: Geofence = DurableExitFences.circle) async -> GeofenceDwellVisit? {
        await storage.getDwellVisit(geofenceId: geofence.id)
    }

    func dwellRows() async -> [PendingGeofenceMetric] {
        await outbox.rows().filter { $0.transition == .dwell }
    }

    /// A fresh fix wholly inside the circle, applied as the visit's deadline evidence and directly
    /// as inside evidence, so both the evidence request and the reservation are exercised.
    func freshInsideEvidence() async {
        await dwell.requestQualifyingEvidence(geofenceId: DurableExitFences.circle.id)
        await dwell.recordInsideEvidence(
            geofence: DurableExitFences.circle, at: device.clock.wall, source: "location_evidence"
        )
    }

    /// The process dies: nothing it scheduled runs again.
    func end() {
        dwell.cancelEvidence(for: DurableExitFences.circle.id)
        dwell.cancelEvidence(for: DurableExitFences.polygon.id)
    }
}
