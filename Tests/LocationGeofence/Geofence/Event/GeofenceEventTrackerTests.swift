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
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_42"),
            eventBus: bus
        )

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        // Fresh transition goes out over HTTP only — the EventBus channel is for replay.
        #expect(delivery.trackMetricCallsCount == 1)
        #expect(delivery.trackMetricReceivedArguments?.userId == "user_42")
        #expect(postedGeofenceEvents(from: bus).isEmpty)
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
        let canRetry = await storage.tryAcquireCooldown(key: "user_42:geo_1:enter", now: dateUtil.now, interval: cooldownInterval)
        #expect(canRetry)
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

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter) // fresh HTTP fails → row persists
        await tracker.flushPending() // replay hands the persisted row to EventBus

        // Fresh delivery goes out over HTTP; the replay over EventBus. Both carry the same
        // transitionId (minted at capture, reloaded from disk verbatim) so the server dedupes them.
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
    func trackTransition_givenDifferentUserWithinCooldown_expectNotSuppressed() async {
        // After A triggers a geofence, B (a fast re-login whose skipped sign-out cleanup left A's
        // cooldown state in shared storage) crossing the same geofence within the window must
        // not be suppressed.
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
        await trackerA.trackTransition(geofenceId: "geo_1", transition: .enter)
        #expect(delivery.trackMetricCallsCount == 1)

        // Same geofence, halfway through the cooldown window, but user B now.
        dateUtil.givenNow = baseTime.addingTimeInterval(cooldownInterval / 2)
        let trackerB = makeTracker(
            storage: storage,
            pendingStore: pending,
            deliveryTracker: delivery,
            contextStore: makeContextStore(userId: "user_B"),
            dateUtil: dateUtil
        )
        await trackerB.trackTransition(geofenceId: "geo_1", transition: .enter)

        #expect(delivery.trackMetricCallsCount == 2)
        #expect(delivery.trackMetricReceivedArguments?.userId == "user_B")

        // And the same user within the window stays suppressed.
        await trackerA.trackTransition(geofenceId: "geo_1", transition: .enter)
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
    func flushPending_givenNoHttpContext_expectPostedToEventBusAndDrained() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        // Rows from earlier failed sends, seeded directly — tracking a second transition would
        // itself replay the first row's backlog before the store could be inspected.
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
        #expect(await pending.loadAll().count == 2)

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

        // Without an HTTP context (no cdpApiKey), replay falls back to EventBus → DataPipeline.
        #expect(postedGeofenceEvents(from: bus).count == 2)
        #expect(delivery.trackMetricCallsCount == 0)
        #expect(await pending.loadAll().isEmpty)
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

        // Persisted key and no live DataPipeline = uninitialized cold-wake (the wrapper case):
        // replay ships over the direct channel instead of waiting for the next launch.
        #expect(Set(delivery.trackMetricReceivedInvocations.map(\.metric.geofenceId)) == ["geo_1", "geo_2"])
        #expect(postedGeofenceEvents(from: bus).isEmpty)
        #expect(await pending.loadAll().isEmpty)
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

        // An HTTP failure keeps the row queued for the next trigger; it must not silently switch
        // channels — EventBus is the no-context fallback, not the failure fallback.
        #expect(await pending.loadAll().count == 1)
        #expect(postedGeofenceEvents(from: bus).isEmpty)
    }

    @Test
    func flushPending_givenColdWakeRowStampedDifferentUser_expectStampedUserIdSent() async {
        // Same pinned-attribution contract the EventBus fallback has (tests below): a row captured
        // under user_A ships as user_A even though user_B is signed in at flush time.
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
        // With DataPipeline live in-process, replay hands off over EventBus — its durable queue
        // owns retry and batches the rows — even though a persisted key would allow direct HTTP.
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
        #expect(await pending.loadAll().isEmpty)
        // The store holds the provider weakly; keep it alive through the flush above.
        withExtendedLifetime(liveProvider) {}
    }

    @Test
    func trackTransition_givenColdWakeBacklog_expectBacklogShippedOverHttpWithCrossing() async {
        // The wrapper cold-wake story end-to-end: a crossing arrives with a backlog queued and no
        // DataPipeline — both the backlog row and the fresh crossing go out over direct HTTP.
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

        await tracker.trackTransition(geofenceId: "geo_new", transition: .enter)

        #expect(Set(delivery.trackMetricReceivedInvocations.map(\.metric.geofenceId)) == ["geo_old", "geo_new"])
        #expect(postedGeofenceEvents(from: bus).isEmpty)
        #expect(await pending.loadAll().isEmpty)
    }

    @Test
    func concurrentFlushPending_expectDrainedAndEachMetricPostedAtLeastOnce() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = makePendingStore(directory: dir)
        // Seeded directly for the same reason as the test above.
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

        // Fire two flushPending calls in parallel. Delivery is at-least-once by design: two flushes
        // reading the same snapshot may double-post a row (deduped downstream by transitionId).
        // Both metrics are delivered and the store is drained.
        async let flush1: Void = tracker.flushPending()
        async let flush2: Void = tracker.flushPending()
        _ = await(flush1, flush2)

        #expect(Set(postedGeofenceEvents(from: bus).map(\.geofenceId)) == ["geo_1", "geo_2"])
        #expect(await pending.loadAll().isEmpty)
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
        // Backlog row: signal when its send starts, then hold completion so the replay stays in
        // flight. Fresh row: fail, so its persisted row must survive on disk.
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

        let tracking = Task { await tracker.trackTransition(geofenceId: "geo_new", transition: .enter) }
        for await _ in backlogStarted.stream {
            break
        }
        // The replay is mid-flight; a suspension here must not lose the crossing — it is on disk.
        #expect(await pending.loadAll().map(\.geofenceId).contains("geo_new"))
        backlogRelease.continuation.yield()
        await tracking.value

        // Backlog delivered and removed; the failed fresh row stays for the next trigger, attempted
        // exactly once — the flush excluded it instead of re-sending on the same network.
        #expect(await pending.loadAll().map(\.geofenceId) == ["geo_new"])
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

        await tracker.trackTransition(geofenceId: "geo_new", transition: .enter)

        // The crossing replays the backlog over EventBus, then delivers itself over HTTP.
        #expect(postedGeofenceEvents(from: bus).map(\.geofenceId) == ["geo_old"])
        #expect(delivery.trackMetricReceivedInvocations.map(\.metric.geofenceId) == ["geo_new"])
        #expect(await pending.loadAll().isEmpty)
    }

    @Test
    func trackTransition_givenAnonymousCrossingWithBacklog_expectBacklogStillReplayed() async {
        // The backlog replay runs before the identified-only gate: queued rows carry their own
        // stamped userId, so a crossing the gate drops is still a wake-up worth using.
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

        await tracker.trackTransition(geofenceId: "geo_new", transition: .enter)

        // The anonymous crossing itself is dropped (no HTTP, nothing new queued)...
        #expect(delivery.trackMetricCallsCount == 0)
        // ...but the stamped backlog row still went out.
        #expect(postedGeofenceEvents(from: bus).map(\.transitionId) == ["txn_old"])
        #expect(await pending.loadAll().isEmpty)
    }

    @Test
    func trackTransition_givenAnonymousCaptureThenIdentify_expectNoBackfill() async {
        // Regression: an anonymous crossing is dropped at capture, so a later identify must NOT
        // backfill it — there is no persisted row to attribute to the newly-identified user.
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
        // Dropped at capture: nothing queued, nothing posted.
        #expect(await pending.loadAll().isEmpty)
        #expect(postedGeofenceEvents(from: bus).isEmpty)

        contextStore.setUserId("user_42")
        await tracker.flushPending()

        // Identify can't resurrect a crossing that was never persisted.
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

        await tracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        let queued = await pending.loadAll()
        #expect(queued.first?.userId == "user_A")
    }

    @Test
    func flushPending_givenRowStampedDifferentFromCurrent_expectPinnedUserIdOnEvent() async {
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
        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: makeStorage(directory: dir),
            pendingStore: pending,
            deliveryTracker: GeofenceDeliveryTrackerMock(),
            contextStore: makeContextStore(userId: "user_B"),
            eventBus: bus
        )

        await tracker.flushPending()

        // The event carries the snapshot userId so DataPipeline pins the track to user_A, not the
        // current user_B.
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
    func flushPending_givenTwoGeosetRows_expectOneEventBusEventPerGeoset() async {
        // The geoset fan-out survives the EventBus flush: two persisted rows → two posts, each with
        // its own geosetId, all sharing the crossing's transitionId.
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await seedGeofence(storage, id: "geo_1", name: "HQ", geosetIds: ["set_y", "set_z"])
        let pending = makePendingStore(directory: dir)
        // Fail the fresh HTTP send so both fan-out rows persist for the flush to replay.
        let failing = GeofenceDeliveryTrackerMock()
        failing.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.transport)) }
        let priorTracker = makeTracker(
            storage: storage, pendingStore: pending, deliveryTracker: failing,
            contextStore: makeContextStore(userId: "user_42")
        )
        await priorTracker.trackTransition(geofenceId: "geo_1", transition: .enter)

        let bus = EventBusHandlerMock()
        let tracker = makeTracker(
            storage: storage, pendingStore: pending,
            deliveryTracker: GeofenceDeliveryTrackerMock(),
            contextStore: makeContextStore(userId: "user_42"), eventBus: bus
        )

        await tracker.flushPending()

        #expect(await pending.loadAll().isEmpty)
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

        // The replay hands off to EventBus → DataPipeline, which owns delivery — so no background-task
        // assertion is taken (that is only for the fresh HTTP send). The row is posted and drained.
        #expect(runner.callCount.wrappedValue == 0)
        #expect(postedGeofenceEvents(from: bus).count == 1)
        #expect(await pending.loadAll().isEmpty)
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

/// Stands in for DataPipeline's live key registration, so tests can put the store into the
/// "initialized in this process" state.
private final class StubCdpApiKeyProvider: BackgroundDeliveryCdpApiKeyProvider {
    let cdpApiKey: String?
    init(cdpApiKey: String?) {
        self.cdpApiKey = cdpApiKey
    }
}
