@testable import CioInternalCommon
@_spi(Geofence) import CioLocation
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import CoreLocation
import Foundation
import SharedTests
import Testing

/// Tests `GeofenceModuleState.setup` without the full `initialize()` path, which spins up
/// `CLLocationManager` and lifecycle observers.
///
/// Each test owns a private `DIGraphShared`, so a fire-and-forget refresh `Task` can never resolve
/// a dependency another suite swapped on the shared graph.
@Suite("GeofenceModuleState.setup", .serialized)
struct GeofenceModuleSetupTests {
    @Test
    @MainActor
    func setup_givenResetEventDelivered_expectCoordinatorResetCalled() async throws {
        let f = Fixture()
        defer { f.cleanup() }

        let (resetSignal, resetContinuation) = AsyncStream<Void>.makeStream()
        let resetContinuationWatchdog = bounded(resetContinuation)
        defer { resetContinuationWatchdog.cancel() }
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
    func setup_givenResetEvent_clearsRefreshArm_soLaterFixDoesNotRefresh() async throws {
        // Otherwise a fix after logout would drive a refresh armed in the previous user's session.
        let f = Fixture(cachedLocation: LocationData(latitude: 1, longitude: 2))
        defer { f.cleanup() }

        let (refreshSignal, refreshContinuation) = AsyncStream<Void>.makeStream()
        let refreshContinuationWatchdog = bounded(refreshContinuation)
        defer { refreshContinuationWatchdog.cancel() }
        f.spyCoordinator.refreshClosure = { _, _, _ in
            refreshContinuation.yield()
            return .success(())
        }

        f.wire()
        var iter = refreshSignal.makeAsyncIterator()
        _ = await iter.next() // drain the launch refresh (cached anchor clears the no-anchor arm)

        f.state.onRefreshRequested()
        let reset = try #require(f.bus.observers[ResetEvent.key], "ResetEvent observer must be registered")
        reset(ResetEvent())

        let locAcquired = try #require(f.bus.observers[LocationAcquiredEvent.key], "LocationAcquiredEvent observer must be registered")
        locAcquired(LocationAcquiredEvent(location: LocationData(latitude: 3, longitude: 4)))

        #expect(f.spyCoordinator.refreshCallsCount == 1) // only the launch refresh
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
        let refreshContinuationWatchdog = bounded(refreshContinuation)
        defer { refreshContinuationWatchdog.cancel() }
        f.spyCoordinator.refreshClosure = { lat, lon, _ in
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
        // The registration center wins over the Location cache, which movement never updates and
        // is stale on relaunch; anchoring there would re-rank from a far-away point.
        let f = Fixture(cachedLocation: LocationData(latitude: 12.34, longitude: 56.78))
        defer { f.cleanup() }

        await f.di.geofenceStorage.recordRegistration(center: LocationData(latitude: 10, longitude: 20), businessIds: ["g1"])

        let (refreshSignal, refreshContinuation) = AsyncStream<(Double, Double)>.makeStream()
        let refreshContinuationWatchdog = bounded(refreshContinuation)
        defer { refreshContinuationWatchdog.cancel() }
        f.spyCoordinator.refreshClosure = { lat, lon, _ in
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

        f.spyCoordinator.refreshClosure = { _, _, _ in .success(()) }

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
        let continuationWatchdog = bounded(continuation)
        defer { continuationWatchdog.cancel() }
        f.stub.onRequestSilently = { continuation.yield() }

        f.wire()

        var iter = signal.makeAsyncIterator()
        _ = await iter.next()

        #expect(f.stub.requestSilentlyCount.wrappedValue == 1)
    }

    @Test
    @MainActor
    func setup_givenNoAnchorAtLaunch_whenIdentifiedWithAnchor_expectRefresh() async throws {
        // Launch runs with no anchor (arms + acquires, no refresh); a registration recorded
        // afterward is what the identify refresh anchors on.
        let f = Fixture()
        defer { f.cleanup() }

        let (readSignal, readContinuation) = AsyncStream<Void>.makeStream()
        let readContinuationWatchdog = bounded(readContinuation)
        defer { readContinuationWatchdog.cancel() }
        f.stub.onGetLastKnown = { readContinuation.yield() }

        let (refreshSignal, refreshContinuation) = AsyncStream<(Double, Double)>.makeStream()
        let refreshContinuationWatchdog = bounded(refreshContinuation)
        defer { refreshContinuationWatchdog.cancel() }
        f.spyCoordinator.refreshClosure = { lat, lon, _ in
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

        // Barrier on the anchor read, the last await before the no-anchor branch. It fires as the
        // read starts, so the arm may not be written yet; the fix loop below handles that.
        let (readSignal, readContinuation) = AsyncStream<Void>.makeStream()
        let readContinuationWatchdog = bounded(readContinuation)
        defer { readContinuationWatchdog.cancel() }
        f.stub.onGetLastKnown = { readContinuation.yield() }

        f.spyCoordinator.refreshClosure = { _, _, _ in .success(()) }

        f.wire()

        var readIter = readSignal.makeAsyncIterator()
        _ = await readIter.next()

        #expect(f.stub.requestSilentlyCount.wrappedValue == 0)

        // Launch still armed the first-run refresh. The arm has no observable of its own in manual
        // mode and a fix delivered before it is a no-op, so deliver until one is consumed.
        let locAcquired = try #require(f.bus.observers[LocationAcquiredEvent.key], "LocationAcquiredEvent observer must be registered")
        let refreshed = await settle {
            if f.spyCoordinator.refreshCallsCount == 0 {
                locAcquired(LocationAcquiredEvent(location: LocationData(latitude: 9, longitude: 10)))
            }
            return f.spyCoordinator.refreshCallsCount >= 1
        }
        #expect(refreshed, "the armed first-run refresh never consumed the host's fix")
        #expect(f.spyCoordinator.refreshReceivedArguments?.latitude == 9)
        #expect(f.spyCoordinator.refreshReceivedArguments?.longitude == 10)
        #expect(f.stub.requestSilentlyCount.wrappedValue == 0)
    }

    @Test
    @MainActor
    func setup_givenExplicitRefreshRequested_whenLocationAcquiredWithoutPriorSkip_expectRefresh() async throws {
        // An anchor at launch clears the no-anchor arm, so only the explicit arm can drive the
        // second refresh.
        let f = Fixture(cachedLocation: LocationData(latitude: 1, longitude: 2))
        defer { f.cleanup() }

        let (refreshSignal, refreshContinuation) = AsyncStream<(Double, Double)>.makeStream()
        let refreshContinuationWatchdog = bounded(refreshContinuation)
        defer { refreshContinuationWatchdog.cancel() }
        f.spyCoordinator.refreshClosure = { lat, lon, _ in
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
        // An anchor at launch must not arm the first-run flag, or a later fix fires a second,
        // competing refresh.
        let f = Fixture(cachedLocation: LocationData(latitude: 1, longitude: 2))
        defer { f.cleanup() }

        let (refreshSignal, refreshContinuation) = AsyncStream<Void>.makeStream()
        let refreshContinuationWatchdog = bounded(refreshContinuation)
        defer { refreshContinuationWatchdog.cancel() }
        f.spyCoordinator.refreshClosure = { _, _, _ in
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

    // MARK: - Visit arming

    /// Kept in this suite so they don't run in parallel with it: a sibling suite holding the main
    /// actor starved the disarm hop and timed out the barrier.

    @Test
    @MainActor
    func identify_givenSetupRanBeforeIdentify_expectVisitsArmed() async throws {
        let f = Fixture(identifiedUserId: nil)
        defer { f.cleanup() }
        f.wire()

        // Bootstrap arms on its own task and, with no user yet, disarms. Waiting for that first
        // means a later `start` can only come from the identify observer.
        try await f.settle { f.visitMonitor.stopCallCount == 1 }
        #expect(f.visitMonitor.startCallCount == 0)

        f.contextStore.setUserId("u1")
        let identify = try #require(
            f.bus.observers[ProfileIdentifiedEvent.key], "ProfileIdentifiedEvent observer must be registered"
        )
        identify(ProfileIdentifiedEvent(identifier: "u1"))

        try await f.settle { f.visitMonitor.startCallCount == 1 }
    }

    /// `bindVisits` refuses a signed-out visit but leaves the monitor running, so only the reset
    /// path disarms.
    @Test
    @MainActor
    func reset_givenVisitsArmed_expectDisarmed() async throws {
        let f = Fixture(identifiedUserId: "u1")
        defer { f.cleanup() }
        // Unstubbed, the generated mock's implicitly-unwrapped return traps the test process.
        f.spyCoordinator.resetClosure = { .success(()) }
        f.wire()

        // Same barrier as above: bootstrap's own arming must land first, or its `stop` is
        // indistinguishable from reset's.
        try await f.settle { f.visitMonitor.startCallCount == 1 }
        #expect(f.visitMonitor.stopCallCount == 0)

        // Cleared before the event, matching production: `commonClearIdentify` calls
        // `clearUserId()` before `analytics.reset()`, and it is that reset which posts the event.
        f.contextStore.setUserId(nil)
        let reset = try #require(f.bus.observers[ResetEvent.key], "ResetEvent observer must be registered")
        reset(ResetEvent())

        try await f.settle { f.visitMonitor.stopCallCount == 1 }
    }
}

/// Per-test private `DIGraphShared` with capturing/mocking deps, and a fresh `GeofenceModuleState`
/// with a stub `LocationServices`.
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
    let visitMonitor: MockGeofenceVisitMonitor
    let contextStore: BackgroundDeliveryContextStore

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
        self.contextStore = contextStore

        self.visitMonitor = MockGeofenceVisitMonitor()
        di.override(value: visitMonitor as GeofenceVisitMonitoring, forType: GeofenceVisitMonitoring.self)

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

    /// Waits for a condition the module's own tasks satisfy.
    ///
    /// `Date`/`Task.sleep(nanoseconds:)` rather than `ContinuousClock`: that is iOS 16+, and this
    /// package targets iOS 13.
    func settle(
        _ condition: () -> Bool,
        within: TimeInterval = 10,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let deadline = Date().addingTimeInterval(within)
        while Date() < deadline {
            // Arming runs through process-global chains a concurrent suite can hold, so await them
            // rather than race the deadline, which is only a backstop.
            await GeofenceBootstrap.awaitPendingWorkForTesting()
            if condition() { return }
            try await Task.sleep(nanoseconds: 5000000)
        }
        Issue.record("condition not met within \(within)s", sourceLocation: sourceLocation)
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

/// Captures registered observers so tests can deliver events synchronously, without the real
/// `CioEventBusHandler`'s async queue.
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

/// Bounds a signal the test awaits: if the SDK never sends it, the stream finishes and the await
/// returns `nil`, so the test fails instead of hanging the whole run.
private func bounded<T>(_ continuation: AsyncStream<T>.Continuation, seconds: TimeInterval = 5) -> Task<Void, Never> {
    Task {
        do {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1000000000))
        } catch {
            // Cancelled: the test stood the watchdog down. Not `try?`, which would fall through to
            // `finish()` and close the stream.
            return
        }
        continuation.finish()
    }
}
