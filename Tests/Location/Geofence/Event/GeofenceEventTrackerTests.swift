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

    private func makePendingStore(directory: URL) -> PendingGeofenceMetricStore {
        PendingGeofenceMetricStore(fileManager: .default, directoryURL: directory)
    }

    private func makeContextStore(userId: String? = nil) -> BackgroundDeliveryContextStore {
        let store = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        if let userId { store.setUserId(userId) }
        return store
    }

    private func makeTracker(
        storage: GeofenceStorage,
        pendingStore: PendingGeofenceMetricStore,
        deliveryTracker: GeofenceDeliveryTracker?,
        contextStore: BackgroundDeliveryContextStore,
        eventBus: EventBusHandlerMock,
        dateUtil: DateUtil = DateUtilStub()
    ) -> GeofenceEventTracker {
        GeofenceEventTracker(
            storage: storage,
            pendingStore: pendingStore,
            deliveryTracker: deliveryTracker,
            contextStore: contextStore,
            eventBusHandler: eventBus,
            dateUtil: dateUtil,
            logger: LoggerMock(),
            cooldownInterval: cooldownInterval
        )
    }

    private func postedGeofenceEvents(from bus: EventBusHandlerMock) -> [TrackGeofenceMetricEvent] {
        bus.postEventReceivedInvocations.compactMap { $0 as? TrackGeofenceMetricEvent }
    }

    // MARK: - Direct HTTP path

    @Test
    func trackTransition_givenUserIdAndSuccessfulDelivery_expectQueueDrainedNoEventBus() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.deliverClosure = { _, _, onComplete in onComplete(.success(())) }
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42"),
            eventBus: bus
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        #expect(delivery.deliverCallsCount == 1)
        #expect(delivery.deliverReceivedArguments?.userId == "user_42")
        #expect(await pending.loadAll().isEmpty)
        #expect(postedGeofenceEvents(from: bus).isEmpty)
    }

    @Test
    func trackTransition_givenDeliveryFailure_expectQueueRetainedNoEventBus() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.deliverClosure = { _, _, onComplete in
            onComplete(.failure(.unsuccessfulStatusCode(503, apiMessage: "boom")))
        }
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42"),
            eventBus: bus
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        #expect(await pending.loadAll().count == 1)
        #expect(postedGeofenceEvents(from: bus).isEmpty)
    }

    @Test
    func trackTransition_givenNoUserId_expectQueueRetainedNoEventBus() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(),
            eventBus: bus
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        #expect(delivery.deliverCallsCount == 0)
        #expect(await pending.loadAll().count == 1)
        #expect(postedGeofenceEvents(from: bus).isEmpty)
    }

    @Test
    func trackTransition_givenNoDeliveryTracker_expectEventBusAndQueueDrained() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: nil,
            contextStore: makeContextStore(userId: "user_42"),
            eventBus: bus
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        #expect(await pending.loadAll().isEmpty)
        #expect(postedGeofenceEvents(from: bus).count == 1)
    }

    // MARK: - Cooldown

    @Test
    func trackTransition_givenSameEventWithinCooldown_expectSuppressedAndNoQueueGrowth() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.deliverClosure = { _, _, onComplete in onComplete(.success(())) }
        let dateUtil = DateUtilStub()
        let baseTime = Date(timeIntervalSince1970: 1700000000)
        dateUtil.givenNow = baseTime
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42"),
            eventBus: bus,
            dateUtil: dateUtil
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)
        #expect(delivery.deliverCallsCount == 1)

        dateUtil.givenNow = baseTime.addingTimeInterval(1800)
        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        #expect(delivery.deliverCallsCount == 1)
        #expect(await pending.loadAll().isEmpty)
    }

    @Test
    func trackTransition_givenSameEventAfterCooldown_expectTrackedAgain() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.deliverClosure = { _, _, onComplete in onComplete(.success(())) }
        let dateUtil = DateUtilStub()
        let baseTime = Date(timeIntervalSince1970: 1700000000)
        dateUtil.givenNow = baseTime
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42"),
            eventBus: bus,
            dateUtil: dateUtil
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)
        dateUtil.givenNow = baseTime.addingTimeInterval(cooldownInterval)
        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        #expect(delivery.deliverCallsCount == 2)
    }

    @Test
    func trackTransition_givenDifferentTransitionTypes_expectBothTracked() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.deliverClosure = { _, _, onComplete in onComplete(.success(())) }
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42"),
            eventBus: bus
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)
        await tracker.trackTransition(geofenceId: "geo_1", transition: .exit)

        #expect(delivery.deliverCallsCount == 2)
    }

    // MARK: - flushPending

    @Test
    func flushPending_givenQueuedMetricsAndUserId_expectDeliveredAndDrained() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let failingDelivery = GeofenceDeliveryTrackerMock()
        failingDelivery.deliverClosure = { _, _, onComplete in
            onComplete(.failure(.unsuccessfulStatusCode(503, apiMessage: "boom")))
        }
        let priorTracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: failingDelivery,
            contextStore: makeContextStore(userId: "user_42"),
            eventBus: EventBusHandlerMock()
        )
        await priorTracker.trackTransition(geofenceId: "geo_1", transition: .enter)
        await priorTracker.trackTransition(geofenceId: "geo_2", transition: .enter)
        #expect(await pending.loadAll().count == 2)

        let delivery = GeofenceDeliveryTrackerMock()
        delivery.deliverClosure = { _, _, onComplete in onComplete(.success(())) }
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42"),
            eventBus: EventBusHandlerMock()
        )

        await tracker.flushPending()

        #expect(delivery.deliverCallsCount == 2)
        #expect(await pending.loadAll().isEmpty)
    }

    @Test
    func flushPending_givenDeliveryFailure_expectQueueRetainedNoEventBus() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let failingDelivery = GeofenceDeliveryTrackerMock()
        failingDelivery.deliverClosure = { _, _, onComplete in
            onComplete(.failure(.unsuccessfulStatusCode(503, apiMessage: "boom")))
        }
        let priorTracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: failingDelivery,
            contextStore: makeContextStore(userId: "user_42"),
            eventBus: EventBusHandlerMock()
        )
        await priorTracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: failingDelivery,
            contextStore: makeContextStore(userId: "user_42"),
            eventBus: bus
        )

        await tracker.flushPending()

        #expect(await pending.loadAll().count == 1)
        #expect(postedGeofenceEvents(from: bus).isEmpty)
    }

    @Test
    func concurrentFlushPending_expectEachMetricDeliveredOnce() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let failingDelivery = GeofenceDeliveryTrackerMock()
        failingDelivery.deliverClosure = { _, _, onComplete in
            onComplete(.failure(.unsuccessfulStatusCode(503, apiMessage: "boom")))
        }
        let priorTracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: failingDelivery,
            contextStore: makeContextStore(userId: "user_42"),
            eventBus: EventBusHandlerMock()
        )
        await priorTracker.trackTransition(geofenceId: "geo_1", transition: .enter)
        await priorTracker.trackTransition(geofenceId: "geo_2", transition: .enter)

        let delivery = GeofenceDeliveryTrackerMock()
        delivery.deliverClosure = { _, _, onComplete in onComplete(.success(())) }
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42"),
            eventBus: EventBusHandlerMock()
        )

        // Fire two flushPending calls in parallel; active-delivery dedup must prevent
        // either metric from being delivered twice.
        async let flush1: Void = tracker.flushPending()
        async let flush2: Void = tracker.flushPending()
        _ = await(flush1, flush2)

        #expect(delivery.deliverCallsCount == 2)
        #expect(await pending.loadAll().isEmpty)
    }

    @Test
    func flushPending_givenNoUserIdTransitionThenIdentify_expectDeliveredAndDrained() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.deliverClosure = { _, _, onComplete in onComplete(.success(())) }
        let contextStore = makeContextStore()
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: contextStore,
            eventBus: bus
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)
        #expect(delivery.deliverCallsCount == 0)
        #expect(await pending.loadAll().count == 1)

        contextStore.setUserId("user_42")
        await tracker.flushPending()

        #expect(delivery.deliverCallsCount == 1)
        #expect(delivery.deliverReceivedArguments?.userId == "user_42")
        #expect(await pending.loadAll().isEmpty)
        #expect(postedGeofenceEvents(from: bus).isEmpty)
    }
}
