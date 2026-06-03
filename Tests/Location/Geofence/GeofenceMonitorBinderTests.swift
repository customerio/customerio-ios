@testable import CioInternalCommon
@testable import CioLocation
import Foundation
import SharedTests
import Testing

@Suite("GeofenceMonitorBinder")
@MainActor
struct GeofenceMonitorBinderTests {
    private func makeTracker(eventBusHandler: EventBusHandler) -> GeofenceEventTracker {
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
            pendingStore: PendingGeofenceMetricStore(),
            deliveryTracker: nil,
            contextStore: contextStore,
            eventBusHandler: eventBusHandler,
            dateUtil: DateUtilStub(),
            logger: LoggerMock()
        )
    }

    private func makeCoordinatorMock() -> GeofenceSyncCoordinatorMock {
        let mock = GeofenceSyncCoordinatorMock()
        mock.refreshReturnValue = .success(())
        mock.handleMovementReturnValue = .success(())
        return mock
    }

    /// Polls the fire-and-forget Task created inside the transition handler. Bounded by a
    /// finite iteration count so a regression doesn't hang the suite.
    private func awaitDispatch(_ condition: @autoclosure () -> Bool) async {
        for _ in 0 ..< 50 {
            if condition() { return }
            await Task.yield()
        }
    }

    @Test
    func bind_givenMovementTriggerExit_expectCoordinatorHandleMovementCalledWithLocation() async {
        let monitor = MockGeofenceRegionMonitor()
        let coordinator = makeCoordinatorMock()
        let eventBus = EventBusHandlerMock()
        let tracker = makeTracker(eventBusHandler: eventBus)

        GeofenceMonitorBinder.bind(monitor: monitor, tracker: tracker, coordinator: coordinator)
        monitor.simulateTransition(
            identifier: GeofenceConstants.movementTriggerIdentifier,
            transition: .exit,
            location: LocationData(latitude: 37.0, longitude: -122.0)
        )
        await awaitDispatch(coordinator.handleMovementCallsCount > 0)

        #expect(coordinator.handleMovementCallsCount == 1)
        #expect(coordinator.handleMovementReceivedArguments?.latitude == 37.0)
        #expect(coordinator.handleMovementReceivedArguments?.longitude == -122.0)
    }

    /// We only register the movement trigger for `.exit`; an unexpected `.enter` on the
    /// reserved identifier must NOT fall through to either the tracker or the coordinator.
    @Test
    func bind_givenMovementTriggerEnter_expectNeitherDispatchPathFires() async {
        let monitor = MockGeofenceRegionMonitor()
        let coordinator = makeCoordinatorMock()
        let eventBus = EventBusHandlerMock()
        let tracker = makeTracker(eventBusHandler: eventBus)

        GeofenceMonitorBinder.bind(monitor: monitor, tracker: tracker, coordinator: coordinator)
        monitor.simulateTransition(
            identifier: GeofenceConstants.movementTriggerIdentifier,
            transition: .enter,
            location: LocationData(latitude: 37.0, longitude: -122.0)
        )
        for _ in 0 ..< 10 { await Task.yield() }

        #expect(coordinator.handleMovementCallsCount == 0)
        #expect(eventBus.postEventCallsCount == 0)
    }

    /// Skip rather than guess at a location — `handleMovement` needs a real position to
    /// distance-compare against the API anchor.
    @Test
    func bind_givenMovementTriggerExitWithNilLocation_expectCoordinatorNotCalled() async {
        let monitor = MockGeofenceRegionMonitor()
        let coordinator = makeCoordinatorMock()
        let eventBus = EventBusHandlerMock()
        let tracker = makeTracker(eventBusHandler: eventBus)

        GeofenceMonitorBinder.bind(monitor: monitor, tracker: tracker, coordinator: coordinator)
        monitor.simulateTransition(
            identifier: GeofenceConstants.movementTriggerIdentifier,
            transition: .exit,
            location: nil
        )
        for _ in 0 ..< 10 { await Task.yield() }

        #expect(coordinator.handleMovementCallsCount == 0)
    }

    @Test
    func bind_givenBusinessGeofenceTransition_expectTrackerDispatchedAndCoordinatorIdle() async {
        let monitor = MockGeofenceRegionMonitor()
        let coordinator = makeCoordinatorMock()
        let eventBus = EventBusHandlerMock()
        let tracker = makeTracker(eventBusHandler: eventBus)

        GeofenceMonitorBinder.bind(monitor: monitor, tracker: tracker, coordinator: coordinator)
        monitor.simulateTransition(
            identifier: "business-region-1",
            transition: .enter,
            location: LocationData(latitude: 37.0, longitude: -122.0)
        )
        // With no deliveryTracker and a set userId, trackTransition posts a fallback event
        // on the EventBus — observable signal that the binder routed to the tracker.
        await awaitDispatch(eventBus.postEventCallsCount > 0)

        #expect(eventBus.postEventCallsCount == 1)
        #expect(coordinator.handleMovementCallsCount == 0)
    }
}
