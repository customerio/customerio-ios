@testable import CioInternalCommon
@_spi(Internal) import CioLocation
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import CoreLocation
import Foundation
import SharedTests
import Testing

/// Validates the geofence wiring contract of `GeofenceModuleState.setup` without driving the
/// full module `initialize()` path (which spins up `CLLocationManager`, lifecycle observers,
/// and other side effects).
///
/// Each test owns a private `DIGraphShared` instance (EventBus, coordinator spy, monitor mock,
/// storage, stub `LocationServices`), so a fire-and-forget refresh `Task` can never resolve a
/// dependency another suite swapped on the shared graph. `.serialized` to keep ordering stable.
@Suite("GeofenceModuleState.setup", .serialized)
struct GeofenceModuleSetupTests {
    @Test
    @MainActor
    func setup_givenResetEventDelivered_expectCoordinatorResetCalled() async throws {
        let f = Fixture()
        defer { f.cleanup() }

        let (resetSignal, resetContinuation) = AsyncStream<Void>.makeStream()
        f.spyCoordinator.resetClosure = {
            resetContinuation.yield()
            return .success(())
        }

        f.wire()

        let deliver = try #require(f.bus.observers[ResetEvent.key], "ResetEvent observer must be registered")
        deliver(ResetEvent())

        var iter = resetSignal.makeAsyncIterator()
        _ = await iter.next()

        #expect(f.spyCoordinator.resetCallsCount == 1)
    }

    @Test
    @MainActor
    func setup_expectEventObserversRegistered() throws {
        let f = Fixture()
        defer { f.cleanup() }

        f.wire()

        #expect(f.bus.observers[ResetEvent.key] != nil, "ResetEvent observer must be registered")
        #expect(f.bus.observers[ProfileIdentifiedEvent.key] != nil, "ProfileIdentifiedEvent observer must be registered")
        #expect(f.bus.observers[LocationAcquiredEvent.key] != nil, "LocationAcquiredEvent observer must be registered")
    }

    @Test
    @MainActor
    func setup_givenProfileIdentifiedEventWithCachedLocation_expectRefreshCalledWithAnchor() async throws {
        let f = Fixture(cachedLocation: LocationData(latitude: 12.34, longitude: 56.78))
        defer { f.cleanup() }

        let (refreshSignal, refreshContinuation) = AsyncStream<(Double, Double)>.makeStream()
        f.spyCoordinator.refreshClosure = { lat, lon in
            refreshContinuation.yield((lat, lon))
            return .success(())
        }

        f.wire()

        let deliver = try #require(f.bus.observers[ProfileIdentifiedEvent.key], "ProfileIdentifiedEvent observer must be registered")
        deliver(ProfileIdentifiedEvent(identifier: "u1"))

        var iter = refreshSignal.makeAsyncIterator()
        let received = await iter.next()

        #expect(received?.0 == 12.34)
        #expect(received?.1 == 56.78)
        #expect(f.spyCoordinator.refreshCallsCount == 1)
    }

    @Test
    @MainActor
    func setup_givenProfileIdentifiedEventWithRegistrationCenter_expectRefreshAnchoredThereNotCache() async throws {
        // A movement-walked registration center exists. It must win over the Location cache, which
        // movement never updates and is stale on relaunch — anchoring there would clobber the good
        // registration with a far-away ranking.
        let f = Fixture(cachedLocation: LocationData(latitude: 12.34, longitude: 56.78))
        defer { f.cleanup() }

        await f.di.geofenceStorage.recordRegistration(center: LocationData(latitude: 10, longitude: 20), businessIds: ["g1"])

        let (refreshSignal, refreshContinuation) = AsyncStream<(Double, Double)>.makeStream()
        f.spyCoordinator.refreshClosure = { lat, lon in
            refreshContinuation.yield((lat, lon))
            return .success(())
        }

        f.wire()

        let deliver = try #require(f.bus.observers[ProfileIdentifiedEvent.key], "ProfileIdentifiedEvent observer must be registered")
        deliver(ProfileIdentifiedEvent(identifier: "u1"))

        var iter = refreshSignal.makeAsyncIterator()
        let received = await iter.next()

        #expect(received?.0 == 10)
        #expect(received?.1 == 20)
    }
}

/// Per-test setup: overrides the DI shared singleton with capturing/mocking deps and builds
/// a fresh `GeofenceModuleState` with a no-op lifecycle notifier and a stub `LocationServices`.
@MainActor
private struct Fixture {
    let di: DIGraphShared
    let bus: CapturingEventBusHandler
    let spyCoordinator: GeofenceSyncCoordinatorMock
    let mockMonitor: MockGeofenceRegionMonitor
    let tempDir: URL
    let state: GeofenceModuleState

    init(cachedLocation: LocationData? = nil) {
        self.di = DIGraphShared()

        self.bus = CapturingEventBusHandler()
        di.override(value: bus as EventBusHandler, forType: EventBusHandler.self)

        self.spyCoordinator = GeofenceSyncCoordinatorMock()
        di.override(value: spyCoordinator as GeofenceSyncCoordinator, forType: GeofenceSyncCoordinator.self)

        self.mockMonitor = MockGeofenceRegionMonitor()
        di.override(value: mockMonitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)

        self.tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let testStorage = GeofenceStorage(fileManager: .default, directoryURL: tempDir)
        di.override(value: testStorage, forType: GeofenceStorage.self)

        let stubServices = StubLocationServices(cachedLocation: cachedLocation)
        self.state = GeofenceModuleState(
            locationServicesProvider: { stubServices }
        )
    }

    func wire() {
        state.setup(di: di)
    }

    func cleanup() {
        di.reset()
        try? FileManager.default.removeItem(at: tempDir)
    }
}

/// Stub `LocationServices` returning a fixed cached location; other operations are no-ops.
private final class StubLocationServices: LocationServices, @unchecked Sendable {
    private let cachedLocation: LocationData?

    init(cachedLocation: LocationData?) {
        self.cachedLocation = cachedLocation
    }

    func setLastKnownLocation(_ location: CLLocation) {}
    func requestLocationUpdate() {}
    func getLastKnownLocation() async -> LocationData? {
        cachedLocation
    }
}

/// Captures registered observers so tests can deliver events synchronously without spinning
/// up the real `CioEventBusHandler` and its async operation queue. Keyed by `EventRepresentable.key`.
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
