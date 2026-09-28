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

    /// The binder holds the resolver weakly (the production instance is a DI singleton), so every
    /// test must keep its own strong reference or the dispatch silently never fires.
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
            // Private centre, not `.default`: the resolver subscribes to `willEnterForeground`,
            // and one foregrounding starts a pass on every live resolver in the process. An
            // unrelated test's pass then holds `passesInFlight`, and the pass under test takes the
            // already-running short-circuit and logs nothing.
            notificationCenter: NotificationCenter()
        )
    }

    private func makeStorage() -> GeofenceStorage {
        GeofenceStorage(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
    }

    /// A registered polygon at the origin with a ring the fix below sits inside, so the enter path
    /// reaches the membership pass rather than being refused as unbuildable or unregistered.
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

    /// Accuracy well inside the venue scale and a current timestamp, so the gate can decide and
    /// the freshness check passes.
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

    /// Polls the fire-and-forget Task created inside the transition handler, bounded so a
    /// regression doesn't hang the suite.
    ///
    /// Yields first for the short paths, then sleeps. Yield-only is not enough: the polygon paths
    /// reach storage and a fix request before the coordinator, and 50 yields elapse almost
    /// instantly when this suite runs alone.
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

    /// A movement pass whose fresh-fix request failed carries the cached fix that prompted it. The
    /// coordinator sizes the wake circle from these coordinates, so the staleness has to survive the
    /// hop rather than being assumed away because it is the movement path.
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

    /// The movement trigger registers `.exit` only; a stray `.enter` must reach neither the tracker
    /// nor the coordinator.
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

    /// Skip rather than guess at a location — `handleMovement` needs a real position to
    /// distance-compare against the API anchor.
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

    /// The crossing must reach the tracker AND ask the coordinator to reconsider freshness. It is
    /// `refresh`, never `handleMovement`: the latter assumes an EXIT happened and always
    /// re-registers, so routing crossings through it would re-arm the trigger continuously.
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
            // The production value on both monitors. The mock defaults to true, which would let a
            // binder that hardcoded `anchorIsLiveFix: true` pass.
            locationIsFresh: false
        )
        await awaitDispatch(delivery.trackMetricCallsCount > 0)
        await awaitDispatch(coordinator.refreshCallsCount > 0)

        #expect(delivery.trackMetricCallsCount == 1)
        #expect(coordinator.handleMovementCallsCount == 0)
        #expect(coordinator.refreshCallsCount == 1)
        #expect(coordinator.refreshReceivedArguments?.latitude == 37.0)
        #expect(coordinator.refreshReceivedArguments?.longitude == -122.0)
        // Decides the trigger radius.
        #expect(coordinator.refreshReceivedArguments?.anchorIsLiveFix == false)
    }

    /// The refresh anchors on the crossing's own coordinates. A placeholder would re-rank the whole
    /// set around the equator.
    @Test
    func bind_givenBusinessGeofenceTransitionWithoutLocation_expectNoRefresh() async {
        let monitor = MockGeofenceRegionMonitor()
        let coordinator = makeCoordinatorMock()
        let delivery = makeDeliveryMock()
        let tracker = makeTracker(deliveryTracker: delivery)

        let resolver = makeResolver(tracker: tracker)
        GeofenceMonitorBinder.bind(monitor: monitor, resolver: resolver, coordinator: coordinator, logger: LoggerMock())
        monitor.simulateTransition(identifier: "business-region-1", transition: .enter, location: nil)
        // A positive barrier from the same handler first: a zero count before anything ran
        // proves nothing.
        await awaitDispatch(delivery.trackMetricCallsCount > 0)
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        #expect(coordinator.refreshCallsCount == 0)
    }

    /// The trigger EXIT already refreshes through `handleMovement`. Also calling `refresh` would
    /// race for the same gate, and one would be dropped as `alreadyInProgress`.
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

    /// The circle an event was raised for has to survive the binder hop, or the resolver's
    /// staleness check is fed nil on every real crossing and silently never fires.
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

    /// Entering a polygon's covering circle leaves the device beside a boundary the OS cannot
    /// report, and the wake is sized only at registration, so the crossing that usually follows has
    /// nothing to wake it.
    ///
    /// `handleMovement`, not `refresh`: `refresh` answers `.skip` unless the device moved a full
    /// refresh radius from the last registration centre, and `.skip` never touches the trigger.
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

    /// The re-arm is sized against the membership pass's fix, not the crossing's coordinates.
    /// Business events carry `locationIsFresh == false`, and the coordinator widens the trigger to
    /// the full refresh radius for a non-live anchor: the widest wake where the tightest is needed.
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

    /// The re-arm's membership pass demands a fix strictly newer than the resolver's last, which is
    /// the entry's own. Left to request one, every polygon records `no_usable_fix`.
    ///
    /// Asserted on the argument because the pass runs inside the coordinator, mocked here.
    /// Accuracy and timestamp are checked too: membership judges against both.
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

    /// No fix means nothing to size a trigger with, so the crossing falls back to the plain
    /// catalog refresh rather than re-arming on coordinates it does not trust.
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

    /// A polygon EXIT puts the boundary behind us and the next registration re-sizes from wherever
    /// the device then is. Re-arming here would tighten the trigger around a venue being left.
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

    /// `handleMovement` refetches on distance and on a missing anchor, never on age, so re-arming
    /// alone would leave a time-expired catalog stale on a circle entry made without moving a
    /// refetch radius.
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

    /// The in-circle dead zone has no edge to cross, so only a re-evaluation can notice the device
    /// is inside a polygon. A visit has to start one.
    ///
    /// Asserted on the pass record: no polygon is seeded, so the pass decides nothing, but its
    /// start is logged before the empty guard.
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
        // `bindVisits` holds the resolver weakly; without this ARC can release it and the pass
        // never runs.
        withExtendedLifetime(resolver) {}
    }

    /// A visit reports that the device arrived, so any cached fix predates the arrival. Here the
    /// cached fix is five seconds old and outside the ring while the device is inside it: the pass
    /// has to ask.
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

    /// Signed out, the handler's `false` is what disarms monitoring. The monitor acting on it is
    /// covered in `GeofenceVisitMonitorTests`.
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

    /// A departure is as good a reason to re-judge membership as an arrival.
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

/// Lets a visit test await the pass instead of polling for it. `bindVisits` runs the pass in a
/// `Task` with no handle, and a deadline on `@MainActor` work fails whenever parallel suites keep
/// the main actor busy past it.
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
