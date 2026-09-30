@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import CoreLocation
import Foundation
import SharedTests
import Testing

@Suite("GeofenceMonitorBinder")
@MainActor
struct GeofenceMonitorBinderTests {
    private func makeTracker(deliveryTracker: GeofenceDeliveryTracker) -> GeofenceEventTracker {
        let contextStore = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        contextStore.setUserId("user-1")
        let storage = GeofenceStorage(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        return GeofenceEventTracker(
            storage: storage,
            pendingStore: PendingGeofenceMetricStore(logger: LoggerMock()),
            deliveryTracker: deliveryTracker,
            contextStore: contextStore,
            eventBusHandler: EventBusHandlerMock(),
            dateUtil: DateUtilStub(),
            logger: LoggerMock()
        )
    }

    /// The binder holds the resolver weakly; each test must keep a strong reference or dispatch
    /// never fires.
    private func makeResolver(
        tracker: GeofenceEventTracker,
        storage: GeofenceStorage = GeofenceStorage(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        ),
        logger: LoggerMock = LoggerMock(),
        contextStore: BackgroundDeliveryContextStore? = nil,
        fixResolver: MovementFixResolver? = nil
    ) -> PolygonMembershipResolver {
        PolygonMembershipResolver(
            storage: storage,
            transitionEmitter: tracker,
            logger: logger,
            contextStore: contextStore ?? BackgroundDeliveryContextStore(
                fileManager: .default,
                directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            ),
            fixResolver: fixResolver ?? MovementFixResolver(logger: LoggerMock()),
            // Not `.default`: one foregrounding starts a pass on every live resolver, and another
            // test's pass would short-circuit this one.
            notificationCenter: NotificationCenter()
        )
    }

    private func makeStorage() -> GeofenceStorage {
        GeofenceStorage(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
    }

    private func seedPolygon(in storage: GeofenceStorage) async {
        let ring = [
            LocationData(latitude: -0.0016, longitude: -0.0016),
            LocationData(latitude: -0.0016, longitude: 0.0016),
            LocationData(latitude: 0.0016, longitude: 0.0016),
            LocationData(latitude: 0.0016, longitude: -0.0016)
        ]
        await storage.setCachedGeofences([Geofence(
            id: "poly-1", latitude: 0, longitude: 0, radius: 300, name: nil,
            transitionTypes: [.enter, .exit], lastUpdated: Date(), vertices: ring
        )])
        await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: ["poly-1"])
    }

    private static var insideFix: CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date()
        )
    }

    private func makeContextStore(userId: String?) -> BackgroundDeliveryContextStore {
        let store = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        if let userId { store.setUserId(userId) }
        return store
    }

    private func makeCoordinatorMock() -> GeofenceSyncCoordinatorMock {
        let mock = GeofenceSyncCoordinatorMock()
        mock.refreshReturnValue = .success(())
        mock.handleMovementReturnValue = .success(())
        return mock
    }

    /// Yield-only isn't enough: polygon paths reach storage and a fix request first, and 50 yields
    /// pass almost instantly.
    private func awaitDispatch(_ condition: @autoclosure () -> Bool) async {
        for _ in 0 ..< 50 {
            if condition() { return }
            await Task.yield()
        }
        for _ in 0 ..< 200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10000000)
        }
    }

    private func makeDeliveryMock() -> GeofenceDeliveryTrackerMock {
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        return delivery
    }

    @Test
    func bind_givenMovementTriggerExit_expectCoordinatorHandleMovementCalledWithLocation() async {
        let monitor = MockGeofenceRegionMonitor()
        let coordinator = makeCoordinatorMock()
        let tracker = makeTracker(deliveryTracker: makeDeliveryMock())

        let resolver = makeResolver(tracker: tracker)
        GeofenceMonitorBinder.bind(monitor: monitor, resolver: resolver, coordinator: coordinator, logger: LoggerMock())
        monitor.simulateTransition(
            identifier: GeofenceConstants.movementTriggerIdentifier,
            transition: .exit,
            location: LocationData(latitude: 37.0, longitude: -122.0)
        )
        await awaitDispatch(coordinator.handleMovementCallsCount > 0)

        #expect(coordinator.handleMovementCallsCount == 1)
        #expect(coordinator.handleMovementReceivedArguments?.latitude == 37.0)
        #expect(coordinator.handleMovementReceivedArguments?.longitude == -122.0)
        #expect(coordinator.handleMovementReceivedArguments?.anchorIsLiveFix == true)
        // A trigger EXIT holds no resolved fix; the pass it starts requests its own.
        #expect(coordinator.handleMovementReceivedArguments?.heldFix == nil)
    }

    /// The coordinator sizes the wake circle from these coordinates, so staleness must survive the hop.
    @Test
    func bind_givenMovementTriggerExitOnStaleFix_expectAnchorNotReportedLive() async {
        let monitor = MockGeofenceRegionMonitor()
        let coordinator = makeCoordinatorMock()
        let tracker = makeTracker(deliveryTracker: makeDeliveryMock())

        let resolver = makeResolver(tracker: tracker)
        GeofenceMonitorBinder.bind(monitor: monitor, resolver: resolver, coordinator: coordinator, logger: LoggerMock())
        monitor.simulateTransition(
            identifier: GeofenceConstants.movementTriggerIdentifier,
            transition: .exit,
            location: LocationData(latitude: 37.0, longitude: -122.0),
            locationIsFresh: false
        )
        await awaitDispatch(coordinator.handleMovementCallsCount > 0)

        #expect(coordinator.handleMovementReceivedArguments?.anchorIsLiveFix == false)
    }

    @Test
    func bind_givenMovementTriggerEnter_expectNeitherDispatchPathFires() async {
        let monitor = MockGeofenceRegionMonitor()
        let coordinator = makeCoordinatorMock()
        let delivery = makeDeliveryMock()
        let tracker = makeTracker(deliveryTracker: delivery)

        let resolver = makeResolver(tracker: tracker)
        GeofenceMonitorBinder.bind(monitor: monitor, resolver: resolver, coordinator: coordinator, logger: LoggerMock())
        monitor.simulateTransition(
            identifier: GeofenceConstants.movementTriggerIdentifier,
            transition: .enter,
            location: LocationData(latitude: 37.0, longitude: -122.0)
        )
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        #expect(coordinator.handleMovementCallsCount == 0)
        #expect(delivery.trackMetricCallsCount == 0)
    }

    @Test
    func bind_givenMovementTriggerExitWithNilLocation_expectCoordinatorNotCalled() async {
        let monitor = MockGeofenceRegionMonitor()
        let coordinator = makeCoordinatorMock()
        let tracker = makeTracker(deliveryTracker: makeDeliveryMock())

        let resolver = makeResolver(tracker: tracker)
        GeofenceMonitorBinder.bind(monitor: monitor, resolver: resolver, coordinator: coordinator, logger: LoggerMock())
        monitor.simulateTransition(
            identifier: GeofenceConstants.movementTriggerIdentifier,
            transition: .exit,
            location: nil
        )
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        #expect(coordinator.handleMovementCallsCount == 0)
    }

    /// `refresh`, never `handleMovement`: the latter always re-registers, so crossings would re-arm
    /// the trigger continuously.
    @Test
    func bind_givenBusinessGeofenceTransition_expectTrackerDispatchedAndRefreshRequested() async {
        let monitor = MockGeofenceRegionMonitor()
        let coordinator = makeCoordinatorMock()
        let delivery = makeDeliveryMock()
        let tracker = makeTracker(deliveryTracker: delivery)

        let resolver = makeResolver(tracker: tracker)
        GeofenceMonitorBinder.bind(monitor: monitor, resolver: resolver, coordinator: coordinator, logger: LoggerMock())
        monitor.simulateTransition(
            identifier: "business-region-1",
            transition: .enter,
            location: LocationData(latitude: 37.0, longitude: -122.0),
            // Production value; the mock's `true` default would pass a binder that hardcoded it.
            locationIsFresh: false
        )
        await awaitDispatch(delivery.trackMetricCallsCount > 0)
        await awaitDispatch(coordinator.refreshCallsCount > 0)

        #expect(delivery.trackMetricCallsCount == 1)
        #expect(coordinator.handleMovementCallsCount == 0)
        #expect(coordinator.refreshCallsCount == 1)
        #expect(coordinator.refreshReceivedArguments?.latitude == 37.0)
        #expect(coordinator.refreshReceivedArguments?.longitude == -122.0)
        #expect(coordinator.refreshReceivedArguments?.anchorIsLiveFix == false)
    }

    /// A placeholder location would re-rank the whole set around the equator.
    @Test
    func bind_givenBusinessGeofenceTransitionWithoutLocation_expectNoRefresh() async {
        let monitor = MockGeofenceRegionMonitor()
        let coordinator = makeCoordinatorMock()
        let delivery = makeDeliveryMock()
        let tracker = makeTracker(deliveryTracker: delivery)

        let resolver = makeResolver(tracker: tracker)
        GeofenceMonitorBinder.bind(monitor: monitor, resolver: resolver, coordinator: coordinator, logger: LoggerMock())
        monitor.simulateTransition(identifier: "business-region-1", transition: .enter, location: nil)
        // Positive barrier first: a zero count before anything ran proves nothing.
        await awaitDispatch(delivery.trackMetricCallsCount > 0)
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        #expect(coordinator.refreshCallsCount == 0)
    }

    /// Also calling `refresh` would race `handleMovement` for the gate and one would be dropped.
    @Test
    func bind_givenMovementTriggerExit_expectRefreshNotAlsoRequested() async {
        let monitor = MockGeofenceRegionMonitor()
        let coordinator = makeCoordinatorMock()
        let tracker = makeTracker(deliveryTracker: makeDeliveryMock())

        let resolver = makeResolver(tracker: tracker)
        GeofenceMonitorBinder.bind(monitor: monitor, resolver: resolver, coordinator: coordinator, logger: LoggerMock())
        monitor.simulateTransition(
            identifier: GeofenceConstants.movementTriggerIdentifier,
            transition: .exit,
            location: LocationData(latitude: 37.0, longitude: -122.0)
        )
        await awaitDispatch(coordinator.handleMovementCallsCount > 0)
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        #expect(coordinator.handleMovementCallsCount == 1)
        #expect(coordinator.refreshCallsCount == 0)
    }

    /// The event's circle must survive the hop, or the resolver's staleness check never fires.
    @Test
    func bind_givenExitForAReplacedCircle_expectResolverRefusesIt() async {
        let monitor = MockGeofenceRegionMonitor()
        let delivery = makeDeliveryMock()
        let tracker = makeTracker(deliveryTracker: delivery)
        let storage = GeofenceStorage(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let ring = [
            LocationData(latitude: -0.0016, longitude: -0.0016),
            LocationData(latitude: -0.0016, longitude: 0.0016),
            LocationData(latitude: 0.0016, longitude: 0.0016)
        ]
        // Cached fence sits at the replacement's circle; the event names the one it replaced.
        await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: ["poly-1"])
        await storage.setCachedGeofences([Geofence(
            id: "poly-1", latitude: 0, longitude: 0.005, radius: 300, name: nil,
            transitionTypes: [.enter, .exit], lastUpdated: Date(), vertices: ring
        )])
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "poly-1")

        let resolver = makeResolver(tracker: tracker, storage: storage)
        GeofenceMonitorBinder.bind(monitor: monitor, resolver: resolver, coordinator: makeCoordinatorMock(), logger: LoggerMock())
        monitor.simulateTransition(
            identifier: "poly-1", transition: .exit, location: nil,
            eventCircle: .circle(MonitoredCircle(center: LocationData(latitude: 0, longitude: 0), radius: 300, maximumRadius: 1000))
        )
        await awaitDispatch(delivery.trackMetricCallsCount > 0)

        #expect(delivery.trackMetricCallsCount == 0)
        #expect(await storage.getPolygonMembership()["poly-1"]?.membership == .inside)
    }

    /// `handleMovement`, not `refresh`: `refresh` skips unless the device moved a full refresh
    /// radius, and a skip never touches the trigger.
    @Test
    func bind_givenPolygonCoveringCircleEnter_expectWakeReArmedNotJustRefreshed() async {
        let monitor = MockGeofenceRegionMonitor()
        let coordinator = makeCoordinatorMock()
        let tracker = makeTracker(deliveryTracker: makeDeliveryMock())
        let storage = makeStorage()
        await seedPolygon(in: storage)

        let resolver = makeResolver(tracker: tracker, storage: storage)
        resolver.fixResolver.requestFreshFix = { [weak resolver] in
            resolver?.fixResolver.handleResolvedFix(Self.insideFix)
        }
        GeofenceMonitorBinder.bind(monitor: monitor, resolver: resolver, coordinator: coordinator, logger: LoggerMock())
        monitor.simulateTransition(
            identifier: "poly-1", transition: .enter,
            location: LocationData(latitude: 37.0, longitude: -122.0),
            eventCircle: .circle(MonitoredCircle(center: .init(latitude: 0, longitude: 0), radius: 300, maximumRadius: 1000))
        )
        await awaitDispatch(coordinator.handleMovementCallsCount > 0)

        #expect(coordinator.handleMovementCallsCount == 1)
    }

    /// Business events carry `locationIsFresh == false`, which would widen the trigger to the full
    /// refresh radius.
    @Test
    func bind_givenPolygonCoveringCircleEnter_expectTheResolversFixNotTheCallbacks() async {
        let monitor = MockGeofenceRegionMonitor()
        let coordinator = makeCoordinatorMock()
        let tracker = makeTracker(deliveryTracker: makeDeliveryMock())
        let storage = makeStorage()
        await seedPolygon(in: storage)

        let resolver = makeResolver(tracker: tracker, storage: storage)
        resolver.fixResolver.requestFreshFix = { [weak resolver] in
            resolver?.fixResolver.handleResolvedFix(Self.insideFix)
        }
        GeofenceMonitorBinder.bind(monitor: monitor, resolver: resolver, coordinator: coordinator, logger: LoggerMock())
        monitor.simulateTransition(
            identifier: "poly-1", transition: .enter,
            // Deliberately far from the fix, so reading the wrong one is visible.
            location: LocationData(latitude: 37.0, longitude: -122.0),
            eventCircle: .circle(MonitoredCircle(center: .init(latitude: 0, longitude: 0), radius: 300, maximumRadius: 1000))
        )
        await awaitDispatch(coordinator.handleMovementCallsCount > 0)

        let arguments = coordinator.handleMovementReceivedArguments
        #expect(arguments?.latitude == Self.insideFix.coordinate.latitude)
        #expect(arguments?.longitude == Self.insideFix.coordinate.longitude)
        #expect(arguments?.anchorIsLiveFix == true)
    }

    /// The membership pass needs a fix newer than the resolver's last (the entry's own); left to
    /// request one, every polygon records `no_usable_fix`.
    @Test
    func bind_givenPolygonCoveringCircleEnter_expectTheResolvedFixTravelsToTheReArm() async {
        let monitor = MockGeofenceRegionMonitor()
        let coordinator = makeCoordinatorMock()
        let tracker = makeTracker(deliveryTracker: makeDeliveryMock())
        let storage = makeStorage()
        await seedPolygon(in: storage)

        // Captured once: `insideFix` builds a new location, and a new timestamp, on every read.
        let resolved = Self.insideFix
        let resolver = makeResolver(tracker: tracker, storage: storage)
        resolver.fixResolver.requestFreshFix = { [weak resolver] in
            resolver?.fixResolver.handleResolvedFix(resolved)
        }
        GeofenceMonitorBinder.bind(monitor: monitor, resolver: resolver, coordinator: coordinator, logger: LoggerMock())
        monitor.simulateTransition(
            identifier: "poly-1", transition: .enter,
            location: LocationData(latitude: 37.0, longitude: -122.0),
            eventCircle: .circle(MonitoredCircle(center: .init(latitude: 0, longitude: 0), radius: 300, maximumRadius: 1000))
        )
        await awaitDispatch(coordinator.handleMovementCallsCount > 0)

        let held = coordinator.handleMovementReceivedArguments?.heldFix
        #expect(held?.latitude == resolved.coordinate.latitude)
        #expect(held?.longitude == resolved.coordinate.longitude)
        #expect(held?.horizontalAccuracy == resolved.horizontalAccuracy)
        #expect(held?.timestamp == resolved.timestamp)
    }

    @Test
    func bind_givenPolygonEnterWithNoUsableFix_expectRefreshNotReArm() async {
        let monitor = MockGeofenceRegionMonitor()
        let coordinator = makeCoordinatorMock()
        let tracker = makeTracker(deliveryTracker: makeDeliveryMock())
        let storage = makeStorage()
        await seedPolygon(in: storage)

        let resolver = makeResolver(tracker: tracker, storage: storage)
        // Requested and never answered: the resolver times out and reports no usable fix.
        resolver.fixResolver.requestFreshFix = { [weak resolver] in
            resolver?.fixResolver.handleRequestFailure()
        }
        GeofenceMonitorBinder.bind(monitor: monitor, resolver: resolver, coordinator: coordinator, logger: LoggerMock())
        monitor.simulateTransition(
            identifier: "poly-1", transition: .enter,
            location: LocationData(latitude: 37.0, longitude: -122.0),
            eventCircle: .circle(MonitoredCircle(center: .init(latitude: 0, longitude: 0), radius: 300, maximumRadius: 1000))
        )
        await awaitDispatch(coordinator.refreshCallsCount > 0)

        #expect(coordinator.handleMovementCallsCount == 0)
        #expect(coordinator.refreshCallsCount == 1)
    }

    /// Re-arming on EXIT would tighten the trigger around a venue being left.
    @Test
    func bind_givenPolygonCoveringCircleExit_expectRefreshNotReArm() async {
        let monitor = MockGeofenceRegionMonitor()
        let coordinator = makeCoordinatorMock()
        let tracker = makeTracker(deliveryTracker: makeDeliveryMock())
        let storage = makeStorage()
        await seedPolygon(in: storage)

        let resolver = makeResolver(tracker: tracker, storage: storage)
        GeofenceMonitorBinder.bind(monitor: monitor, resolver: resolver, coordinator: coordinator, logger: LoggerMock())
        monitor.simulateTransition(
            identifier: "poly-1", transition: .exit,
            location: LocationData(latitude: 37.0, longitude: -122.0),
            eventCircle: .circle(MonitoredCircle(center: .init(latitude: 0, longitude: 0), radius: 300, maximumRadius: 1000))
        )
        await awaitDispatch(coordinator.refreshCallsCount > 0)

        #expect(coordinator.handleMovementCallsCount == 0)
        #expect(coordinator.refreshCallsCount == 1)
    }

    /// `handleMovement` never refetches on age, so re-arming alone would leave an expired catalog
    /// stale.
    @Test
    func bind_givenPolygonCoveringCircleEnter_expectCatalogStillRefreshed() async {
        let monitor = MockGeofenceRegionMonitor()
        let coordinator = makeCoordinatorMock()
        let tracker = makeTracker(deliveryTracker: makeDeliveryMock())
        let storage = makeStorage()
        await seedPolygon(in: storage)

        let resolver = makeResolver(tracker: tracker, storage: storage)
        resolver.fixResolver.requestFreshFix = { [weak resolver] in
            resolver?.fixResolver.handleResolvedFix(Self.insideFix)
        }
        GeofenceMonitorBinder.bind(monitor: monitor, resolver: resolver, coordinator: coordinator, logger: LoggerMock())
        monitor.simulateTransition(
            identifier: "poly-1", transition: .enter,
            location: LocationData(latitude: 37.0, longitude: -122.0),
            eventCircle: .circle(MonitoredCircle(center: .init(latitude: 0, longitude: 0), radius: 300, maximumRadius: 1000))
        )
        await awaitDispatch(coordinator.refreshCallsCount > 0)

        #expect(coordinator.handleMovementCallsCount == 1)
        #expect(coordinator.refreshCallsCount == 1)
        // Both anchored on the resolver's fix, for the same reason the re-arm is.
        #expect(coordinator.refreshReceivedArguments?.latitude == Self.insideFix.coordinate.latitude)
        #expect(coordinator.refreshReceivedArguments?.anchorIsLiveFix == true)
    }

    // MARK: - Visit wake

    /// No polygon is seeded, so assert on the pass record: its start is logged before the empty guard.
    @Test
    func bindVisits_givenAnIdentifiedUser_expectAPolygonPassAndStaysArmed() async {
        let visitMonitor = MockGeofenceVisitMonitor()
        let logger = LoggerMock()
        let contextStore = makeContextStore(userId: "user-1")
        let tracker = makeTracker(deliveryTracker: makeDeliveryMock())
        let resolver = makeResolver(tracker: tracker, logger: logger, contextStore: contextStore)

        let passFinished = AsyncSignal()
        GeofenceMonitorBinder.bindVisits(
            visitMonitor: visitMonitor, resolver: resolver, contextStore: contextStore,
            backgroundTaskRunner: SignalingBackgroundTaskRunner(finished: passFinished)
        )
        let stayArmed = visitMonitor.simulateVisit()
        await passFinished.wait()

        #expect(stayArmed == true)
        #expect(logger.debugReceivedInvocations.contains { $0.message.contains("(visit)") })
        // `bindVisits` holds the resolver weakly; without this, ARC can release it before the pass.
        withExtendedLifetime(resolver) {}
    }

    /// A cached fix predates the arrival; here it's outside the ring while the device is inside.
    @Test
    func bindVisits_givenACachedFixFromBeforeTheArrival_expectTheCurrentFixRequested() async {
        let storage = makeStorage()
        await seedPolygon(in: storage)
        let contextStore = makeContextStore(userId: "user-1")
        let fixResolver = MovementFixResolver(logger: LoggerMock())
        fixResolver.systemCachedFix = {
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 0.02, longitude: 0.02),
                altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                timestamp: Date().addingTimeInterval(-5)
            )
        }
        // Only a forced request reaches this.
        fixResolver.requestFreshFix = { [weak fixResolver] in
            fixResolver?.handleResolvedFix(Self.insideFix)
        }
        let resolver = makeResolver(
            tracker: makeTracker(deliveryTracker: makeDeliveryMock()), storage: storage,
            contextStore: contextStore, fixResolver: fixResolver
        )
        let visitMonitor = MockGeofenceVisitMonitor()

        let passFinished = AsyncSignal()
        GeofenceMonitorBinder.bindVisits(
            visitMonitor: visitMonitor, resolver: resolver, contextStore: contextStore,
            backgroundTaskRunner: SignalingBackgroundTaskRunner(finished: passFinished)
        )
        _ = visitMonitor.simulateVisit()
        await passFinished.wait()

        #expect(await storage.getPolygonMembership()["poly-1"]?.membership == .inside)
        withExtendedLifetime(resolver) {}
    }

    @Test
    func bindVisits_givenNoIdentifiedUser_expectNoPassAndRefusal() async {
        let visitMonitor = MockGeofenceVisitMonitor()
        let logger = LoggerMock()
        let contextStore = makeContextStore(userId: nil)
        let tracker = makeTracker(deliveryTracker: makeDeliveryMock())
        let resolver = makeResolver(tracker: tracker, logger: logger, contextStore: contextStore)

        GeofenceMonitorBinder.bindVisits(
            visitMonitor: visitMonitor, resolver: resolver, contextStore: contextStore,
            backgroundTaskRunner: NoBackgroundTaskRunner()
        )
        let stayArmed = visitMonitor.simulateVisit()
        // Fixed wait, not a poll: an absence cannot be polled for.
        try? await Task.sleep(nanoseconds: 300000000)

        #expect(stayArmed == false)
        #expect(!logger.debugReceivedInvocations.contains { $0.message.contains("(visit)") })
    }

    @Test
    func bindVisits_givenADeparture_expectAPolygonPassToo() async {
        let visitMonitor = MockGeofenceVisitMonitor()
        let logger = LoggerMock()
        let contextStore = makeContextStore(userId: "user-1")
        let tracker = makeTracker(deliveryTracker: makeDeliveryMock())
        let resolver = makeResolver(tracker: tracker, logger: logger, contextStore: contextStore)

        let passFinished = AsyncSignal()
        GeofenceMonitorBinder.bindVisits(
            visitMonitor: visitMonitor, resolver: resolver, contextStore: contextStore,
            backgroundTaskRunner: SignalingBackgroundTaskRunner(finished: passFinished)
        )
        let stayArmed = visitMonitor.simulateVisit(isArrival: false)
        await passFinished.wait()

        #expect(stayArmed == true)
        #expect(logger.debugReceivedInvocations.contains { $0.message.contains("(visit)") })
        withExtendedLifetime(resolver) {}
    }
}

/// `bindVisits` runs the pass in an unhandled `Task`, and a deadline on main-actor work flakes under
/// parallel suites.
private struct SignalingBackgroundTaskRunner: BackgroundTaskRunner {
    let finished: AsyncSignal

    func withBackgroundTime(_ work: @Sendable () async -> Void) async {
        await work()
        await finished.fire()
    }
}

private actor AsyncSignal {
    private var continuation: CheckedContinuation<Void, Never>?
    private var fired = false

    func wait() async {
        if fired { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func fire() {
        fired = true
        continuation?.resume()
        continuation = nil
    }
}
