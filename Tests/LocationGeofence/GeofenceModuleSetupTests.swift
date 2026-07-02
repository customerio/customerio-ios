@testable import CioInternalCommon
@_spi(Geofence) import CioLocation
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
    func setup_givenCachedAnchor_expectRefreshFromAnchorAtLaunch() async throws {
        let f = Fixture(cachedLocation: LocationData(latitude: 12.34, longitude: 56.78))
        defer { f.cleanup() }

        let (refreshSignal, refreshContinuation) = AsyncStream<(Double, Double)>.makeStream()
        f.spyCoordinator.refreshClosure = { lat, lon in
            refreshContinuation.yield((lat, lon))
            return .success(())
        }

        f.wire()

        var iter = refreshSignal.makeAsyncIterator()
        let received = await iter.next()

        #expect(received?.0 == 12.34)
        #expect(received?.1 == 56.78)
        #expect(f.spyCoordinator.refreshCallsCount == 1)
    }

    @Test
    @MainActor
    func setup_givenRegistrationCenter_expectRefreshAnchoredThereNotCacheAtLaunch() async throws {
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

        var iter = refreshSignal.makeAsyncIterator()
        let received = await iter.next()

        #expect(received?.0 == 10)
        #expect(received?.1 == 20)
    }

    @Test
    @MainActor
    func setup_givenNoIdentifiedUser_expectNoRefreshOrAcquireAtLaunch() throws {
        // Geofencing can't sync without a user, so launch must not refresh or self-acquire a fix.
        let f = Fixture(cachedLocation: LocationData(latitude: 7, longitude: 8), identifiedUserId: nil)
        defer { f.cleanup() }

        f.spyCoordinator.refreshClosure = { _, _ in .success(()) }

        f.wire()
        // The user gate is synchronous (no Task spawned), so nothing can have run.
        #expect(f.spyCoordinator.refreshCallsCount == 0)
        #expect(f.stub.requestSilentlyCount.wrappedValue == 0)
    }

    @Test
    @MainActor
    func setup_givenAutomaticModeAndNoAnchor_expectSilentAcquireAtLaunch() async throws {
        let f = Fixture(locationMode: .automatic)
        defer { f.cleanup() }

        let (signal, continuation) = AsyncStream<Void>.makeStream()
        f.stub.onRequestSilently = { continuation.yield() }

        f.wire()

        var iter = signal.makeAsyncIterator()
        _ = await iter.next()

        #expect(f.stub.requestSilentlyCount.wrappedValue == 1)
    }

    @Test
    @MainActor
    func setup_givenNoAnchorAtLaunch_whenIdentifiedWithAnchor_expectRefresh() async throws {
        // Identify is a distinct refresh trigger. Launch runs first with no anchor (arms + acquires,
        // no refresh); a registration recorded afterward is what the identify refresh anchors on.
        let f = Fixture()
        defer { f.cleanup() }

        let (readSignal, readContinuation) = AsyncStream<Void>.makeStream()
        f.stub.onGetLastKnown = { readContinuation.yield() }

        let (refreshSignal, refreshContinuation) = AsyncStream<(Double, Double)>.makeStream()
        f.spyCoordinator.refreshClosure = { lat, lon in
            refreshContinuation.yield((lat, lon))
            return .success(())
        }

        f.wire()

        // Barrier: wait for the launch pass to read location (no anchor yet) before recording one.
        var readIter = readSignal.makeAsyncIterator()
        _ = await readIter.next()

        await f.di.geofenceStorage.recordRegistration(center: LocationData(latitude: 10, longitude: 20), businessIds: ["g1"])

        let identify = try #require(f.bus.observers[ProfileIdentifiedEvent.key], "ProfileIdentifiedEvent observer must be registered")
        identify(ProfileIdentifiedEvent(identifier: "u1"))

        var refreshIter = refreshSignal.makeAsyncIterator()
        let received = await refreshIter.next()

        #expect(received?.0 == 10)
        #expect(received?.1 == 20)
        #expect(f.spyCoordinator.refreshCallsCount == 1)
    }

    @Test
    @MainActor
    func setup_givenManualModeAndNoAnchor_expectArmsButDoesNotSelfAcquire() async throws {
        let f = Fixture(locationMode: .manual)
        defer { f.cleanup() }

        // The anchor read is the last await before the no-anchor branch runs, so awaiting it as a
        // barrier guarantees the launch arm + acquire-gate decision has executed before we assert.
        let (readSignal, readContinuation) = AsyncStream<Void>.makeStream()
        f.stub.onGetLastKnown = { readContinuation.yield() }

        let (refreshSignal, refreshContinuation) = AsyncStream<(Double, Double)>.makeStream()
        f.spyCoordinator.refreshClosure = { lat, lon in
            refreshContinuation.yield((lat, lon))
            return .success(())
        }

        f.wire()

        var readIter = readSignal.makeAsyncIterator()
        _ = await readIter.next()

        // Manual mode never self-acquires; the host must drive location.
        #expect(f.stub.requestSilentlyCount.wrappedValue == 0)

        // But launch still armed the first-run refresh, so a host-driven fix drives the sync.
        let locAcquired = try #require(f.bus.observers[LocationAcquiredEvent.key], "LocationAcquiredEvent observer must be registered")
        locAcquired(LocationAcquiredEvent(location: LocationData(latitude: 9, longitude: 10)))

        var refreshIter = refreshSignal.makeAsyncIterator()
        let received = await refreshIter.next()
        #expect(received?.0 == 9)
        #expect(received?.1 == 10)
        #expect(f.stub.requestSilentlyCount.wrappedValue == 0)
    }

    @Test
    @MainActor
    func setup_givenExplicitRefreshRequested_whenLocationAcquiredWithoutPriorSkip_expectRefresh() async throws {
        // An anchor at launch clears the no-anchor arm, so only the host-initiated arm can drive the
        // second refresh — isolating the explicit-refresh path.
        let f = Fixture(cachedLocation: LocationData(latitude: 1, longitude: 2))
        defer { f.cleanup() }

        let (refreshSignal, refreshContinuation) = AsyncStream<(Double, Double)>.makeStream()
        f.spyCoordinator.refreshClosure = { lat, lon in
            refreshContinuation.yield((lat, lon))
            return .success(())
        }

        f.wire()

        var iter = refreshSignal.makeAsyncIterator()
        _ = await iter.next() // drain the launch refresh (clears the no-anchor arm)

        f.state.onRefreshRequested()

        let deliver = try #require(f.bus.observers[LocationAcquiredEvent.key], "LocationAcquiredEvent observer must be registered")
        deliver(LocationAcquiredEvent(location: LocationData(latitude: 5, longitude: 6)))

        let received = await iter.next()

        #expect(received?.0 == 5)
        #expect(received?.1 == 6)
        #expect(f.spyCoordinator.refreshCallsCount == 2)
    }

    @Test
    @MainActor
    func setup_givenAnchorAtLaunch_whenLocationAcquired_expectNoDuplicateRefresh() async throws {
        // An anchor at launch must NOT arm the first-run flag, so a later fix does not fire a second,
        // competing refresh (guards against the false-arm race).
        let f = Fixture(cachedLocation: LocationData(latitude: 1, longitude: 2))
        defer { f.cleanup() }

        let (refreshSignal, refreshContinuation) = AsyncStream<Void>.makeStream()
        f.spyCoordinator.refreshClosure = { _, _ in
            refreshContinuation.yield()
            return .success(())
        }

        f.wire()

        var iter = refreshSignal.makeAsyncIterator()
        _ = await iter.next() // launch refresh fired (anchor cleared the flag)

        let locAcquired = try #require(f.bus.observers[LocationAcquiredEvent.key], "LocationAcquiredEvent observer must be registered")
        locAcquired(LocationAcquiredEvent(location: LocationData(latitude: 3, longitude: 4)))

        #expect(f.spyCoordinator.refreshCallsCount == 1)
    }
}

/// Per-test setup: overrides the DI shared singleton with capturing/mocking deps and builds
/// a fresh `GeofenceModuleState` with a stub `LocationServices`.
@MainActor
private struct Fixture {
    let di: DIGraphShared
    let bus: CapturingEventBusHandler
    let spyCoordinator: GeofenceSyncCoordinatorMock
    let mockMonitor: MockGeofenceRegionMonitor
    let tempDir: URL
    let state: GeofenceModuleState
    let stub: StubLocationServices
    let locationMode: GeofenceLocationMode

    init(cachedLocation: LocationData? = nil, locationMode: GeofenceLocationMode = .automatic, identifiedUserId: String? = "test-user") {
        self.locationMode = locationMode
        self.di = DIGraphShared()

        self.bus = CapturingEventBusHandler()
        di.override(value: bus as EventBusHandler, forType: EventBusHandler.self)

        // Geofence refreshes require an identified user; seed one so launch/identify proceed.
        self.tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let contextStore = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: tempDir)
        contextStore.setUserId(identifiedUserId)
        di.override(value: contextStore, forType: BackgroundDeliveryContextStore.self)

        self.spyCoordinator = GeofenceSyncCoordinatorMock()
        di.override(value: spyCoordinator as GeofenceSyncCoordinator, forType: GeofenceSyncCoordinator.self)

        self.mockMonitor = MockGeofenceRegionMonitor()
        di.override(value: mockMonitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)

        let testStorage = GeofenceStorage(fileManager: .default, directoryURL: tempDir)
        di.override(value: testStorage, forType: GeofenceStorage.self)

        let stubServices = StubLocationServices(cachedLocation: cachedLocation)
        self.stub = stubServices
        self.state = GeofenceModuleState(
            locationServicesProvider: { stubServices }
        )
    }

    func wire() {
        state.setup(di: di, locationMode: locationMode)
    }

    func cleanup() {
        di.reset()
        try? FileManager.default.removeItem(at: tempDir)
    }
}

/// Stub `LocationServices` returning a fixed cached location and recording silent-acquire calls.
private final class StubLocationServices: LocationServices, @unchecked Sendable {
    private let cachedLocation: LocationData?
    let requestSilentlyCount = Synchronized<Int>(0)
    var onRequestSilently: (() -> Void)?
    var onGetLastKnown: (() -> Void)?

    init(cachedLocation: LocationData?) {
        self.cachedLocation = cachedLocation
    }

    func setLastKnownLocation(_ location: CLLocation) {}
    func requestLocationUpdate() {}
    func requestLocationUpdateSilently() {
        requestSilentlyCount.mutating { $0 += 1 }
        onRequestSilently?()
    }

    func getLastKnownLocation() async -> LocationData? {
        onGetLastKnown?()
        return cachedLocation
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
