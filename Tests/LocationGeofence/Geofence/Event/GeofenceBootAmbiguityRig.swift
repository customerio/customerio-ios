@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import CoreLocation
import Foundation
import SharedTests
import Testing

/// What survives a process: the files, and the device's clocks. The boot identity changes only
/// between processes, as `SystemGeofenceClock` reads it once per process.
@MainActor
final class BootAmbiguityDevice {
    /// About 180 m square around (5, 6), well inside its 300 m covering circle.
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

    let contextDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let geofenceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    /// Booted `uptime` seconds before `wall`, so the boot time reads as the kernel's would. The
    /// wall clock starts a day ahead of the real time. The polygon membership store clamps its
    /// stamps to `Date()`, which on a device is the stepped clock itself, and discards a stamp left
    /// ahead of it by a backward step. A day ahead, every stamp clamps to the real time instead, so
    /// they stay in processing order whichever way the scripted clock steps — what the device's
    /// discard amounts to.
    let clock: ManualGeofenceClock = {
        let wall = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down) + 86400)
        return ManualGeofenceClock(
            wall: wall, uptime: 10000,
            boot: GeofenceBootIdentity(bootTime: wall.timeIntervalSince1970 - 10000, processToken: nil)
        )
    }()

    let dateUtil = DateUtilStub()
    /// Where every fresh fix is taken: degrees of latitude north of the polygon's centre.
    var fixOffset: Double = 0
    var seeded = false

    init() {
        dateUtil.givenNow = clock.wall
    }

    func advance(_ seconds: TimeInterval) {
        clock.advance(seconds)
        dateUtil.givenNow = clock.wall
    }

    /// The wall clock is set by `seconds`. The process running now keeps the boot identity it read
    /// at launch; the kernel's boot time moves with the wall clock, so the next process reads it
    /// `seconds` away (XNU `clock_set_calendar_microtime`).
    func stepWall(_ seconds: TimeInterval) {
        clock.stepWall(seconds)
        dateUtil.givenNow = clock.wall
    }

    /// The boot identity the next process reads after `stepWall(seconds)`.
    func rereadBootAfterStep(_ seconds: TimeInterval) {
        clock.boot = GeofenceBootIdentity(bootTime: (clock.boot.bootTime ?? 0) + seconds, processToken: nil)
    }

    func stepWallAndBoot(_ seconds: TimeInterval) {
        stepWall(seconds)
        rereadBootAfterStep(seconds)
    }

    /// A fix taken now at `fixOffset`.
    func fix() -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: Self.polygon.latitude + fixOffset, longitude: Self.polygon.longitude),
            altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: clock.wall
        )
    }
}

/// What a process builds at launch from the device's files: the real context store, identity
/// tracker, geofence store, outbox, event tracker, dwell coordinator and polygon resolver.
@MainActor
final class BootAmbiguityProcess {
    let contextStore: BackgroundDeliveryContextStore
    let storage: GeofenceStorage
    let outbox: PendingGeofenceMetricStore
    let tracker: GeofenceEventTracker
    let dwell: GeofenceDwellCoordinator
    let resolver: PolygonMembershipResolver
    /// The bound binder's follow-up target: a routed polygon ENTER whose evaluation returned a fix
    /// ends with `handleMovement`, then `refresh`.
    let sync = GeofenceSyncCoordinatorMock()

    init(device: BootAmbiguityDevice) async {
        let polygon = BootAmbiguityDevice.polygon
        self.contextStore = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: device.contextDirectory)
        self.storage = GeofenceStorage(directoryURL: device.geofenceDirectory, dateUtil: device.dateUtil)
        if !device.seeded {
            device.seeded = true
            contextStore.setUserId("user-a")
            // A key, so a flush sends rows over HTTP, which fails: every row stays in the outbox.
            contextStore.setCdpApiKey("test-key")
            await storage.setCachedGeofences([polygon])
            await storage.recordRegistration(center: LocationData(latitude: 5, longitude: 6), businessIds: [polygon.id])
        }
        self.outbox = PendingGeofenceMetricStore(logger: LoggerMock(), directoryURL: device.geofenceDirectory.appendingPathComponent("outbox"))
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.transport)) }
        self.tracker = GeofenceEventTracker(
            storage: storage, pendingStore: outbox, deliveryTracker: delivery, contextStore: contextStore,
            eventBusHandler: EventBusHandlerMock(), dateUtil: device.dateUtil, logger: LoggerMock()
        )
        self.dwell = GeofenceDwellCoordinator(
            storage: storage, transitionEmitter: tracker, contextStore: contextStore, logger: LoggerMock(),
            notificationCenter: NotificationCenter(), freshFixProvider: { nil }, evidenceRetryDelay: 3600,
            clock: device.clock, identityTracker: GeofenceIdentityTracker(contextStore: contextStore)
        )
        let fixResolver = MovementFixResolver(logger: LoggerMock(), dateUtil: device.dateUtil)
        fixResolver.systemCachedFix = { nil }
        fixResolver.requestFreshFix = { [weak device, weak fixResolver] in
            guard let fix = device?.fix() else { return }
            fixResolver?.handleResolvedFix(fix)
        }
        self.resolver = PolygonMembershipResolver(
            storage: storage, transitionEmitter: tracker, logger: LoggerMock(), contextStore: contextStore,
            dateUtil: device.dateUtil, fixResolver: fixResolver, notificationCenter: NotificationCenter(),
            dwellCoordinator: dwell
        )
        sync.refreshReturnValue = .success(())
        sync.handleMovementReturnValue = .success(())
    }

    /// A resolver pass on a fresh fix, as a movement wake runs it.
    func pass() async {
        await resolver.evaluateMembership(
            geofenceIds: [BootAmbiguityDevice.polygon.id], reason: .movement, requiresFreshFix: true
        )
    }

    /// Binds a region monitor double to this process's resolver and coordinator, as setup does.
    func bind(_ monitor: GeofenceRegionMonitoring) {
        GeofenceMonitorBinder.bind(
            monitor: monitor, resolver: resolver, coordinator: sync, logger: LoggerMock(), dwellCoordinator: dwell
        )
    }

    func visit() async -> GeofenceDwellVisit? {
        await storage.getDwellVisit(geofenceId: BootAmbiguityDevice.polygon.id)
    }

    func dwellRows() async -> [PendingGeofenceMetric] {
        await outbox.rows().filter { $0.transition == .dwell }
    }

    /// The process dies: nothing it scheduled runs again.
    func end() {
        dwell.cancelEvidence(for: BootAmbiguityDevice.polygon.id)
    }

    /// A polygon stay first proven now, then qualified and emitted by a pass 600 s later.
    static func emitted(on device: BootAmbiguityDevice) async throws -> (BootAmbiguityProcess, GeofenceDwellVisit) {
        let process = await BootAmbiguityProcess(device: device)
        await process.pass()
        device.advance(600)
        await process.pass()
        let visit = try #require(await process.visit())
        try #require(visit.emitted)
        try #require(await process.dwellRows().map(\.visitId) == [visit.visitId])
        return (process, visit)
    }
}
