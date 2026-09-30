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
    /// Fixed, so a row's dedup key (which includes the timestamp's second) is stable across runs.
    private let crossedAt = Date(timeIntervalSince1970: 1700000000)

    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func makeStorage(directory: URL) -> GeofenceStorage {
        GeofenceStorage(fileManager: .default, directoryURL: directory)
    }

    private func makePendingStore(directory: URL) -> PendingGeofenceMetricStore {
        PendingGeofenceMetricStore(logger: LoggerMock(), fileManager: .default, directoryURL: directory)
    }

    private func makeContextStore(userId: String? = nil, cdpApiKey: String? = nil) -> BackgroundDeliveryContextStore {
        let store = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        if let userId { store.setUserId(userId) }
        if let cdpApiKey { store.setCdpApiKey(cdpApiKey) }
        return store
    }

    private func makeTracker(
        storage: GeofenceStorage,
        pendingStore: PendingGeofenceMetricStore,
        deliveryTracker: GeofenceDeliveryTracker,
        contextStore: BackgroundDeliveryContextStore,
        eventBus: EventBusHandlerMock = EventBusHandlerMock(),
        dateUtil: DateUtil = DateUtilStub(),
        logger: Logger = LoggerMock(),
        backgroundTaskRunner: BackgroundTaskRunner = NoBackgroundTaskRunner()
    ) -> GeofenceEventTracker {
        GeofenceEventTracker(
            storage: storage,
            pendingStore: pendingStore,
            deliveryTracker: deliveryTracker,
            contextStore: contextStore,
            eventBusHandler: eventBus,
            dateUtil: dateUtil,
            logger: logger,
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
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42"),
            eventBus: bus
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)

        // Fresh transition goes out over HTTP only — the EventBus channel is for replay.
        #expect(delivery.trackMetricCallsCount == 1)
        #expect(delivery.trackMetricReceivedArguments?.userId == "user_42")
        #expect(postedGeofenceEvents(from: bus).isEmpty)
        #expect(await pending.rows().isEmpty)
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

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)

        #expect(await pending.rows().count == 1)
    }

    @Test
    func trackTransition_givenPersistFails_expectDeliverySkippedAndCooldownReleased() async {
        // A file where the pending store's parent directory should be makes the write fail.
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

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)

        // Skipped: keys omit transitionId, so draining on success could remove a later same-second row.
        #expect(delivery.trackMetricCallsCount == 0)
        // Released: a held cooldown would make this claim return the remaining time.
        let remaining = await storage.tryAcquireCooldown(key: "user_42:geo_1:enter", now: dateUtil.now, interval: cooldownInterval)
        #expect(remaining == nil)
    }

    /// No write was attempted, so it must not be reported as a failed write.
    @Test
    func trackTransition_givenQueueUnreadable_expectRefusalNotAWriteFailure() async {
        let dir = makeTempDirectory()
        let queueFile = dir.appendingPathComponent("pending_geofence_metrics.json")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: queueFile.path)
            try? FileManager.default.removeItem(at: dir)
        }
        let pending = makePendingStore(directory: dir)
        #expect(await pending.append([PendingGeofenceMetric(
            geofenceId: "geo_old", transition: .enter, timestamp: Date(timeIntervalSince1970: 1),
            userId: "user_42", name: nil, transitionId: "txn_old"
        )]) == .persisted)
        let before = try? Data(contentsOf: queueFile)
        try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: queueFile.path)

        let storage = makeStorage(directory: makeTempDirectory())
        let dateUtil = DateUtilStub()
        let logger = LoggerMock()
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let tracker = makeTracker(
            storage: storage,
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42"),
            dateUtil: dateUtil,
            logger: logger
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)

        let messages = logger.errorReceivedInvocations.map(\.message)
        #expect(messages.contains { $0.contains("the pending queue could not be read, so no write was attempted") })
        #expect(!messages.contains { $0.contains("Failed to persist") })
        #expect(delivery.trackMetricCallsCount == 0)
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: queueFile.path)
        #expect((try? Data(contentsOf: queueFile)) == before)
        // Released, as on the write-failure path.
        let remaining = await storage.tryAcquireCooldown(key: "user_42:geo_1:enter", now: dateUtil.now, interval: cooldownInterval)
        #expect(remaining == nil)
    }

    @Test
    func trackTransition_givenDeliveryFailsThenFlush_expectSameTransitionIdReused() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.transport)) }
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42"),
            eventBus: bus
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt) // fresh HTTP fails → row persists
        await tracker.flushPending() // replay hands the persisted row to EventBus

        // Both carry the transitionId minted at capture, so the server dedupes them.
        let httpTransitionId = delivery.trackMetricReceivedInvocations.map(\.metric).first?.transitionId
        let busTransitionId = postedGeofenceEvents(from: bus).first?.transitionId
        #expect(delivery.trackMetricCallsCount == 1)
        #expect(postedGeofenceEvents(from: bus).count == 1)
        #expect(httpTransitionId?.isEmpty == false)
        #expect(httpTransitionId == busTransitionId)
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

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)
        #expect(delivery.trackMetricCallsCount == 1)

        dateUtil.givenNow = baseTime.addingTimeInterval(1800)
        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)

        #expect(delivery.trackMetricCallsCount == 1)
        #expect(await pending.rows().isEmpty)
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

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: baseTime)
        dateUtil.givenNow = baseTime.addingTimeInterval(cooldownInterval)
        await tracker.trackTransition(
            geofenceId: "geo_1", transition: .enter, occurredAt: baseTime.addingTimeInterval(cooldownInterval)
        )

        #expect(delivery.trackMetricCallsCount == 2)
    }

    @Test
    func trackTransition_givenDifferentUserWithinCooldown_expectNotSuppressed() async {
        // A fast re-login can skip sign-out cleanup and leave A's cooldown in shared storage.
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let dateUtil = DateUtilStub()
        let baseTime = Date(timeIntervalSince1970: 1700000000)
        dateUtil.givenNow = baseTime

        let trackerA = makeTracker(
            storage: storage,
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_A"),
            dateUtil: dateUtil
        )
        await trackerA.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: baseTime)
        #expect(delivery.trackMetricCallsCount == 1)

        dateUtil.givenNow = baseTime.addingTimeInterval(cooldownInterval / 2)
        let trackerB = makeTracker(
            storage: storage,
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_B"),
            dateUtil: dateUtil
        )
        await trackerB.trackTransition(
            geofenceId: "geo_1", transition: .enter, occurredAt: baseTime.addingTimeInterval(cooldownInterval / 2)
        )

        #expect(delivery.trackMetricCallsCount == 2)
        #expect(delivery.trackMetricReceivedArguments?.userId == "user_B")

        await trackerA.trackTransition(
            geofenceId: "geo_1", transition: .enter, occurredAt: baseTime.addingTimeInterval(cooldownInterval / 2)
        )
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

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)
        await tracker.trackTransition(geofenceId: "geo_1", transition: .exit, occurredAt: crossedAt)

        #expect(delivery.trackMetricCallsCount == 2)
    }

    @Test
    func trackTransition_givenCachedConfigCooldown_expectServerValueWinsOverConstructorDefault() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        // Server cooldown 30 min vs the constructor's 1 h.
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

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)
        dateUtil.givenNow = baseTime.addingTimeInterval(serverCooldown / 2)
        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)
        #expect(delivery.trackMetricCallsCount == 1)

        // Past the server cooldown but still within the constructor default → allowed.
        dateUtil.givenNow = baseTime.addingTimeInterval(serverCooldown + 1)
        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)
        #expect(delivery.trackMetricCallsCount == 2)
    }

    // MARK: - flushPending

    @Test
    func flushPending_givenNoHttpContext_expectPostedToEventBusAndDrained() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        // Seeded directly: tracking a transition would replay the backlog before inspection.
        _ = await pending.append([
            PendingGeofenceMetric(
                geofenceId: "geo_1", transition: .enter,
                timestamp: Date(timeIntervalSince1970: 1),
                userId: "user_42", name: nil, transitionId: "txn_1"
            ),
            PendingGeofenceMetric(
                geofenceId: "geo_2", transition: .enter,
                timestamp: Date(timeIntervalSince1970: 2),
                userId: "user_42", name: nil, transitionId: "txn_2"
            )
        ])
        #expect(await pending.rows().count == 2)

        let delivery = GeofenceDeliveryTrackerMock()
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42"),
            eventBus: bus
        )

        await tracker.flushPending()

        // No cdpApiKey → EventBus.
        #expect(postedGeofenceEvents(from: bus).count == 2)
        #expect(delivery.trackMetricCallsCount == 0)
        #expect(await pending.rows().isEmpty)
    }

    @Test
    func flushPending_givenColdWakeWithPersistedKey_expectDeliveredOverHttpAndDrained() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        _ = await pending.append([
            PendingGeofenceMetric(
                geofenceId: "geo_1", transition: .enter,
                timestamp: Date(timeIntervalSince1970: 1),
                userId: "user_42", name: nil, transitionId: "txn_1"
            ),
            PendingGeofenceMetric(
                geofenceId: "geo_2", transition: .enter,
                timestamp: Date(timeIntervalSince1970: 2),
                userId: "user_42", name: nil, transitionId: "txn_2"
            )
        ])
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42", cdpApiKey: "key_123"),
            eventBus: bus
        )

        await tracker.flushPending()

        // Persisted key, no live DataPipeline (a wrapper cold wake): ships over HTTP now.
        #expect(Set(delivery.trackMetricReceivedInvocations.map(\.metric.geofenceId)) == ["geo_1", "geo_2"])
        #expect(postedGeofenceEvents(from: bus).isEmpty)
        #expect(await pending.rows().isEmpty)
    }

    @Test
    func flushPending_givenColdWakeHttpFailure_expectRowRetainedNoEventBus() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        _ = await pending.append([PendingGeofenceMetric(
            geofenceId: "geo_1", transition: .enter,
            timestamp: Date(timeIntervalSince1970: 1),
            userId: "user_42", name: nil, transitionId: "txn_1"
        )])
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in
            onComplete(.failure(.http(statusCode: 503)))
        }
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42", cdpApiKey: "key_123"),
            eventBus: bus
        )

        await tracker.flushPending()

        // EventBus is the no-context fallback, not the failure fallback.
        #expect(await pending.rows().count == 1)
        #expect(postedGeofenceEvents(from: bus).isEmpty)
    }

    @Test
    func flushPending_givenColdWakeRowStampedDifferentUser_expectStampedUserIdSent() async {
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
            contextStore: makeContextStore(userId: "user_B", cdpApiKey: "key_123")
        )

        await tracker.flushPending()

        #expect(delivery.trackMetricReceivedArguments?.userId == "user_A")
        #expect(delivery.trackMetricReceivedArguments?.metric.userId == "user_A")
    }

    @Test
    func flushPending_givenLiveDataPipeline_expectEventBusPreferredOverHttp() async {
        // DataPipeline's durable queue owns retry when it is live, even with a persisted key.
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        _ = await pending.append([PendingGeofenceMetric(
            geofenceId: "geo_1", transition: .enter,
            timestamp: Date(timeIntervalSince1970: 1),
            userId: "user_42", name: nil, transitionId: "txn_1"
        )])
        let contextStore = makeContextStore(userId: "user_42", cdpApiKey: "persisted_key")
        let liveProvider = StubCdpApiKeyProvider(cdpApiKey: "live_key")
        contextStore.setCdpApiKeyProvider(liveProvider)
        let delivery = GeofenceDeliveryTrackerMock()
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: contextStore,
            eventBus: bus
        )

        await tracker.flushPending()

        #expect(postedGeofenceEvents(from: bus).count == 1)
        #expect(delivery.trackMetricCallsCount == 0)
        #expect(await pending.rows().isEmpty)
        // The store holds the provider weakly; keep it alive through the flush above.
        withExtendedLifetime(liveProvider) {}
    }

    @Test
    func trackTransition_givenColdWakeBacklog_expectBacklogShippedOverHttpWithCrossing() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        _ = await pending.append([PendingGeofenceMetric(
            geofenceId: "geo_old", transition: .exit,
            timestamp: Date(timeIntervalSince1970: 1),
            userId: "user_42", name: nil, transitionId: "txn_old"
        )])
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42", cdpApiKey: "key_123"),
            eventBus: bus
        )

        await tracker.trackTransition(geofenceId: "geo_new", transition: .enter, occurredAt: crossedAt)

        #expect(Set(delivery.trackMetricReceivedInvocations.map(\.metric.geofenceId)) == ["geo_old", "geo_new"])
        #expect(postedGeofenceEvents(from: bus).isEmpty)
        #expect(await pending.rows().isEmpty)
    }

    @Test
    func concurrentFlushPending_expectDrainedAndEachMetricPostedAtLeastOnce() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        _ = await pending.append([
            PendingGeofenceMetric(
                geofenceId: "geo_1", transition: .enter,
                timestamp: Date(timeIntervalSince1970: 1),
                userId: "user_42", name: nil, transitionId: "txn_1"
            ),
            PendingGeofenceMetric(
                geofenceId: "geo_2", transition: .enter,
                timestamp: Date(timeIntervalSince1970: 2),
                userId: "user_42", name: nil, transitionId: "txn_2"
            )
        ])

        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: GeofenceDeliveryTrackerMock(),
            contextStore: makeContextStore(userId: "user_42"),
            eventBus: bus
        )

        // At-least-once by design: two flushes may double-post a row (deduped by transitionId).
        async let flush1: Void = tracker.flushPending()
        async let flush2: Void = tracker.flushPending()
        _ = await(flush1, flush2)

        #expect(Set(postedGeofenceEvents(from: bus).map(\.geofenceId)) == ["geo_1", "geo_2"])
        #expect(await pending.rows().isEmpty)
    }

    @Test
    func trackTransition_givenSlowBacklogReplay_expectFreshRowDurableBeforeBacklogCompletes() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        _ = await pending.append([PendingGeofenceMetric(
            geofenceId: "geo_old", transition: .exit,
            timestamp: Date(timeIntervalSince1970: 1),
            userId: "user_42", name: nil, transitionId: "txn_old"
        )])
        let delivery = GeofenceDeliveryTrackerMock()
        // Backlog send held in flight; fresh send fails so its row must survive on disk.
        let backlogStarted = AsyncStream.makeStream(of: Void.self)
        let backlogRelease = AsyncStream.makeStream(of: Void.self)
        delivery.trackMetricClosure = { metric, _, onComplete in
            if metric.geofenceId == "geo_old" {
                backlogStarted.continuation.yield()
                Task {
                    for await _ in backlogRelease.stream {
                        break
                    }
                    onComplete(.success(()))
                }
            } else {
                onComplete(.failure(.transport))
            }
        }
        // Cold-wake HTTP route: persisted key, no live provider.
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42", cdpApiKey: "key_123")
        )

        let tracking = Task { await tracker.trackTransition(geofenceId: "geo_new", transition: .enter, occurredAt: crossedAt) }
        for await _ in backlogStarted.stream {
            break
        }
        #expect(await pending.rows().map(\.geofenceId).contains("geo_new"))
        backlogRelease.continuation.yield()
        await tracking.value

        // The failed fresh row stays, attempted once: the flush excluded it.
        #expect(await pending.rows().map(\.geofenceId) == ["geo_new"])
        #expect(delivery.trackMetricReceivedInvocations.filter { $0.metric.geofenceId == "geo_new" }.count == 1)
    }

    @Test
    func trackTransition_givenBacklogFromEarlierFailure_expectBacklogReplayedOnCrossing() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        _ = await pending.append([PendingGeofenceMetric(
            geofenceId: "geo_old", transition: .exit,
            timestamp: Date(timeIntervalSince1970: 1),
            userId: "user_42", name: nil, transitionId: "txn_old"
        )])
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42"),
            eventBus: bus
        )

        await tracker.trackTransition(geofenceId: "geo_new", transition: .enter, occurredAt: crossedAt)

        // The crossing replays the backlog over EventBus, then delivers itself over HTTP.
        #expect(postedGeofenceEvents(from: bus).map(\.geofenceId) == ["geo_old"])
        #expect(delivery.trackMetricReceivedInvocations.map(\.metric.geofenceId) == ["geo_new"])
        #expect(await pending.rows().isEmpty)
    }

    @Test
    func trackTransition_givenAnonymousCrossingWithBacklog_expectBacklogStillReplayed() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        _ = await pending.append([PendingGeofenceMetric(
            geofenceId: "geo_old", transition: .exit,
            timestamp: Date(timeIntervalSince1970: 1),
            userId: "user_A", name: nil, transitionId: "txn_old"
        )])
        let delivery = GeofenceDeliveryTrackerMock()
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(),
            eventBus: bus
        )

        await tracker.trackTransition(geofenceId: "geo_new", transition: .enter, occurredAt: crossedAt)

        #expect(delivery.trackMetricCallsCount == 0)
        #expect(postedGeofenceEvents(from: bus).map(\.transitionId) == ["txn_old"])
        #expect(await pending.rows().isEmpty)
    }

    @Test
    func trackTransition_givenAnonymousCaptureThenIdentify_expectNoBackfill() async {
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

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)
        #expect(await pending.rows().isEmpty)
        #expect(postedGeofenceEvents(from: bus).isEmpty)

        contextStore.setUserId("user_42")
        await tracker.flushPending()

        #expect(delivery.trackMetricCallsCount == 0)
        #expect(postedGeofenceEvents(from: bus).isEmpty)
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

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)

        let queued = await pending.rows()
        #expect(queued.first?.userId == "user_A")
    }

    @Test
    func flushPending_givenRowStampedDifferentFromCurrent_expectPinnedUserIdOnEvent() async {
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
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: GeofenceDeliveryTrackerMock(),
            contextStore: makeContextStore(userId: "user_B"),
            eventBus: bus
        )

        await tracker.flushPending()

        #expect(postedGeofenceEvents(from: bus).first?.userId == "user_A")
    }

    @Test
    func flushPending_givenStampedUserId_andNoCurrent_expectEventCarriesStamped() async {
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
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: GeofenceDeliveryTrackerMock(),
            contextStore: makeContextStore(),
            eventBus: bus
        )

        await tracker.flushPending()

        #expect(postedGeofenceEvents(from: bus).first?.userId == "user_A")
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

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)

        #expect(await pending.rows().first?.name == "HQ")
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

        await tracker.trackTransition(geofenceId: "geo_unknown", transition: .enter, occurredAt: crossedAt)

        #expect(await pending.rows().first?.name == nil)
    }

    @Test
    func trackTransition_givenCachedGeofenceWithNoName_expectNilName() async {
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

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)

        #expect(await pending.rows().first?.name == nil)
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

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)

        #expect(await pending.rows().first?.metadata == ["category": .string("office")])
    }

    @Test
    func deliver_givenMetadataChangedAfterCapture_expectFreshMetadataSent() async {
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
        await priorTracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt) // snapshot gold, persisted

        await seedGeofence(storage, id: "geo_1", name: "HQ", metadata: ["tier": .string("platinum")])
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: storage, pendingStore: pending, deliveryTracker: GeofenceDeliveryTrackerMock(),
            contextStore: makeContextStore(userId: "user_42"), eventBus: bus
        )

        await tracker.flushPending()

        #expect(postedGeofenceEvents(from: bus).first?.metadata == ["tier": .string("platinum")])
    }

    @Test
    func deliver_givenGeofenceEvictedAfterCapture_expectSnapshotMetadataSent() async {
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
        await priorTracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)

        await storage.setCachedGeofences([]) // geofence evicted

        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: storage, pendingStore: pending, deliveryTracker: GeofenceDeliveryTrackerMock(),
            contextStore: makeContextStore(userId: "user_42"), eventBus: bus
        )

        await tracker.flushPending()

        #expect(postedGeofenceEvents(from: bus).first?.metadata == ["tier": .string("gold")])
    }

    @Test
    func deliver_givenNameChangedAfterCapture_expectFreshNameSent() async {
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
        await priorTracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)

        await seedGeofence(storage, id: "geo_1", name: "New HQ", metadata: [:])
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: storage, pendingStore: pending, deliveryTracker: GeofenceDeliveryTrackerMock(),
            contextStore: makeContextStore(userId: "user_42"), eventBus: bus
        )

        await tracker.flushPending()

        #expect(postedGeofenceEvents(from: bus).first?.name == "New HQ")
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

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)

        let metrics = delivery.trackMetricReceivedInvocations.map(\.metric)
        #expect(metrics.count == 2)
        #expect(Set(metrics.compactMap(\.geosetId)) == ["set_y", "set_z"]) // delivery order is not guaranteed (concurrent)
        #expect(metrics.allSatisfy { $0.geofenceId == "geo_1" })
        #expect(metrics.allSatisfy { $0.name == "HQ" })
        #expect(metrics.allSatisfy { $0.transition == .enter })
        // One physical crossing, so one transitionId.
        #expect(Set(metrics.map(\.transitionId)).count == 1)
        #expect(await pending.rows().isEmpty)
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

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)

        let metrics = delivery.trackMetricReceivedInvocations.map(\.metric)
        #expect(metrics.count == 1)
        #expect(metrics.first?.geosetId == nil)
    }

    @Test
    func trackTransition_givenBlankGeosetIds_expectSingleMetricWithoutGeosetId() async {
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

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)

        let metrics = delivery.trackMetricReceivedInvocations.map(\.metric)
        #expect(metrics.count == 1)
        #expect(metrics.first?.geosetId == nil)
    }

    @Test
    func trackTransition_givenDuplicateGeosetIds_expectOneEventPerDistinctGeoset() async {
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

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)

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

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)

        // The pending key includes geosetId, so the fan-out rows do not collide.
        let persisted = await pending.rows()
        #expect(persisted.count == 2)
        #expect(Set(persisted.compactMap(\.geosetId)) == ["set_y", "set_z"])
    }

    @Test
    func flushPending_givenTwoGeosetRows_expectOneEventBusEventPerGeoset() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await seedGeofence(storage, id: "geo_1", name: "HQ", geosetIds: ["set_y", "set_z"])
        let pending = makePendingStore(directory: dir)
        // Fail the fresh send so both rows persist for the flush.
        let failing = GeofenceDeliveryTrackerMock()
        failing.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.transport)) }
        let priorTracker = makeTracker(
            storage: storage, pendingStore: pending, deliveryTracker: failing,
            contextStore: makeContextStore(userId: "user_42")
        )
        await priorTracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)

        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: storage, pendingStore: pending,
            deliveryTracker: GeofenceDeliveryTrackerMock(),
            contextStore: makeContextStore(userId: "user_42"), eventBus: bus
        )

        await tracker.flushPending()

        #expect(await pending.rows().isEmpty)
        let posted = postedGeofenceEvents(from: bus)
        #expect(posted.count == 2)
        #expect(Set(posted.compactMap(\.geosetId)) == ["set_y", "set_z"]) // delivery order is not guaranteed (concurrent)
        #expect(posted.allSatisfy { $0.geofenceId == "geo_1" })
        #expect(Set(posted.map(\.transitionId)).count == 1)
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

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)
        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)

        // The cooldown gates the crossing before fan-out, so the second adds nothing.
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

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: crossedAt)

        #expect(runner.callCount.wrappedValue == 1)
        #expect(runner.events.wrappedValue == ["begin", "deliver", "end"])
    }

    @Test
    func flushPending_expectNoBackgroundTaskAndHandoffToEventBus() async {
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
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: GeofenceDeliveryTrackerMock(),
            contextStore: makeContextStore(userId: "user_42"),
            eventBus: bus,
            backgroundTaskRunner: runner
        )

        await tracker.flushPending()

        // DataPipeline owns delivery after the EventBus handoff, so no background task is taken.
        #expect(runner.callCount.wrappedValue == 0)
        #expect(postedGeofenceEvents(from: bus).count == 1)
        #expect(await pending.rows().isEmpty)
    }

    // MARK: - Crossing time

    /// A cdpApiKey routes the post-send flush over HTTP; an EventBus flush would drain the queue and
    /// mask the drop.
    @Test
    func trackTransition_givenTwoUsersAtTheSameCrossingTime_expectBothRowsDurable() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.transport)) }
        let occurredAt = Date(timeIntervalSince1970: 1700000000)
        let trackerA = makeTracker(
            storage: storage, pendingStore: pending, deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_A", cdpApiKey: "key_123")
        )
        let trackerB = makeTracker(
            storage: storage, pendingStore: pending, deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_B", cdpApiKey: "key_123")
        )

        await trackerA.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: occurredAt)
        await trackerB.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: occurredAt)

        // Keyed without userId, B's append would be a no-op and only A's row would remain.
        #expect(Set(await pending.rows().map(\.userId)) == ["user_A", "user_B"])
    }

    /// A never succeeds, so only a key collision with B's successful send can remove its row.
    @Test
    func trackTransition_givenAnotherUserSucceedsAtTheSameCrossingTime_expectTheQueuedRowKept() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let pending = makePendingStore(directory: dir)
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, userId, onComplete in
            onComplete(userId == "user_B" ? .success(()) : .failure(.transport))
        }
        let occurredAt = Date(timeIntervalSince1970: 1700000000)
        let trackerA = makeTracker(
            storage: storage, pendingStore: pending, deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_A", cdpApiKey: "key_123")
        )
        let trackerB = makeTracker(
            storage: storage, pendingStore: pending, deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_B", cdpApiKey: "key_123")
        )

        await trackerA.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: occurredAt)
        await trackerB.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: occurredAt)

        #expect(await pending.rows().map(\.userId) == ["user_A"])
    }

    @Test
    func trackTransition_givenACrossingBeforeTheSend_expectTheRowStampedWithTheCrossing() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let dateUtil = DateUtilStub()
        let sentAt = Date(timeIntervalSince1970: 1700000000)
        dateUtil.givenNow = sentAt
        let occurredAt = sentAt.addingTimeInterval(-90)
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: makePendingStore(directory: dir),
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42"),
            dateUtil: dateUtil
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: occurredAt)

        let sent = delivery.trackMetricReceivedInvocations.map(\.metric).first
        #expect(sent?.timestamp == occurredAt)
        #expect(sent?.timestamp != sentAt)
    }

    @Test
    func flushPending_givenAReplayedRow_expectTheCrossingTimeCarriedToEventBus() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.transport)) }
        let bus = EventBusHandlerMock()
        let dateUtil = DateUtilStub()
        let sentAt = Date(timeIntervalSince1970: 1700000000)
        dateUtil.givenNow = sentAt
        let occurredAt = sentAt.addingTimeInterval(-90)
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: makePendingStore(directory: dir),
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42"),
            eventBus: bus,
            dateUtil: dateUtil
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: occurredAt)
        dateUtil.givenNow = sentAt.addingTimeInterval(3600)
        await tracker.flushPending()

        #expect(postedGeofenceEvents(from: bus).first?.timestamp == occurredAt)
    }

    /// The cooldown runs on the wall clock, not the crossings' own timestamps.
    @Test
    func trackTransition_givenCrossingsAnHourApartDeliveredTogether_expectTheSecondSuppressed() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        let dateUtil = DateUtilStub()
        let sentAt = Date(timeIntervalSince1970: 1700000000)
        dateUtil.givenNow = sentAt
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: makePendingStore(directory: dir),
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42"),
            dateUtil: dateUtil
        )

        await tracker.trackTransition(
            geofenceId: "geo_1", transition: .enter, occurredAt: sentAt.addingTimeInterval(-2 * cooldownInterval)
        )
        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter, occurredAt: sentAt)

        #expect(delivery.trackMetricCallsCount == 1)
    }
}

/// `@unchecked Sendable`: all state is `Synchronized`.
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

/// Stands in for DataPipeline's live key registration ("initialized in this process").
private final class StubCdpApiKeyProvider: BackgroundDeliveryCdpApiKeyProvider {
    let cdpApiKey: String?
    init(cdpApiKey: String?) {
        self.cdpApiKey = cdpApiKey
    }
}
