@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@_spi(Geofence) import CioLocation
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import CoreLocation
import Foundation
import SharedTests
import Testing

/// Each test owns a private `DIGraphShared`, so a fire-and-forget refresh `Task` can't resolve
/// another suite's overrides.
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
        // Not the Location cache: movement never updates it, so it's stale on relaunch.
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
        let f = Fixture(cachedLocation: LocationData(latitude: 7, longitude: 8), identifiedUserId: nil)
        defer { f.cleanup() }

        f.spyCoordinator.refreshClosure = { _, _, _ in .success(()) }

        f.wire()
        // The user gate is synchronous, so nothing can have run.
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
        // Launch has no anchor, so it arms and acquires without refreshing.
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

        // Fires as the anchor read starts, so the arm may not be written yet; the fix loop covers it.
        let (readSignal, readContinuation) = AsyncStream<Void>.makeStream()
        let readContinuationWatchdog = bounded(readContinuation)
        defer { readContinuationWatchdog.cancel() }
        f.stub.onGetLastKnown = { readContinuation.yield() }

        f.spyCoordinator.refreshClosure = { _, _, _ in .success(()) }

        f.wire()

        var readIter = readSignal.makeAsyncIterator()
        _ = await readIter.next()

        #expect(f.stub.requestSilentlyCount.wrappedValue == 0)

        // The arm has no observable in manual mode and an earlier fix is a no-op, so deliver until
        // one is consumed.
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
        // The launch anchor clears the no-anchor arm, so only the explicit arm can drive a second
        // refresh.
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

    /// Kept in this serialized suite: in parallel, a sibling holding the main actor starved the
    /// disarm hop.

    @Test
    @MainActor
    func identify_givenSetupRanBeforeIdentify_expectVisitsArmed() async throws {
        let f = Fixture(identifiedUserId: nil)
        defer { f.cleanup() }
        f.wire()

        // Wait for bootstrap's own disarm, so a later `start` can only come from the identify observer.
        try await f.settle { f.visitMonitor.stopCallCount == 1 }
        #expect(f.visitMonitor.startCallCount == 0)

        f.contextStore.setUserId("u1")
        let identify = try #require(
            f.bus.observers[ProfileIdentifiedEvent.key], "ProfileIdentifiedEvent observer must be registered"
        )
        identify(ProfileIdentifiedEvent(identifier: "u1"))

        try await f.settle { f.visitMonitor.startCallCount == 1 }
    }

    /// Only reset disarms: `bindVisits` refuses a signed-out visit but leaves the monitor running.
    @Test
    @MainActor
    func reset_givenVisitsArmed_expectDisarmed() async throws {
        let f = Fixture(identifiedUserId: "u1")
        defer { f.cleanup() }
        // Unstubbed, the generated mock's implicitly-unwrapped return traps the test process.
        f.spyCoordinator.resetClosure = { .success(()) }
        f.wire()

        // Bootstrap's own arming must land first, or its `stop` is indistinguishable from reset's.
        try await f.settle { f.visitMonitor.startCallCount == 1 }
        #expect(f.visitMonitor.stopCallCount == 0)

        // Cleared before the event, as in production: `clearUserId()` runs before `analytics.reset()`.
        f.contextStore.setUserId(nil)
        let reset = try #require(f.bus.observers[ResetEvent.key], "ResetEvent observer must be registered")
        reset(ResetEvent())

        try await f.settle { f.visitMonitor.stopCallCount == 1 }
    }
}

extension GeofenceModuleSetupTests {
    /// `identify(B)` while A is identified only rewrites the identified user: no reset clears
    /// user-scoped state. A's visit must not survive B's time and be picked up again when A comes
    /// back, as a stay continuous across both identities.
    @Test
    @MainActor
    func setup_givenIdentitySwitchesAwayAndBack_expectTheEarlierUsersVisitEnded() async throws {
        let f = Fixture(identifiedUserId: "user-a")
        defer { f.cleanup() }
        let fence = await Self.seedVisit(f, userId: "user-a")
        f.spyCoordinator.refreshClosure = { _, _, _ in .success(()) }
        f.wire()
        await GeofenceBootstrap.awaitPendingWorkForTesting()
        let identify = try #require(f.bus.observers[ProfileIdentifiedEvent.key])

        f.contextStore.setUserId("user-b")
        identify(ProfileIdentifiedEvent(identifier: "user-b"))
        f.contextStore.setUserId("user-a")
        identify(ProfileIdentifiedEvent(identifier: "user-a"))

        #expect(await Self.visitEnds(f, fence: fence))
    }

    /// Control: identifying the same user again keeps that user's visit.
    @Test
    @MainActor
    func setup_givenTheSameUserIdentifiedAgain_expectTheVisitKept() async throws {
        let f = Fixture(identifiedUserId: "user-a")
        defer { f.cleanup() }
        let fence = await Self.seedVisit(f, userId: "user-a")
        f.spyCoordinator.refreshClosure = { _, _, _ in .success(()) }
        f.wire()
        await GeofenceBootstrap.awaitPendingWorkForTesting()
        let identify = try #require(f.bus.observers[ProfileIdentifiedEvent.key])

        identify(ProfileIdentifiedEvent(identifier: "user-a"))

        #expect(await Self.visitEnds(f, fence: fence) == false)
    }

    @MainActor
    private static func seedVisit(_ f: Fixture, userId: String) async -> Geofence {
        let fence = Geofence(
            id: "dwell-fence", latitude: 1, longitude: 2, radius: 100, name: nil,
            transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1), dwellThresholdSeconds: 60
        )
        let storage = f.di.geofenceStorage
        await storage.setCachedGeofences([fence])
        // Observes the store the producer writes, as the shared tracker does.
        let tracker = GeofenceIdentityTracker(contextStore: f.contextStore)
        f.di.override(value: tracker, forType: GeofenceIdentityTracker.self)
        let dwell = GeofenceDwellCoordinator(
            storage: storage, transitionEmitter: SilentTransitionEmitter(), contextStore: f.contextStore,
            logger: LoggerMock(), notificationCenter: NotificationCenter(), freshFixProvider: { nil },
            identityTracker: tracker
        )
        f.di.override(value: dwell, forType: GeofenceDwellCoordinator.self)
        // Recorded from an ENTER, so it carries the identity it was recorded under.
        await dwell.handleBoundary(geofence: fence, transition: .enter, occurredAt: Date())
        dwell.cancelEvidence(for: fence.id)
        #expect(await storage.getDwellVisit(geofenceId: fence.id)?.userId == userId)
        return fence
    }

    /// Bounded: the identity handler works on tasks of its own.
    private static func visitEnds(_ f: Fixture, fence: Geofence) async -> Bool {
        for _ in 0 ..< 100 {
            if await f.di.geofenceStorage.getDwellVisit(geofenceId: fence.id) == nil { return true }
            try? await Task.sleep(nanoseconds: 10000000)
        }
        return false
    }
}

/// `DataPipelineImplementation.identify` writes the context store, then posts
/// `ProfileIdentifiedEvent`; `CombinedCacheEventBusHandler.postEvent` delivers it from an
/// unstructured task, off the main actor and unordered against later posts. The observer's cleanup
/// then hops to the main actor. These tests invoke the real observer on the main actor, so that
/// cleanup cannot start until the test yields.
extension GeofenceModuleSetupTests {
    /// B then A identified, both observed, cleanup not yet run: A's earlier visit spans B's time and
    /// must already admit no DWELL.
    @Test
    @MainActor
    func setup_givenBThenAObservedBeforeCleanupRuns_expectEarlierVisitAdmitsNoDwell() async throws {
        let f = Fixture(identifiedUserId: "user-a")
        defer { f.cleanup() }
        let rig = await IdentityRig.make(f)
        let identify = try await rig.wire(f)

        f.contextStore.setUserId("user-b")
        identify(ProfileIdentifiedEvent(identifier: "user-b"))
        f.contextStore.setUserId("user-a")
        identify(ProfileIdentifiedEvent(identifier: "user-a"))

        // No suspension yet: neither cleanup task has run.
        #expect(rig.dwell.continuityHolds(for: rig.visit, geofenceId: rig.fence.id) == false)
        await rig.dwell.emitDwellIfQualified(
            geofence: rig.fence, visit: rig.visit, observedAt: rig.clock.wall, source: "location_evidence", userId: "user-a"
        )
        #expect(await rig.emitter.dwellCount() == 0)
    }

    /// The producer and the profile callback can both run on any task; recording B needs neither
    /// the main actor nor the event bus.
    @Test
    @MainActor
    func setup_givenUserChangedOffTheMainActor_expectLossRecordedWithoutCrashing() async throws {
        let f = Fixture(identifiedUserId: "user-a")
        defer { f.cleanup() }
        let rig = await IdentityRig.make(f)
        let identify = try await rig.wire(f)

        let store = f.contextStore
        await Task.detached {
            store.setUserId("user-b")
            identify(ProfileIdentifiedEvent(identifier: "user-b"))
        }.value

        #expect(rig.dwell.continuityHolds(for: rig.visit, geofenceId: rig.fence.id) == false)
    }

    /// The producer changes the user to B and back to A before the bus delivers either profile
    /// event. A's earlier visit spans B's time: refused at once, with no event at all.
    @Test
    @MainActor
    func setup_givenUserChangedAwayAndBackBeforeAnyProfileEvent_expectEarlierVisitAdmitsNoDwell() async throws {
        let f = Fixture(identifiedUserId: "user-a")
        defer { f.cleanup() }
        let rig = await IdentityRig.make(f)
        _ = try await rig.wire(f)

        f.contextStore.setUserId("user-b")
        rig.clock.advance(5)
        f.contextStore.setUserId("user-a")

        #expect(rig.dwell.continuityHolds(for: rig.visit, geofenceId: rig.fence.id) == false)
        await rig.dwell.emitDwellIfQualified(
            geofence: rig.fence, visit: rig.visit, observedAt: rig.clock.wall, source: "location_evidence", userId: "user-a"
        )
        #expect(await rig.emitter.dwellCount() == 0)
    }

    /// Signing out ends the stay, whether by an empty user or a reset.
    @Test(arguments: [false, true])
    @MainActor
    func setup_givenUserClearedAndRestored_expectEarlierVisitAdmitsNoDwell(byReset: Bool) async throws {
        let f = Fixture(identifiedUserId: "user-a")
        defer { f.cleanup() }
        let rig = await IdentityRig.make(f)
        _ = try await rig.wire(f)

        if byReset { f.contextStore.reset() } else { f.contextStore.setUserId("") }
        f.contextStore.setUserId("user-a")

        #expect(rig.dwell.continuityHolds(for: rig.visit, geofenceId: rig.fence.id) == false)
    }

    /// The tracker matches the store's internal notification by its string values.
    @Test
    func identityTracker_expectTheStoresNotificationNameAndKey() {
        #expect(GeofenceIdentityTracker.userIdDidChangeNotification == BackgroundDeliveryContextStore.userIdDidChangeNotification)
        #expect(GeofenceIdentityTracker.userIdKey == BackgroundDeliveryContextStore.userIdKey)
        #expect(GeofenceIdentityTracker.userVersionKey == BackgroundDeliveryContextStore.userVersionKey)
        #expect(GeofenceIdentityTracker.userLineageKey == BackgroundDeliveryContextStore.userLineageKey)
        #expect(GeofenceIdentityTracker.userSnapshotRequest == BackgroundDeliveryContextStore.userSnapshotRequest)
        #expect(GeofenceIdentityTracker.replyKey == BackgroundDeliveryContextStore.replyKey)
    }

    /// Control: the producer writing the same user again changes nothing.
    @Test
    @MainActor
    func setup_givenTheSameUserWrittenAgain_expectTheVisitStillHolds() async throws {
        let f = Fixture(identifiedUserId: "user-a")
        defer { f.cleanup() }
        let rig = await IdentityRig.make(f)
        _ = try await rig.wire(f)

        f.contextStore.setUserId("user-a")

        #expect(rig.dwell.continuityHolds(for: rig.visit, geofenceId: rig.fence.id))
    }

    /// B's profile event arrives late, after A was restored and recorded a new visit. B happened
    /// before that visit: neither admission nor B's cleanup may end it.
    @Test
    @MainActor
    func setup_givenDelayedProfileEventOlderThanARestoredVisit_expectTheVisitKept() async throws {
        let f = Fixture(identifiedUserId: "user-a")
        defer { f.cleanup() }
        let rig = await IdentityRig.make(f)
        let identify = try await rig.wire(f)
        let changedToB = rig.clock.wall
        f.contextStore.setUserId("user-b")
        rig.clock.advance(10)
        f.contextStore.setUserId("user-a")
        identify(ProfileIdentifiedEvent(identifier: "user-a", timestamp: rig.clock.wall))
        rig.clock.advance(10)
        let later = await rig.recordVisit()
        rig.clock.advance(60)

        identify(ProfileIdentifiedEvent(identifier: "user-b", timestamp: changedToB))
        await settleQuietly(0.5)

        #expect(rig.dwell.continuityHolds(for: later, geofenceId: rig.fence.id))
        #expect(await rig.storage.getDwellVisit(geofenceId: rig.fence.id)?.visitId == later.visitId)
    }

    /// The real event bus replays its whole cached history to the module's observer: B then A,
    /// both from before the A visit now stored, whose dwell was already emitted. Neither may end
    /// it — losing its emitted mark would let the same uninterrupted stay emit a second DWELL.
    @Test(arguments: [false, true])
    @MainActor
    func setup_givenBusReplaysIdentityHistoryOlderThanTheVisit_expectEmittedVisitKeptAndNoSecondDwell(wallRolledBack: Bool) async throws {
        let f = Fixture(identifiedUserId: "user-a")
        defer { f.cleanup() }
        let eventStorage = EventStorageMock()
        eventStorage.loadEventsReturnValue = []
        let bus = CombinedCacheEventBusHandler(eventStorage: eventStorage, logger: LoggerMock())
        f.di.override(value: bus as EventBusHandler, forType: EventBusHandler.self)
        let clock = ManualGeofenceClock()
        // The history, before the geofence module or its tracker existed in this process.
        f.contextStore.setUserId("user-b")
        await bus.postEventAndWait(ProfileIdentifiedEvent(identifier: "user-b", timestamp: clock.wall))
        clock.advance(5)
        f.contextStore.setUserId("user-a")
        await bus.postEventAndWait(ProfileIdentifiedEvent(identifier: "user-a", timestamp: clock.wall))
        clock.advance(5)
        if wallRolledBack { clock.wall = clock.wall.addingTimeInterval(-3600) }
        let rig = await IdentityRig.make(f, clock: clock, visitEmitted: true, polygon: true)
        f.spyCoordinator.refreshClosure = { _, _, _ in .success(()) }

        f.wire()
        // Posted behind the replay on the same key, so it returns once the replay was delivered.
        await bus.postEventAndWait(ProfileIdentifiedEvent(identifier: "user-a", timestamp: clock.wall))
        await GeofenceBootstrap.awaitPendingWorkForTesting()
        await settleQuietly(0.3)
        rig.dwell.cancelEvidence(for: rig.fence.id)

        let stored = await rig.storage.getDwellVisit(geofenceId: rig.fence.id)
        #expect(stored?.visitId == rig.visit.visitId)
        #expect(stored?.emitted == true)
        // The device is still inside: fresh evidence a moment later, and again after the threshold.
        clock.advance(1)
        await rig.dwell.recordInsideEvidence(geofence: rig.fence, at: clock.wall, source: "location_evidence")
        clock.advance(600)
        await rig.dwell.recordInsideEvidence(geofence: rig.fence, at: clock.wall, source: "location_evidence")
        #expect(await rig.emitter.dwellCount() == 0)
        rig.dwell.cancelEvidence(for: rig.fence.id)
    }

    /// The cleanup B queued is dated when B was observed. A visit A records after A is identified
    /// again, before that cleanup runs, is not one B interrupted.
    @Test
    @MainActor
    func setup_givenStaleIdentityCleanup_expectALaterVisitOfTheRestoredUserKept() async throws {
        let f = Fixture(identifiedUserId: "user-a")
        defer { f.cleanup() }
        let rig = await IdentityRig.make(f)
        let identify = try await rig.wire(f)

        f.contextStore.setUserId("user-b")
        identify(ProfileIdentifiedEvent(identifier: "user-b"))
        rig.clock.advance(10)
        f.contextStore.setUserId("user-a")
        identify(ProfileIdentifiedEvent(identifier: "user-a"))
        rig.clock.advance(10)
        let later = await rig.recordVisit()
        // Both cleanups run now.
        await settleQuietly(0.5)

        #expect(await rig.storage.getDwellVisit(geofenceId: rig.fence.id)?.visitId == later.visitId)
        #expect(rig.dwell.continuityHolds(for: later, geofenceId: rig.fence.id))
    }

    /// Control: the same user identified again changes nothing; the visit still qualifies.
    @Test
    @MainActor
    func setup_givenTheSameUserIdentifiedAgain_expectTheVisitStillQualifies() async throws {
        let f = Fixture(identifiedUserId: "user-a")
        defer { f.cleanup() }
        let rig = await IdentityRig.make(f)
        let identify = try await rig.wire(f)

        identify(ProfileIdentifiedEvent(identifier: "user-a"))

        #expect(rig.dwell.continuityHolds(for: rig.visit, geofenceId: rig.fence.id))
        await rig.dwell.emitDwellIfQualified(
            geofence: rig.fence, visit: rig.visit, observedAt: rig.clock.wall, source: "location_evidence", userId: "user-a"
        )
        #expect(await rig.emitter.dwellCount() == 1)
    }
}

/// A user-a visit 600 s into a 600 s threshold, under a coordinator and identity tracker the
/// fixture's graph resolves.
@MainActor
private struct IdentityRig {
    let clock: ManualGeofenceClock
    let storage: GeofenceStorage
    let dwell: GeofenceDwellCoordinator
    let emitter: CountingDwellEmitter
    let fence: Geofence
    let visit: GeofenceDwellVisit

    static func make(
        _ f: Fixture,
        clock: ManualGeofenceClock = ManualGeofenceClock(),
        visitEmitted: Bool = false,
        polygon: Bool = false
    ) async -> IdentityRig {
        let fence = Geofence(
            id: "dwell-fence", latitude: 1, longitude: 2, radius: 100, name: nil,
            transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1),
            vertices: polygon ? [
                LocationData(latitude: 0.999, longitude: 1.999),
                LocationData(latitude: 0.999, longitude: 2.001),
                LocationData(latitude: 1.001, longitude: 2.001),
                LocationData(latitude: 1.001, longitude: 1.999)
            ] : nil,
            dwellThresholdSeconds: 600
        )
        let storage = f.di.geofenceStorage
        await storage.setCachedGeofences([fence])
        // Subscribed to the store the module's producer writes, as the shared tracker is.
        let tracker = GeofenceIdentityTracker(contextStore: f.contextStore)
        f.di.override(value: tracker, forType: GeofenceIdentityTracker.self)
        let emitter = CountingDwellEmitter()
        let dwell = GeofenceDwellCoordinator(
            storage: storage, transitionEmitter: emitter, contextStore: f.contextStore, logger: LoggerMock(),
            notificationCenter: NotificationCenter(), freshFixProvider: { nil }, clock: clock, identityTracker: tracker
        )
        f.di.override(value: dwell, forType: GeofenceDwellCoordinator.self)
        // Recorded by the coordinator from an ENTER, so it carries whatever provenance this build
        // stamps on a visit.
        var visit = await Self.recordVisit(dwell: dwell, storage: storage, fence: fence, clock: clock)
        if visitEmitted {
            #expect(await storage.markDwellVisitEmitted(visit, geofenceId: fence.id) == .marked)
            visit.emitted = true
        }
        clock.advance(600)
        return IdentityRig(clock: clock, storage: storage, dwell: dwell, emitter: emitter, fence: fence, visit: visit)
    }

    /// A new user-a visit from an ENTER now, as A's next arrival records it.
    func recordVisit() async -> GeofenceDwellVisit {
        await Self.recordVisit(dwell: dwell, storage: storage, fence: fence, clock: clock)
    }

    private static func recordVisit(
        dwell: GeofenceDwellCoordinator, storage: GeofenceStorage, fence: Geofence, clock: ManualGeofenceClock
    ) async -> GeofenceDwellVisit {
        await dwell.handleBoundary(geofence: fence, transition: .enter, occurredAt: clock.wall)
        dwell.cancelEvidence(for: fence.id)
        let stored = await storage.getDwellVisit(geofenceId: fence.id)
        #expect(stored?.userId == "user-a")
        return stored ?? GeofenceDwellVisit(
            visitId: "missing", enteredAt: clock.wall, geometryRevision: fence.dwellRevision, userId: "user-a",
            emitted: false, timing: nil
        )
    }

    /// Wires the module and returns its real `ProfileIdentifiedEvent` observer.
    func wire(_ f: Fixture) async throws -> (ProfileIdentifiedEvent) -> Void {
        f.spyCoordinator.refreshClosure = { _, _, _ in .success(()) }
        f.wire()
        await GeofenceBootstrap.awaitPendingWorkForTesting()
        dwell.cancelEvidence(for: fence.id)
        let observer = try #require(f.bus.observers[ProfileIdentifiedEvent.key])
        return { observer($0) }
    }
}

private actor CountingDwellEmitter: GeofenceTransitionEmitting {
    private var dwells = 0

    func trackTransition(geofenceId: String, transition: GeofenceTransition, occurredAt: Date) async {}
    func trackDwell(
        geofenceId: String, occurredAt: Date, context: GeofenceDwellContext, expectedUserId: String?
    ) async -> Bool {
        dwells += 1
        return true
    }

    func trackExit(
        geofenceId: String, occurredAt: Date, context: GeofenceExitContext?, expectedUserId: String?
    ) async {}

    func dwellCount() -> Int {
        dwells
    }
}

private actor SilentTransitionEmitter: GeofenceTransitionEmitting {
    func trackTransition(geofenceId: String, transition: GeofenceTransition, occurredAt: Date) async {}
    func trackDwell(
        geofenceId: String, occurredAt: Date, context: GeofenceDwellContext, expectedUserId: String?
    ) async -> Bool {
        true
    }

    func trackExit(
        geofenceId: String, occurredAt: Date, context: GeofenceExitContext?, expectedUserId: String?
    ) async {}
}

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

    /// Not `ContinuousClock`: it's iOS 16+ and this package targets iOS 13.
    func settle(
        _ condition: () -> Bool,
        within: TimeInterval = 10,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let deadline = Date().addingTimeInterval(within)
        while Date() < deadline {
            // Await the process-global chains a concurrent suite can hold; the deadline is a backstop.
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

/// Finishes the stream after `seconds`, so a missing signal fails the test instead of hanging it.
private func bounded<T>(_ continuation: AsyncStream<T>.Continuation, seconds: TimeInterval = 5) -> Task<Void, Never> {
    Task {
        do {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1000000000))
        } catch {
            // Not `try?`: cancellation must not fall through to `finish()`.
            return
        }
        continuation.finish()
    }
}
