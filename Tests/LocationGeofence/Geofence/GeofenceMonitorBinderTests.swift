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
        )
    ) -> PolygonMembershipResolver {
        PolygonMembershipResolver(
            storage: storage,
            transitionEmitter: tracker,
            logger: LoggerMock(),
            contextStore: BackgroundDeliveryContextStore(
                fileManager: .default,
                directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            )
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

    private func makeCoordinatorMock() -> GeofenceSyncCoordinatorMock {
        let mock = GeofenceSyncCoordinatorMock()
        mock.refreshReturnValue = .success(())
        mock.handleMovementReturnValue = .success(())
        return mock
    }

    /// Polls the fire-and-forget Task created inside the transition handler. Bounded so a
    /// regression doesn't hang the suite.
    ///
    /// Yields first, which settles the short paths in microseconds, then falls back to sleeping.
    /// Yield-only is not enough: the polygon paths reach storage and a fix request before the
    /// coordinator is touched, and 50 yields elapse almost instantly when this suite runs on its
    /// own. Measured — the polygon enter tests passed only while the resolver suite ran alongside
    /// them and failed 3/3 when this suite ran alone, so a yield-only wait makes the result depend
    /// on which OTHER tests happen to be running.
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

    /// We only register the movement trigger for `.exit`; an unexpected `.enter` on the
    /// reserved identifier must NOT fall through to either the tracker or the coordinator.
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
            location: LocationData(latitude: 37.0, longitude: -122.0)
        )
        // Tracker dispatch is observable via the delivery mock's call count.
        await awaitDispatch(delivery.trackMetricCallsCount > 0)
        await awaitDispatch(coordinator.refreshCallsCount > 0)

        #expect(delivery.trackMetricCallsCount == 1)
        #expect(coordinator.handleMovementCallsCount == 0)
        #expect(coordinator.refreshCallsCount == 1)
        #expect(coordinator.refreshReceivedArguments?.latitude == 37.0)
        #expect(coordinator.refreshReceivedArguments?.longitude == -122.0)
    }

    /// The refresh anchors on the crossing's own coordinates, so without one there is nothing to
    /// anchor to. Returning early is correct; passing a placeholder would re-rank the whole set
    /// around the equator.
    @Test
    func bind_givenBusinessGeofenceTransitionWithoutLocation_expectNoRefresh() async {
        let monitor = MockGeofenceRegionMonitor()
        let coordinator = makeCoordinatorMock()
        let tracker = makeTracker(deliveryTracker: makeDeliveryMock())

        let resolver = makeResolver(tracker: tracker)
        GeofenceMonitorBinder.bind(monitor: monitor, resolver: resolver, coordinator: coordinator, logger: LoggerMock())
        monitor.simulateTransition(identifier: "business-region-1", transition: .enter, location: nil)
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        #expect(coordinator.refreshCallsCount == 0)
    }

    /// The trigger EXIT already refreshes through `handleMovement`. If it ALSO reached `refresh`
    /// the two would race for the same gate and one would be dropped as `alreadyInProgress` —
    /// which is exactly the lost refresh this change exists to prevent.
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

    /// The dead-zone fix. Entering a polygon's covering circle leaves the device beside a boundary
    /// the OS cannot report, and the wake is sized only at registration time — so the crossing that
    /// usually follows within minutes has nothing to wake it. Measured in the field: a circle entry
    /// 45 m from the ring, then 11 minutes of silence.
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
        #expect(coordinator.refreshCallsCount == 0)
    }

    /// The re-arm must be sized against the fix the membership pass obtained, NOT the crossing's
    /// own coordinates. Business events dispatch with `locationIsFresh == false` on both monitor
    /// paths, and the coordinator widens the trigger to the full refresh radius for any anchor that
    /// is not a live fix — so passing the callback's location through would install the widest
    /// possible wake in the one case that needs the tightest, and the test would still be green.
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
        // The whole point: a non-live anchor makes the coordinator widen the trigger to maximum.
        #expect(arguments?.anchorIsLiveFix == true)
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
}
