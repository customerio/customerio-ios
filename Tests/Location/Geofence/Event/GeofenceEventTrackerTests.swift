@testable import CioInternalCommon
@testable import CioLocation
import Foundation
import SharedTests
import Testing

@Suite("GeofenceEventTracker")
struct GeofenceEventTrackerTests {
    private let cooldownInterval: TimeInterval = 3600

    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func makeStorage(directory: URL) -> GeofenceStorage {
        GeofenceStorage(fileManager: .default, directoryURL: directory)
    }

    private func makeTracker(
        storage: GeofenceStorage,
        eventBus: EventBusHandlerMock,
        dateUtil: DateUtil = DateUtilStub()
    ) -> GeofenceEventTracker {
        GeofenceEventTracker(
            storage: storage,
            eventBusHandler: eventBus,
            dateUtil: dateUtil,
            logger: LoggerMock(),
            cooldownInterval: cooldownInterval
        )
    }

    private func postedGeofenceEvents(from bus: EventBusHandlerMock) -> [TrackGeofenceMetricEvent] {
        bus.postEventReceivedInvocations.compactMap { $0 as? TrackGeofenceMetricEvent }
    }

    @Test
    func trackTransition_givenEnter_expectMetricEventPosted() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(storage: storage, eventBus: bus)

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        let events = postedGeofenceEvents(from: bus)
        #expect(events.count == 1)
        #expect(events.first?.geofenceId == "geo_1")
        #expect(events.first?.transition == .enter)
    }

    @Test
    func trackTransition_givenExit_expectMetricEventPosted() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(storage: storage, eventBus: bus)

        await tracker.trackTransition(geofenceId: "geo_1", transition: .exit)

        let events = postedGeofenceEvents(from: bus)
        #expect(events.count == 1)
        #expect(events.first?.transition == .exit)
    }

    @Test
    func trackTransition_givenSameEventWithinCooldown_expectSuppressed() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let dateUtil = DateUtilStub()
        let baseTime = Date(timeIntervalSince1970: 1700000000)
        dateUtil.givenNow = baseTime
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(storage: storage, eventBus: bus, dateUtil: dateUtil)

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)
        #expect(postedGeofenceEvents(from: bus).count == 1)

        dateUtil.givenNow = baseTime.addingTimeInterval(1800)
        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)
        #expect(postedGeofenceEvents(from: bus).count == 1)
    }

    @Test
    func trackTransition_givenSameEventAfterCooldown_expectTracked() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let dateUtil = DateUtilStub()
        let baseTime = Date(timeIntervalSince1970: 1700000000)
        dateUtil.givenNow = baseTime
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(storage: storage, eventBus: bus, dateUtil: dateUtil)

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)
        #expect(postedGeofenceEvents(from: bus).count == 1)

        dateUtil.givenNow = baseTime.addingTimeInterval(cooldownInterval)
        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)
        #expect(postedGeofenceEvents(from: bus).count == 2)
    }

    @Test
    func trackTransition_givenDifferentTransitionTypes_expectBothTracked() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(storage: storage, eventBus: bus)

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)
        await tracker.trackTransition(geofenceId: "geo_1", transition: .exit)

        #expect(postedGeofenceEvents(from: bus).count == 2)
    }

    @Test
    func trackTransition_givenDifferentGeofences_expectBothTracked() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(storage: storage, eventBus: bus)

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)
        await tracker.trackTransition(geofenceId: "geo_2", transition: .enter)

        #expect(postedGeofenceEvents(from: bus).count == 2)
    }

    @Test
    func trackTransition_givenExpiredCooldowns_expectPurged() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let dateUtil = DateUtilStub()
        let baseTime = Date(timeIntervalSince1970: 1700000000)
        dateUtil.givenNow = baseTime
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(storage: storage, eventBus: bus, dateUtil: dateUtil)

        await tracker.trackTransition(geofenceId: "geo_old", transition: .enter)
        #expect(await storage.getEventCooldowns().count == 1)

        dateUtil.givenNow = baseTime.addingTimeInterval(cooldownInterval + 1)
        await tracker.trackTransition(geofenceId: "geo_new", transition: .enter)

        let cooldowns = await storage.getEventCooldowns()
        #expect(cooldowns["geo_old:enter"] == nil)
        #expect(cooldowns["geo_new:enter"] != nil)
    }

    @Test
    func trackTransition_givenCooldownPersisted_expectSurvivedNewTrackerInstance() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sharedStorage = makeStorage(directory: dir)
        let dateUtil = DateUtilStub()
        let baseTime = Date(timeIntervalSince1970: 1700000000)
        dateUtil.givenNow = baseTime

        let bus1 = EventBusHandlerMock()
        let tracker1 = makeTracker(storage: sharedStorage, eventBus: bus1, dateUtil: dateUtil)
        await tracker1.trackTransition(geofenceId: "geo_1", transition: .enter)
        #expect(postedGeofenceEvents(from: bus1).count == 1)

        dateUtil.givenNow = baseTime.addingTimeInterval(1800)
        let bus2 = EventBusHandlerMock()
        let tracker2 = makeTracker(storage: sharedStorage, eventBus: bus2, dateUtil: dateUtil)
        await tracker2.trackTransition(geofenceId: "geo_1", transition: .enter)
        #expect(postedGeofenceEvents(from: bus2).isEmpty)
    }
}
