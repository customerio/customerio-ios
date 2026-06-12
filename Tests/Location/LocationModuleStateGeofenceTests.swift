@testable import CioInternalCommon
@testable import CioLocation
import Foundation
import SharedTests
import Testing

/// Validates the geofence wiring contract of `LocationModuleState.setupGeofence`
/// without driving the full `performInitialization` path (which spins up
/// `CLLocationManager`, lifecycle observers, and other non-geofence side effects).
///
/// Each test owns the EventBus, coordinator spy, monitor mock, and storage.
/// `.serialized` because tests share `DIGraphShared.shared` overrides.
@Suite("LocationModuleState.setupGeofence", .serialized)
struct LocationModuleStateGeofenceTests {
    @Test
    @MainActor
    func setupGeofence_givenResetEventDelivered_expectCoordinatorResetCalled() async throws {
        let f = Fixture()
        defer { f.cleanup() }

        let (resetSignal, resetContinuation) = AsyncStream<Void>.makeStream()
        f.spyCoordinator.resetClosure = {
            resetContinuation.yield()
            return .success(())
        }

        f.wireGeofence()

        let deliver = try #require(f.bus.observers[ResetEvent.key], "ResetEvent observer must be registered")
        deliver(ResetEvent())

        var iter = resetSignal.makeAsyncIterator()
        _ = await iter.next()

        #expect(f.spyCoordinator.resetCallsCount == 1)
    }

    @Test
    @MainActor
    func setupGeofence_expectBothEventObserversRegistered() throws {
        let f = Fixture()
        defer { f.cleanup() }

        f.wireGeofence()

        #expect(f.bus.observers[ResetEvent.key] != nil, "ResetEvent observer must be registered")
        #expect(f.bus.observers[ProfileIdentifiedEvent.key] != nil, "ProfileIdentifiedEvent observer must be registered")
    }

    @Test
    @MainActor
    func setupGeofence_givenProfileIdentifiedEventWithCachedLocation_expectRefreshCalledWithAnchor() async throws {
        let f = Fixture(cachedLocation: LocationData(latitude: 12.34, longitude: 56.78))
        defer { f.cleanup() }

        let (refreshSignal, refreshContinuation) = AsyncStream<(Double, Double)>.makeStream()
        f.spyCoordinator.refreshClosure = { lat, lon in
            refreshContinuation.yield((lat, lon))
            return .success(())
        }

        f.wireGeofence()

        let deliver = try #require(f.bus.observers[ProfileIdentifiedEvent.key], "ProfileIdentifiedEvent observer must be registered")
        deliver(ProfileIdentifiedEvent(identifier: "u1"))

        var iter = refreshSignal.makeAsyncIterator()
        let received = await iter.next()

        #expect(received?.0 == 12.34)
        #expect(received?.1 == 56.78)
        #expect(f.spyCoordinator.refreshCallsCount == 1)
    }
}

/// Per-test setup: overrides the DI shared singleton with capturing/mocking deps,
/// builds a fresh `LocationModuleState`, and a real `LocationSyncCoordinator` over
/// an in-memory location store. Optionally seeds a cached location.
@MainActor
private struct Fixture {
    let di: DIGraphShared
    let bus: CapturingEventBusHandler
    let spyCoordinator: GeofenceSyncCoordinatorMock
    let mockMonitor: MockGeofenceRegionMonitor
    let tempDir: URL
    let state: LocationModuleState
    let locationCoordinator: LocationSyncCoordinator
    let lastLocationStorage: LastLocationStorageImpl

    init(cachedLocation: LocationData? = nil) {
        self.di = DIGraphShared.shared

        self.bus = CapturingEventBusHandler()
        di.override(value: bus as EventBusHandler, forType: EventBusHandler.self)

        self.spyCoordinator = GeofenceSyncCoordinatorMock()
        di.override(value: spyCoordinator as GeofenceSyncCoordinator, forType: GeofenceSyncCoordinator.self)

        self.mockMonitor = MockGeofenceRegionMonitor()
        di.override(value: mockMonitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)

        self.tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let testStorage = GeofenceStorage(fileManager: .default, directoryURL: tempDir)
        di.override(value: testStorage, forType: GeofenceStorage.self)

        self.lastLocationStorage = LastLocationStorageImpl(stateStore: InMemoryLastLocationStateStore())
        if let cached = cachedLocation {
            lastLocationStorage.setCachedLocation(cached)
        }
        self.locationCoordinator = LocationSyncCoordinator(
            storage: lastLocationStorage,
            filter: LocationFilter(storage: lastLocationStorage, dateUtil: DateUtilStub()),
            dataPipeline: nil,
            dateUtil: DateUtilStub(),
            logger: LoggerMock(),
            eventBusHandler: bus
        )
        self.state = LocationModuleState()
    }

    func wireGeofence(mode: LocationTrackingMode = .off) {
        state.setupGeofence(
            coordinator: locationCoordinator,
            lastLocationStorage: lastLocationStorage,
            lifecycleNotifying: NoOpAppLifecycleNotifying(),
            mode: mode,
            di: di
        )
    }

    func cleanup() {
        di.reset()
        try? FileManager.default.removeItem(at: tempDir)
    }
}

/// Captures registered observers so tests can deliver events synchronously
/// without spinning up the real `CioEventBusHandler` and its async operation
/// queue. Keyed by `EventRepresentable.key`.
private final class CapturingEventBusHandler: EventBusHandler, @unchecked Sendable {
    private(set) var observers: [String: (AnyEventRepresentable) -> Void] = [:]

    func addObserver<E: EventRepresentable>(_ eventType: E.Type, action: @escaping (E) -> Void) {
        observers[E.key] = { event in
            guard let typed = event as? E else { return }
            action(typed)
        }
    }

    func removeObserver<E: EventRepresentable>(for eventType: E.Type) {
        observers[E.key] = nil
    }

    func postEvent<E: EventRepresentable>(_ event: E) {}
    func postEventAndWait<E: EventRepresentable>(_ event: E) async {}
    func loadEventsFromStorage() async {}
    func removeFromStorage<E: EventRepresentable>(_ event: E) async {}
    func removeAllObservers() {}
}
