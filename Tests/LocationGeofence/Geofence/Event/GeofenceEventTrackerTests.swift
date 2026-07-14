@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
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
        deliveryTracker: GeofenceDeliveryTracker,
        contextStore: BackgroundDeliveryContextStore,
        eventBus: EventBusHandlerMock = EventBusHandlerMock(),
        dateUtil: DateUtil = DateUtilStub(),
        backgroundTaskRunner: BackgroundTaskRunner = NoBackgroundTaskRunner()
    ) -> GeofenceEventTracker {
        GeofenceEventTracker(
            storage: storage,
            pendingStore: pendingStore,
            deliveryTracker: deliveryTracker,
            contextStore: contextStore,
            eventBusHandler: eventBus,
            dateUtil: dateUtil,
            logger: LoggerMock(),
            cooldownInterval: cooldownInterval,
            backgroundTaskRunner: backgroundTaskRunner
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
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42")
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        #expect(delivery.trackMetricCallsCount == 1)
        #expect(delivery.trackMetricReceivedArguments?.userId == "user_42")
        #expect(await pending.loadAll().isEmpty)
    }

    @Test
    func trackTransition_givenDeliveryFailure_expectQueueRetainedNoEventBus() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in
            onComplete(.failure(.http(statusCode: 503)))
        }
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42")
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        #expect(await pending.loadAll().count == 1)
    }

    @Test
    func trackTransition_givenPersistFails_expectDeliverySkippedAndCooldownReleased() async {
        // Force the pending store onto an unwritable path: a regular file stands where its parent
        // directory should be, so createDirectory + write both fail and append() returns false.
        let blocker = makeTempDirectory()
        FileManager.default.createFile(atPath: blocker.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: blocker) }
        let unwritablePendingDir = blocker.appendingPathComponent("nested")

        let storageDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: storageDir) }
        let storage = makeStorage(directory: storageDir)
        let dateUtil = DateUtilStub()
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let tracker = makeTracker(
            storage: storage,
            pendingStore: makePendingStore(directory: unwritablePendingDir),
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42"),
            dateUtil: dateUtil
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        // Delivery is skipped for a row that never reached disk: sending it and then draining on
        // success could remove a later same-second crossing's row (keys omit transitionId).
        #expect(delivery.trackMetricCallsCount == 0)
        // The cooldown claimed for this crossing was released, so the next crossing retries from a
        // clean state instead of being suppressed. A held cooldown would make this claim return false.
        let canRetry = await storage.tryAcquireCooldown(key: "geo_1:enter", now: dateUtil.now, interval: cooldownInterval)
        #expect(canRetry)
    }

    @Test
    func trackTransition_givenDeliveryFailsThenFlush_expectSameTransitionIdReused() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.transport)) }
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42")
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter) // attempt 1 fails → row persists
        await tracker.flushPending() // attempt 2 replays the persisted row

        let metrics = delivery.trackMetricReceivedInvocations.map(\.metric)
        #expect(metrics.count == 2)
        #expect(metrics.first?.transitionId.isEmpty == false) // minted at capture
        #expect(metrics[0].transitionId == metrics[1].transitionId) // reloaded from disk, reused verbatim
    }

    @Test
    func trackTransition_givenNoUserId_expectEventBusAndQueueDrained() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        let bus = EventBusHandlerMock()
        let dateUtil = DateUtilStub()
        let captureTime = Date(timeIntervalSince1970: 1700000000)
        dateUtil.givenNow = captureTime
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(),
            eventBus: bus,
            dateUtil: dateUtil
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        // Anonymous capture: stamped userId is nil. HTTP path can't attribute,
        // so the row is handed off to EventBus → DataPipeline (anonymous track)
        // and drained from disk.
        #expect(delivery.trackMetricCallsCount == 0)
        #expect(await pending.loadAll().isEmpty)

        let posted = postedGeofenceEvents(from: bus)
        #expect(posted.count == 1)
        #expect(posted.first?.geofenceId == "geo_1")
        #expect(posted.first?.transition == .enter)
        #expect(posted.first?.timestamp == captureTime)
    }

    // MARK: - Cooldown

    @Test
    func trackTransition_givenSameEventWithinCooldown_expectSuppressedAndNoQueueGrowth() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let dateUtil = DateUtilStub()
        let baseTime = Date(timeIntervalSince1970: 1700000000)
        dateUtil.givenNow = baseTime
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42"),
            dateUtil: dateUtil
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)
        #expect(delivery.trackMetricCallsCount == 1)

        dateUtil.givenNow = baseTime.addingTimeInterval(1800)
        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        #expect(delivery.trackMetricCallsCount == 1)
        #expect(await pending.loadAll().isEmpty)
    }

    @Test
    func trackTransition_givenSameEventAfterCooldown_expectTrackedAgain() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let dateUtil = DateUtilStub()
        let baseTime = Date(timeIntervalSince1970: 1700000000)
        dateUtil.givenNow = baseTime
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42"),
            dateUtil: dateUtil
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)
        dateUtil.givenNow = baseTime.addingTimeInterval(cooldownInterval)
        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        #expect(delivery.trackMetricCallsCount == 2)
    }

    @Test
    func trackTransition_givenDifferentTransitionTypes_expectBothTracked() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42")
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)
        await tracker.trackTransition(geofenceId: "geo_1", transition: .exit)

        #expect(delivery.trackMetricCallsCount == 2)
    }

    @Test
    func trackTransition_givenCachedConfigCooldown_expectServerValueWinsOverConstructorDefault() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        // Server-driven cooldown is 30 min; constructor's `cooldownInterval` is the
        // test default (1h). The tracker should consult cached config first.
        let serverCooldown: TimeInterval = 30 * 60
        await storage.setCachedConfig(GeofenceConfig(
            localRefreshTriggerRadius: 1000,
            remoteFetchRefreshTriggerRadius: 3000,
            remoteFetchRefreshExpiry: 24 * 60 * 60,
            duplicateEventsExpiry: serverCooldown,
            maxBusinessGeofences: 19,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        ))
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let dateUtil = DateUtilStub()
        let baseTime = Date(timeIntervalSince1970: 1700000000)
        dateUtil.givenNow = baseTime
        let tracker = makeTracker(
            storage: storage,
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42"),
            dateUtil: dateUtil
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)
        // Halfway through the server cooldown → suppressed (would have been allowed if
        // the constructor's 1h default were in effect).
        dateUtil.givenNow = baseTime.addingTimeInterval(serverCooldown / 2)
        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)
        #expect(delivery.trackMetricCallsCount == 1)

        // Past the server cooldown but still within the constructor default → allowed.
        dateUtil.givenNow = baseTime.addingTimeInterval(serverCooldown + 1)
        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)
        #expect(delivery.trackMetricCallsCount == 2)
    }

    // MARK: - flushPending

    @Test
    func flushPending_givenQueuedMetricsAndUserId_expectDeliveredAndDrained() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let failingDelivery = GeofenceDeliveryTrackerMock()
        failingDelivery.trackMetricClosure = { _, _, onComplete in
            onComplete(.failure(.http(statusCode: 503)))
        }
        let priorTracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: failingDelivery,
            contextStore: makeContextStore(userId: "user_42")
        )
        await priorTracker.trackTransition(geofenceId: "geo_1", transition: .enter)
        await priorTracker.trackTransition(geofenceId: "geo_2", transition: .enter)
        #expect(await pending.loadAll().count == 2)

        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42")
        )

        await tracker.flushPending()

        #expect(delivery.trackMetricCallsCount == 2)
        #expect(await pending.loadAll().isEmpty)
    }

    @Test
    func flushPending_givenDeliveryFailure_expectQueueRetainedNoEventBus() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let failingDelivery = GeofenceDeliveryTrackerMock()
        failingDelivery.trackMetricClosure = { _, _, onComplete in
            onComplete(.failure(.http(statusCode: 503)))
        }
        let priorTracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: failingDelivery,
            contextStore: makeContextStore(userId: "user_42")
        )
        await priorTracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: failingDelivery,
            contextStore: makeContextStore(userId: "user_42")
        )

        await tracker.flushPending()

        #expect(await pending.loadAll().count == 1)
    }

    @Test
    func concurrentFlushPending_expectEachMetricDeliveredOnce() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let failingDelivery = GeofenceDeliveryTrackerMock()
        failingDelivery.trackMetricClosure = { _, _, onComplete in
            onComplete(.failure(.http(statusCode: 503)))
        }
        let priorTracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: failingDelivery,
            contextStore: makeContextStore(userId: "user_42")
        )
        await priorTracker.trackTransition(geofenceId: "geo_1", transition: .enter)
        await priorTracker.trackTransition(geofenceId: "geo_2", transition: .enter)

        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42")
        )

        // Fire two flushPending calls in parallel; active-delivery dedup must prevent
        // either metric from being delivered twice.
        async let flush1: Void = tracker.flushPending()
        async let flush2: Void = tracker.flushPending()
        _ = await(flush1, flush2)

        #expect(delivery.trackMetricCallsCount == 2)
        #expect(await pending.loadAll().isEmpty)
    }

    @Test
    func flushPending_givenAnonymousCaptureThenIdentify_expectNoHttpBackfill() async {
        // Regression: anonymous transitions must NOT auto-deliver as the next
        // identified user via HTTP — they go through EventBus at capture time,
        // not through HTTP after identify (which would mis-attribute).
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
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
        // Anonymous capture posts to EventBus and drains the queue at capture time.
        #expect(await pending.loadAll().isEmpty)
        #expect(postedGeofenceEvents(from: bus).count == 1)

        contextStore.setUserId("user_42")
        await tracker.flushPending()

        // No HTTP backfill, no second EventBus post — the row is already gone.
        #expect(delivery.trackMetricCallsCount == 0)
        #expect(postedGeofenceEvents(from: bus).count == 1)
    }

    // MARK: - userId stamping

    @Test
    func trackTransition_givenIdentifiedUser_expectMetricStampedWithUserId() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        // Fail the HTTP send so the row survives on disk to inspect.
        delivery.trackMetricClosure = { _, _, onComplete in
            onComplete(.failure(.http(statusCode: 503)))
        }
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_A")
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        let queued = await pending.loadAll()
        #expect(queued.first?.userId == "user_A")
    }

    @Test
    func flushPending_givenRowStampedDifferentFromCurrent_expectStampedUserIdUsed() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        // Row was captured under user_A; current user is now user_B (after sign-out + new sign-in).
        _ = await pending.append([PendingGeofenceMetric(
            geofenceId: "geo_1", transition: .enter,
            timestamp: Date(timeIntervalSince1970: 1),
            userId: "user_A",
            name: nil,
            transitionId: "txn_a"
        )])
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_B")
        )

        await tracker.flushPending()

        #expect(delivery.trackMetricCallsCount == 1)
        #expect(delivery.trackMetricReceivedArguments?.userId == "user_A")
    }

    @Test
    func flushPending_givenStampedUserId_andNoCurrent_expectDeliveredWithStamped() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        _ = await pending.append([PendingGeofenceMetric(
            geofenceId: "geo_1", transition: .enter,
            timestamp: Date(timeIntervalSince1970: 1),
            userId: "user_A",
            name: nil,
            transitionId: "txn_a"
        )])
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore()
        )

        await tracker.flushPending()

        #expect(delivery.trackMetricReceivedArguments?.userId == "user_A")
    }

    @Test
    func flushPending_givenNilUserIdOnRow_expectEventBusPostNoHttpCall() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        // Row with no stamped userId (anonymous capture or legacy pre-upgrade).
        let capturedAt = Date(timeIntervalSince1970: 1700000000)
        _ = await pending.append([PendingGeofenceMetric(
            geofenceId: "geo_1", transition: .enter,
            timestamp: capturedAt,
            userId: nil,
            name: nil,
            transitionId: "txn_a"
        )])
        let delivery = GeofenceDeliveryTrackerMock()
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            // Current user is set — proving that the live userId is NOT used as a fallback;
            // the row is anonymous-tracked via EventBus instead.
            contextStore: makeContextStore(userId: "user_current"),
            eventBus: bus
        )

        await tracker.flushPending()

        #expect(delivery.trackMetricCallsCount == 0)
        #expect(await pending.loadAll().isEmpty)

        let posted = postedGeofenceEvents(from: bus)
        #expect(posted.count == 1)
        #expect(posted.first?.timestamp == capturedAt)
    }

    // MARK: - Geofence name resolution

    private func seedGeofence(_ storage: GeofenceStorage, id: String, name: String?) async {
        await storage.setCachedGeofences([
            Geofence(
                id: id, latitude: 1, longitude: 2, radius: 100,
                name: name, transitionTypes: [.enter], lastUpdated: Date(timeIntervalSince1970: 0)
            )
        ])
    }

    @Test
    func trackTransition_givenCachedGeofenceWithName_expectMetricCarriesName() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await seedGeofence(storage, id: "geo_1", name: "HQ")
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        // Fail the send so the row survives on disk for inspection.
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.http(statusCode: 503))) }
        let tracker = makeTracker(
            storage: storage,
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42")
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        #expect(await pending.loadAll().first?.name == "HQ")
    }

    @Test
    func trackTransition_givenGeofenceNotCached_expectNilName() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.http(statusCode: 503))) }
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42")
        )

        await tracker.trackTransition(geofenceId: "geo_unknown", transition: .enter)

        #expect(await pending.loadAll().first?.name == nil)
    }

    @Test
    func trackTransition_givenCachedGeofenceWithNoName_expectNilName() async {
        // A geofence with no name (nil) must omit `geofenceName` rather than sending an empty value.
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await seedGeofence(storage, id: "geo_1", name: nil)
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.http(statusCode: 503))) }
        let tracker = makeTracker(
            storage: storage,
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42")
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        #expect(await pending.loadAll().first?.name == nil)
    }

    // MARK: - Metadata (snapshot + prefer-live)

    private func seedGeofence(_ storage: GeofenceStorage, id: String, name: String, metadata: [String: GeofenceMetadataValue]) async {
        await storage.setCachedGeofences([
            Geofence(
                id: id, latitude: 1, longitude: 2, radius: 100,
                name: name, transitionTypes: [.enter], lastUpdated: Date(timeIntervalSince1970: 0),
                metadata: metadata
            )
        ])
    }

    @Test
    func trackTransition_givenCachedGeofenceWithMetadata_expectMetricCarriesSnapshot() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await seedGeofence(storage, id: "geo_1", name: "HQ", metadata: ["category": .string("office")])
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        // Fail so the row survives on disk for inspection.
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.http(statusCode: 503))) }
        let tracker = makeTracker(
            storage: storage,
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42")
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        #expect(await pending.loadAll().first?.metadata == ["category": .string("office")])
    }

    @Test
    func deliver_givenMetadataChangedAfterCapture_expectFreshMetadataSent() async {
        // Prefer-live: an metadata edit between capture and a later flush goes out current.
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await seedGeofence(storage, id: "geo_1", name: "HQ", metadata: ["tier": .string("gold")])
        let pending = makePendingStore(directory: dir)
        let failing = GeofenceDeliveryTrackerMock()
        failing.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.transport)) }
        let priorTracker = makeTracker(
            storage: storage, pendingStore: pending, deliveryTracker: failing,
            contextStore: makeContextStore(userId: "user_42")
        )
        await priorTracker.trackTransition(geofenceId: "geo_1", transition: .enter) // snapshot gold, persisted

        // Server updated the tier; the cache now reflects it.
        await seedGeofence(storage, id: "geo_1", name: "HQ", metadata: ["tier": .string("platinum")])
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let tracker = makeTracker(
            storage: storage, pendingStore: pending, deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42")
        )

        await tracker.flushPending()

        #expect(delivery.trackMetricReceivedArguments?.metric.metadata == ["tier": .string("platinum")])
    }

    @Test
    func deliver_givenGeofenceEvictedAfterCapture_expectSnapshotMetadataSent() async {
        // Fallback: the geofence left the cache (e.g. a refetch) → the row snapshot is used.
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await seedGeofence(storage, id: "geo_1", name: "HQ", metadata: ["tier": .string("gold")])
        let pending = makePendingStore(directory: dir)
        let failing = GeofenceDeliveryTrackerMock()
        failing.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.transport)) }
        let priorTracker = makeTracker(
            storage: storage, pendingStore: pending, deliveryTracker: failing,
            contextStore: makeContextStore(userId: "user_42")
        )
        await priorTracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        await storage.setCachedGeofences([]) // geofence evicted

        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let tracker = makeTracker(
            storage: storage, pendingStore: pending, deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42")
        )

        await tracker.flushPending()

        #expect(delivery.trackMetricReceivedArguments?.metric.metadata == ["tier": .string("gold")])
    }

    @Test
    func trackTransition_givenAnonymousAndCachedMetadata_expectEventBusEventCarriesMetadata() async {
        // The EventBus (anonymous) path must carry metadata too, not just the HTTP path.
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await seedGeofence(storage, id: "geo_1", name: "HQ", metadata: ["tier": .string("gold")])
        let pending = makePendingStore(directory: dir)
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: storage, pendingStore: pending,
            deliveryTracker: GeofenceDeliveryTrackerMock(),
            contextStore: makeContextStore(), eventBus: bus
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        #expect(postedGeofenceEvents(from: bus).first?.metadata == ["tier": .string("gold")])
    }

    @Test
    func deliver_givenNameChangedAfterCapture_expectFreshNameSent() async {
        // Prefer-live applies to name too, not just metadata.
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await seedGeofence(storage, id: "geo_1", name: "Old HQ", metadata: [:])
        let pending = makePendingStore(directory: dir)
        let failing = GeofenceDeliveryTrackerMock()
        failing.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.transport)) }
        let priorTracker = makeTracker(
            storage: storage, pendingStore: pending, deliveryTracker: failing,
            contextStore: makeContextStore(userId: "user_42")
        )
        await priorTracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        await seedGeofence(storage, id: "geo_1", name: "New HQ", metadata: [:])
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let tracker = makeTracker(
            storage: storage, pendingStore: pending, deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42")
        )

        await tracker.flushPending()

        #expect(delivery.trackMetricReceivedArguments?.metric.name == "New HQ")
    }

    // MARK: - Geoset fan-out

    private func seedGeofence(_ storage: GeofenceStorage, id: String, name: String, geosetIds: [String]) async {
        await storage.setCachedGeofences([
            Geofence(
                id: id, latitude: 1, longitude: 2, radius: 100,
                name: name, transitionTypes: [.enter], lastUpdated: Date(timeIntervalSince1970: 0),
                geosetIds: geosetIds
            )
        ])
    }

    @Test
    func trackTransition_givenGeofenceInTwoGeosets_expectOneStandaloneMetricPerGeoset() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await seedGeofence(storage, id: "geo_1", name: "HQ", geosetIds: ["set_y", "set_z"])
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let tracker = makeTracker(
            storage: storage,
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42")
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        // One delivery per geoset, each a standalone event with a scalar geosetId
        // plus full geofence metadata.
        let metrics = delivery.trackMetricReceivedInvocations.map(\.metric)
        #expect(metrics.count == 2)
        #expect(Set(metrics.compactMap(\.geosetId)) == ["set_y", "set_z"]) // delivery order is not guaranteed (concurrent)
        #expect(metrics.allSatisfy { $0.geofenceId == "geo_1" })
        #expect(metrics.allSatisfy { $0.name == "HQ" })
        #expect(metrics.allSatisfy { $0.transition == .enter })
        // All fan-out rows share one transitionId (same physical crossing); geosetId distinguishes them.
        #expect(Set(metrics.map(\.transitionId)).count == 1)
        #expect(await pending.loadAll().isEmpty)
    }

    @Test
    func trackTransition_givenGeofenceInNoGeoset_expectSingleMetricWithoutGeosetId() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await seedGeofence(storage, id: "geo_1", name: "HQ", geosetIds: [])
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let tracker = makeTracker(
            storage: storage,
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42")
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        let metrics = delivery.trackMetricReceivedInvocations.map(\.metric)
        #expect(metrics.count == 1)
        #expect(metrics.first?.geosetId == nil)
    }

    @Test
    func trackTransition_givenBlankGeosetIds_expectSingleMetricWithoutGeosetId() async {
        // Blank ids are dropped, so an all-empty membership behaves like no geoset — one event
        // without a geosetId, not a stray event carrying an empty string.
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await seedGeofence(storage, id: "geo_1", name: "HQ", geosetIds: ["", ""])
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let tracker = makeTracker(
            storage: storage,
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42")
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        let metrics = delivery.trackMetricReceivedInvocations.map(\.metric)
        #expect(metrics.count == 1)
        #expect(metrics.first?.geosetId == nil)
    }

    @Test
    func trackTransition_givenDuplicateGeosetIds_expectOneEventPerDistinctGeoset() async {
        // A fence that lists the same geoset twice must fan out once per distinct geoset — not
        // deliver the duplicate twice (the rows would share a pending key but the deliver loop
        // would still send each).
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await seedGeofence(storage, id: "geo_1", name: "HQ", geosetIds: ["set_y", "set_y", "set_z"])
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let tracker = makeTracker(
            storage: storage,
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42")
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        let metrics = delivery.trackMetricReceivedInvocations.map(\.metric)
        #expect(metrics.count == 2)
        #expect(Set(metrics.compactMap(\.geosetId)) == ["set_y", "set_z"]) // duplicate dropped (delivery order not guaranteed)
    }

    @Test
    func trackTransition_givenTwoGeosetsAndDeliveryFailure_expectBothRowsRetained() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await seedGeofence(storage, id: "geo_1", name: "HQ", geosetIds: ["set_y", "set_z"])
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.http(statusCode: 503))) }
        let tracker = makeTracker(
            storage: storage,
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42")
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        // Both fan-out rows persist independently; the pending-store key includes the
        // geosetId so the rows of one transition cannot collide with each other.
        let persisted = await pending.loadAll()
        #expect(persisted.count == 2)
        #expect(Set(persisted.compactMap(\.geosetId)) == ["set_y", "set_z"])
    }

    @Test
    func trackTransition_givenTwoGeosetsAnonymous_expectOneEventBusEventPerGeoset() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await seedGeofence(storage, id: "geo_1", name: "HQ", geosetIds: ["set_y", "set_z"])
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: storage,
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(),
            eventBus: bus
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        #expect(delivery.trackMetricCallsCount == 0)
        #expect(await pending.loadAll().isEmpty)
        let posted = postedGeofenceEvents(from: bus)
        #expect(posted.count == 2)
        #expect(Set(posted.compactMap(\.geosetId)) == ["set_y", "set_z"]) // delivery order is not guaranteed (concurrent)
        #expect(posted.allSatisfy { $0.geofenceId == "geo_1" })
    }

    @Test
    func trackTransition_givenTwoGeosetsWithinCooldown_expectSecondTransitionFullySuppressed() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await seedGeofence(storage, id: "geo_1", name: "HQ", geosetIds: ["set_y", "set_z"])
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let tracker = makeTracker(
            storage: storage,
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42")
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)
        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        // The cooldown gates the physical transition, before fan-out: the second
        // enter produces zero additional deliveries, not a partial fan-out.
        #expect(delivery.trackMetricCallsCount == 2)
    }

    // MARK: - Background task assertion

    @Test
    func trackTransition_expectDeliveryRunsInsideBackgroundTask() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let runner = SpyBackgroundTaskRunner()
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in
            runner.record("deliver")
            onComplete(.success(()))
        }
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42"),
            backgroundTaskRunner: runner
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        // Delivery is bracketed by the assertion so the OS keeps the app alive through the send.
        #expect(runner.callCount.wrappedValue == 1)
        #expect(runner.events.wrappedValue == ["begin", "deliver", "end"])
    }

    @Test
    func flushPending_givenQueuedRow_expectReplayRunsInsideBackgroundTask() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        _ = await pending.append([
            PendingGeofenceMetric(
                geofenceId: "geo_1",
                transition: .enter,
                timestamp: Date(timeIntervalSince1970: 1700000000),
                userId: "user_42",
                name: nil,
                transitionId: "txn_1",
                geosetId: nil
            )
        ])
        let runner = SpyBackgroundTaskRunner()
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in
            runner.record("deliver")
            onComplete(.success(()))
        }
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42"),
            backgroundTaskRunner: runner
        )

        await tracker.flushPending()

        #expect(runner.callCount.wrappedValue == 1)
        #expect(runner.events.wrappedValue == ["begin", "deliver", "end"])
    }

    @Test
    func flushPending_givenEmptyQueue_expectNoBackgroundTaskRequested() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = SpyBackgroundTaskRunner()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: makePendingStore(directory: dir),
            deliveryTracker: GeofenceDeliveryTrackerMock(),
            contextStore: makeContextStore(userId: "user_42"),
            backgroundTaskRunner: runner
        )

        await tracker.flushPending()

        // Nothing to replay → no background time requested.
        #expect(runner.callCount.wrappedValue == 0)
    }
}

/// Records begin/end around the work and lets the work append its own markers, so tests can assert
/// delivery runs strictly inside the assertion window.
private final class SpyBackgroundTaskRunner: BackgroundTaskRunner, @unchecked Sendable {
    let callCount = Synchronized(0)
    let events = Synchronized<[String]>([])

    func record(_ event: String) {
        events.mutating { $0.append(event) }
    }

    func withBackgroundTime(_ work: @Sendable () async -> Void) async {
        callCount.mutating { $0 += 1 }
        record("begin")
        await work()
        record("end")
    }
}
