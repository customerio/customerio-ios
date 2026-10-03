@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import CoreLocation
import Foundation
import SharedTests
import Testing
#if canImport(UIKit)
import UIKit
#endif

@Suite("PolygonMembershipResolver")
@MainActor
struct PolygonMembershipResolverTests {
    /// Frozen, so a stalled runner can't age a fix past `movementFixMaxAge`.
    private let clock = DateUtilStub()

    private actor EmitterSpy: GeofenceTransitionEmitting {
        struct Delivered: Equatable, Sendable {
            let id: String
            let transition: GeofenceTransition
            let occurredAt: Date
        }

        struct Exit: Sendable {
            let expectedUserId: String?
        }

        private(set) var delivered: [Delivered] = []
        private(set) var exits: [Exit] = []
        /// The dwell payload exactly as the tracker receives it.
        private(set) var dwellContexts: [GeofenceDwellContext] = []

        func trackTransition(geofenceId: String, transition: GeofenceTransition, occurredAt: Date) async {
            delivered.append(Delivered(id: geofenceId, transition: transition, occurredAt: occurredAt))
        }

        func trackDwell(
            geofenceId: String, occurredAt: Date, context: GeofenceDwellContext, expectedUserId: String?
        ) async -> Bool {
            delivered.append(Delivered(id: geofenceId, transition: .dwell, occurredAt: occurredAt))
            dwellContexts.append(context)
            return true
        }

        func trackExit(geofenceId: String, occurredAt: Date, expectedUserId: String?) async {
            delivered.append(Delivered(id: geofenceId, transition: .exit, occurredAt: occurredAt))
            exits.append(Exit(expectedUserId: expectedUserId))
        }

        func dwellContextSnapshot() -> [GeofenceDwellContext] {
            dwellContexts
        }

        func exitSnapshot() -> [Exit] {
            exits
        }

        func snapshot() -> [Delivered] {
            delivered
        }
    }

    /// ~360 m square on the origin, so a precise fix at the centre is decisive.
    private static let squareVertices = [
        LocationData(latitude: -0.0016, longitude: -0.0016),
        LocationData(latitude: -0.0016, longitude: 0.0016),
        LocationData(latitude: 0.0016, longitude: 0.0016),
        LocationData(latitude: 0.0016, longitude: -0.0016)
    ]

    /// Predates the wake but stays well inside `movementFixMaxAge`.
    private static let ageInsideGate: TimeInterval = 5

    private func polygonGeofence(
        id: String = "1",
        transitionTypes: Set<GeofenceTransition> = [.enter, .exit],
        radius: Double = 300,
        dwellThresholdSeconds: Int = 0
    ) -> Geofence {
        Geofence(
            id: id, latitude: 0, longitude: 0, radius: radius, name: "poly",
            transitionTypes: transitionTypes, lastUpdated: clock.now, vertices: Self.squareVertices,
            dwellThresholdSeconds: dwellThresholdSeconds
        )
    }

    /// The fence after a refresh moved its ring; the server moves the covering circle with it.
    private func replacedPolygonGeofence(id: String = "1") -> Geofence {
        Geofence(
            id: id, latitude: 0, longitude: 0.005, radius: 300, name: "poly",
            transitionTypes: [.enter, .exit], lastUpdated: clock.now,
            vertices: Self.squareVertices.map {
                LocationData(latitude: $0.latitude, longitude: $0.longitude + 0.005)
            }
        )
    }

    private func circleGeofence(id: String = "2", dwellThresholdSeconds: Int = 0) -> Geofence {
        Geofence(
            id: id, latitude: 0, longitude: 0, radius: 300, name: "circle",
            transitionTypes: [.enter, .exit], lastUpdated: clock.now,
            dwellThresholdSeconds: dwellThresholdSeconds
        )
    }

    // MARK: - Held-fix selection

    @Test
    func heldFixUse_givenResolverDeliveredANewerFix_expectTheNewerFixUsed() async {
        let setup = await makeSetup(fix: nil)
        let held = ResolvedFix(fix(latitude: 0, longitude: 0, at: clock.now.addingTimeInterval(-5)))
        let newer = fix(latitude: 1, longitude: 1, at: clock.now)
        setup.fixResolver.handleResolvedFix(newer)

        let decision = setup.resolver.heldFixUse(held)

        #expect(decision.use == .newer)
        #expect(decision.newerFix?.timestamp == newer.timestamp)
    }

    @Test
    func passFix_givenANewerFixIsHeld_expectItIsUsedWithoutARequest() async {
        // `fix: nil` makes any request fail, so a pass that needs one decides nothing.
        let setup = await makeSetup(fix: nil)
        let held = ResolvedFix(fix(latitude: 0, longitude: 0, at: clock.now.addingTimeInterval(-5)))
        let newer = fix(latitude: 1, longitude: 1, at: clock.now)
        setup.fixResolver.handleResolvedFix(newer)
        let decision = setup.resolver.heldFixUse(held)

        let chosen = await setup.resolver.passFix(heldFix: held, decision: decision, requiringFresh: true)

        #expect(chosen?.location.timestamp == newer.timestamp)
    }

    @Test
    func heldFixUse_givenANewerFixIsHeld_expectTheNewerFixAge() async {
        let setup = await makeSetup(fix: nil)
        let held = ResolvedFix(fix(latitude: 0, longitude: 0, at: clock.now.addingTimeInterval(-20)))
        setup.fixResolver.handleResolvedFix(fix(latitude: 1, longitude: 1, at: clock.now))

        let decision = setup.resolver.heldFixUse(held)

        #expect(decision.age < 5)
    }

    @Test
    func heldFixUse_givenTheNewerFixIsAlsoPastTheCap_expectTooOld() async {
        let setup = await makeSetup(fix: nil)
        let cap = GeofenceConstants.movementFixMaxAge
        let held = ResolvedFix(fix(latitude: 0, longitude: 0, at: clock.now.addingTimeInterval(-(cap + 20))))
        setup.fixResolver.handleResolvedFix(fix(latitude: 1, longitude: 1, at: clock.now.addingTimeInterval(-(cap + 5))))

        let decision = setup.resolver.heldFixUse(held)

        #expect(decision.use == .tooOld)
        #expect(decision.newerFix == nil)
        // The age bound is what discriminates: ~cap+5 from the newer fix, ~cap+20 without the
        // substitution.
        #expect(decision.age < GeofenceConstants.movementFixMaxAge + 10)
    }

    @Test
    func heldFixUse_givenNothingNewerDelivered_expectReused() async {
        let setup = await makeSetup(fix: nil)
        let delivered = fix(latitude: 0, longitude: 0, at: clock.now.addingTimeInterval(-5))
        setup.fixResolver.handleResolvedFix(delivered)

        let decision = setup.resolver.heldFixUse(ResolvedFix(delivered))

        #expect(decision.use == .reused)
    }

    @Test
    func heldFixUse_givenHeldFixPastTheAgeCap_expectTooOld() async {
        let setup = await makeSetup(fix: nil)
        let stale = clock.now.addingTimeInterval(-(GeofenceConstants.movementFixMaxAge + 5))

        let decision = setup.resolver.heldFixUse(ResolvedFix(fix(latitude: 0, longitude: 0, at: stale)))

        #expect(decision.use == .tooOld)
    }

    /// user-1 was identified when the OS delivered this exit and owns the open visit; user-2 signed
    /// in before routing. The crossing may not reach delivery as user-2's.
    @Test
    func circleExit_givenUserSwitchedAfterDelivery_expectDeliveryBoundToTheReceivingUser() async {
        let setup = await makeSetup(fix: nil, withDwellCoordinator: true)
        let circle = circleGeofence(dwellThresholdSeconds: 60)
        await setup.storage.setCachedGeofences([circle])
        await setup.resolver.handleTransition(
            identifier: circle.id, transition: .enter, occurredAt: clock.now.addingTimeInterval(-75)
        )
        setup.contextStore.setUserId("user-2")

        await setup.resolver.handleTransition(
            identifier: circle.id, transition: .exit, occurredAt: clock.now, receivedForUserId: "user-1"
        )

        let exits = await setup.emitter.exitSnapshot()
        #expect(exits.count == 1)
        #expect(exits.first?.expectedUserId == "user-1")
    }

    /// Holds the first ENTER inside the tracker — an HTTP send stalled offline or behind a backlog
    /// flush — until released, and counts every EXIT.
    private actor StalledEnterEmitter: GeofenceTransitionEmitting {
        private var stalledSend: CheckedContinuation<Void, Never>?
        private var hasStalled = false
        private(set) var enterIsStalled = false
        private(set) var entersReceived = 0
        private(set) var exitsReceived = 0

        func trackTransition(geofenceId: String, transition: GeofenceTransition, occurredAt: Date) async {
            guard transition == .enter else { return }
            entersReceived += 1
            guard !hasStalled else { return }
            hasStalled = true
            await withCheckedContinuation { continuation in
                stalledSend = continuation
                enterIsStalled = true
            }
        }

        func release() {
            hasStalled = true
            stalledSend?.resume()
            stalledSend = nil
            enterIsStalled = false
        }

        func trackDwell(
            geofenceId: String, occurredAt: Date, context: GeofenceDwellContext, expectedUserId: String?
        ) async -> Bool {
            true
        }

        func trackExit(geofenceId: String, occurredAt: Date, expectedUserId: String?) async {
            exitsReceived += 1
        }
    }

    private func resolver(_ setup: Setup, emitter: GeofenceTransitionEmitting) -> PolygonMembershipResolver {
        PolygonMembershipResolver(
            storage: setup.storage,
            transitionEmitter: emitter,
            logger: setup.logger,
            contextStore: setup.contextStore,
            dateUtil: clock,
            fixResolver: setup.fixResolver,
            notificationCenter: setup.notificationCenter,
            dwellCoordinator: GeofenceDwellCoordinator(
                storage: setup.storage,
                transitionEmitter: emitter,
                contextStore: setup.contextStore,
                logger: setup.logger,
                notificationCenter: setup.notificationCenter,
                // No deadline evidence: these tests are about boundary ordering, not dwell.
                freshFixProvider: { nil }
            )
        )
    }

    private struct Setup {
        let resolver: PolygonMembershipResolver
        let storage: GeofenceStorage
        let emitter: EmitterSpy
        let fixResolver: MovementFixResolver
        let contextStore: BackgroundDeliveryContextStore
        let notificationCenter: NotificationCenter
        let logger: LoggerMock
    }

    private func makeSetup(
        fix: CLLocation?,
        logger: LoggerMock = LoggerMock(),
        contextStore: BackgroundDeliveryContextStore? = nil,
        onFixDelivered: (@Sendable () -> Void)? = nil,
        withDwellCoordinator: Bool = false,
        dwellClock: GeofenceClock = SystemGeofenceClock()
    ) async -> Setup {
        // Own centre: a `willEnterForeground` on the default one reaches every other test's resolver.
        let notificationCenter = NotificationCenter()
        let contextStore = contextStore ?? BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        if contextStore.currentUserId == nil { contextStore.setUserId("user-1") }
        let storage = GeofenceStorage(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            dateUtil: clock
        )
        // Beliefs exist only for registered polygons; otherwise every write is
        // `.suppressedUnmonitored`.
        await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: ["1"])
        let emitter = EmitterSpy()
        let fixResolver = MovementFixResolver(logger: LoggerMock(), dateUtil: clock)
        fixResolver.systemCachedFix = { nil } // never touch CoreLocation from a unit test
        fixResolver.requestFreshFix = { [weak fixResolver] in
            guard let fix else { return fixResolver?.handleRequestFailure() ?? () }
            fixResolver?.handleResolvedFix(fix)
            onFixDelivered?()
        }
        let dwellCoordinator = withDwellCoordinator ? GeofenceDwellCoordinator(
            storage: storage,
            transitionEmitter: emitter,
            contextStore: contextStore,
            logger: logger,
            notificationCenter: notificationCenter,
            clock: dwellClock
        ) : nil
        return Setup(
            resolver: PolygonMembershipResolver(
                storage: storage,
                transitionEmitter: emitter,
                logger: logger,
                contextStore: contextStore,
                dateUtil: clock,
                fixResolver: fixResolver,
                notificationCenter: notificationCenter,
                dwellCoordinator: dwellCoordinator
            ),
            storage: storage,
            emitter: emitter,
            fixResolver: fixResolver,
            contextStore: contextStore,
            notificationCenter: notificationCenter,
            logger: logger
        )
    }

    private func fix(
        latitude: Double,
        longitude: Double,
        accuracy: Double = 5,
        at timestamp: Date? = nil
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 5,
            timestamp: timestamp ?? clock.now
        )
    }

    private final class RequestCounter: @unchecked Sendable {
        var count = 0
    }

    private final class Flag: @unchecked Sendable {
        var value = false
    }

    private func logged(_ logger: LoggerMock, _ needle: String) -> Bool {
        logger.debugReceivedInvocations.contains { $0.message.contains(needle) }
    }

    /// Same ring a degree away, so a point decisively inside the original is decisively outside this.
    private func movedPolygonGeofence(id: String = "1") -> Geofence {
        Geofence(
            id: id, latitude: 1, longitude: 1, radius: 300, name: "poly",
            transitionTypes: [.enter, .exit], lastUpdated: clock.now,
            vertices: Self.squareVertices.map {
                LocationData(latitude: $0.latitude + 1, longitude: $0.longitude + 1)
            }
        )
    }

    private func countingRequests(_ setup: Setup) -> RequestCounter {
        let counter = RequestCounter()
        setup.fixResolver.requestFreshFix = { [weak fixResolver = setup.fixResolver] in
            counter.count += 1
            fixResolver?.handleRequestFailure()
        }
        return counter
    }

    private func registerPolygons(_ setup: Setup, ids: [String]) async {
        await setup.storage.recordRegistration(
            center: LocationData(latitude: 0, longitude: 0), businessIds: Set(ids)
        )
        await setup.storage.setCachedGeofences(ids.map { polygonGeofence(id: $0) })
    }

    // MARK: - One fix per pass

    @Test
    func evaluateAllPolygons_givenNoFixAvailable_expectOneRequestForTheWholePass() async {
        let setup = await makeSetup(fix: nil)
        await registerPolygons(setup, ids: ["1", "2", "3"])
        let counter = countingRequests(setup)

        await setup.resolver.evaluateAllPolygons(reason: .foreground)

        #expect(counter.count == 1)
    }

    @Test
    func evaluateAllPolygons_givenConcurrentPasses_expectSecondSkipped() async {
        let setup = await makeSetup(fix: nil)
        await registerPolygons(setup, ids: ["1", "2"])
        let counter = countingRequests(setup)

        async let first: Void = setup.resolver.evaluateAllPolygons(reason: .foreground)
        async let second: Void = setup.resolver.evaluateAllPolygons(reason: .foreground)
        _ = await(first, second)

        #expect(counter.count == 1)
    }

    /// The first pass is held inside its request: `async let` doesn't order start-up, and a request
    /// count can't tell "skipped" from "coalesced".
    @Test
    func evaluateAllPolygons_givenFreshRequiredDuringForegroundPass_expectNotSkipped() async {
        let logger = LoggerMock()
        let setup = await makeSetup(fix: nil, logger: logger)
        await registerPolygons(setup, ids: ["1", "2"])
        let gate = gatingRequests(setup)

        async let foreground: Void = setup.resolver.evaluateAllPolygons(reason: .foreground)
        await yieldUntil { !gate.releases.isEmpty }
        async let wake: Void = setup.resolver.evaluateAllPolygons(reason: .foreground, requiresFreshFix: true)
        await settle()
        gate.releaseAll()
        _ = await(foreground, wake)

        #expect(skipCount(logger) == 0)
    }

    @Test
    func evaluateAllPolygons_givenFreshRequiredDuringFreshPass_expectNotSkipped() async {
        let logger = LoggerMock()
        let setup = await makeSetup(fix: nil, logger: logger)
        await registerPolygons(setup, ids: ["1", "2"])
        let gate = gatingRequests(setup)

        async let firstWake: Void = setup.resolver.evaluateAllPolygons(reason: .foreground, requiresFreshFix: true)
        await yieldUntil { !gate.releases.isEmpty }
        async let secondWake: Void = setup.resolver.evaluateAllPolygons(reason: .foreground, requiresFreshFix: true)
        await settle()
        #expect(gate.releases.count == 1, "expected the second wake to coalesce, got \(gate.releases.count) requests")
        gate.releaseAll()
        _ = await(firstWake, secondWake)

        #expect(skipCount(logger) == 0)
    }

    @Test
    func evaluateAllPolygons_givenForegroundDuringFreshPass_expectSkipped() async {
        let logger = LoggerMock()
        let setup = await makeSetup(fix: nil, logger: logger)
        await registerPolygons(setup, ids: ["1", "2"])
        let gate = gatingRequests(setup)

        async let wake: Void = setup.resolver.evaluateAllPolygons(reason: .foreground, requiresFreshFix: true)
        await yieldUntil { !gate.releases.isEmpty }
        async let foreground: Void = setup.resolver.evaluateAllPolygons(reason: .foreground)
        await settle()
        gate.releaseAll()
        _ = await(wake, foreground)

        #expect(skipCount(logger) == 1)
    }

    private final class RequestGate {
        var releases: [() -> Void] = []
        func releaseAll() {
            let pending = releases
            releases = []
            pending.forEach { $0() }
        }
    }

    private func gatingRequests(_ setup: Setup) -> RequestGate {
        let gate = RequestGate()
        setup.fixResolver.requestFreshFix = { [weak fixResolver = setup.fixResolver] in
            gate.releases.append { fixResolver?.handleRequestFailure() }
        }
        return gate
    }

    private func yieldUntil(_ condition: () -> Bool) async {
        for _ in 0 ..< 1000 where !condition() {
            await Task.yield()
        }
    }

    /// Bounded, so a condition that never holds fails its expectation instead of hanging the suite.
    private func waitUntil(_ condition: () async -> Bool) async {
        for _ in 0 ..< 1000 {
            if await condition() { return }
            await Task.yield()
        }
    }

    /// Lets a just-started task reach its first suspension point.
    private func settle() async {
        for _ in 0 ..< 20 {
            await Task.yield()
        }
    }

    private func skipCount(_ logger: LoggerMock) -> Int {
        logger.debugReceivedInvocations
            .filter { $0.message.contains("Skipped polygon evaluation pass") }
            .count
    }

    // MARK: - Circle fences pass through untouched

    @Test
    func handleTransition_givenCircleGeofence_expectForwardedUnchanged() async {
        let setup = await makeSetup(fix: nil)
        await setup.storage.setCachedGeofences([circleGeofence()])

        await setup.resolver.handleTransition(identifier: "2", transition: .enter, occurredAt: clock.now)

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1)
        #expect(delivered.first?.transition == .enter)
    }

    /// A sync can drop a geofence while the OS still holds its condition. The crossing is still
    /// real, so it is forwarded as the circle it was before polygons existed — bound to the user
    /// who received it and carrying no visit, there being no fence to measure it against.
    @Test
    func handleTransition_givenUncachedGeofenceExit_expectForwardedForTheReceivingUser() async {
        let setup = await makeSetup(fix: nil, withDwellCoordinator: true)

        await setup.resolver.handleTransition(
            identifier: "999", transition: .exit, occurredAt: clock.now, receivedForUserId: "user-1"
        )

        #expect(await setup.emitter.snapshot().map(\.transition) == [.exit])
        let exits = await setup.emitter.exitSnapshot()
        #expect(exits.first?.expectedUserId == "user-1")
    }

    @Test
    func handleTransition_givenUncachedGeofenceEnter_expectForwarded() async {
        let setup = await makeSetup(fix: nil, withDwellCoordinator: true)

        await setup.resolver.handleTransition(
            identifier: "999", transition: .enter, occurredAt: clock.now, receivedForUserId: "user-1"
        )

        #expect(await setup.emitter.snapshot() == [.init(id: "999", transition: .enter, occurredAt: clock.now)])
    }

    /// An exit-only dwell circle is registered for ENTER only so its visit has a start. Once the
    /// cache has dropped it, that ENTER must still not reach the customer; its configured EXIT still does.
    @Test
    func handleTransition_givenUncachedExitDwellCircle_expectBookkeepingEnterDroppedAndExitForwarded() async {
        let setup = await makeSetup(fix: nil, withDwellCoordinator: true)
        let exitOnly = Geofence(
            id: "999", latitude: 0, longitude: 0, radius: 300, name: "exit only",
            transitionTypes: [.exit], lastUpdated: clock.now, dwellThresholdSeconds: 60
        )
        await setup.storage.recordRegistrationIntent(for: [exitOnly], pruningToCache: true)

        await setup.resolver.handleTransition(
            identifier: "999", transition: .enter, occurredAt: clock.now, receivedForUserId: "user-1"
        )
        await setup.resolver.handleTransition(
            identifier: "999", transition: .exit, occurredAt: clock.now, receivedForUserId: "user-1"
        )

        #expect(await setup.emitter.snapshot().map(\.transition) == [.exit])
        #expect(logged(setup.logger, "not routed: transition_not_configured"))
    }

    /// A dwell-only circle configured neither edge: both are bookkeeping once it is uncached.
    @Test
    func handleTransition_givenUncachedDwellOnlyCircle_expectBothEdgesDropped() async {
        let setup = await makeSetup(fix: nil, withDwellCoordinator: true)
        let dwellOnly = Geofence(
            id: "999", latitude: 0, longitude: 0, radius: 300, name: "dwell only",
            transitionTypes: [], lastUpdated: clock.now, dwellThresholdSeconds: 60
        )
        await setup.storage.recordRegistrationIntent(for: [dwellOnly], pruningToCache: true)

        await setup.resolver.handleTransition(
            identifier: "999", transition: .enter, occurredAt: clock.now, receivedForUserId: "user-1"
        )
        await setup.resolver.handleTransition(
            identifier: "999", transition: .exit, occurredAt: clock.now, receivedForUserId: "user-1"
        )

        #expect(await setup.emitter.snapshot().isEmpty)
    }

    /// The legacy behaviour for a configured ENTER is untouched: dropped from the cache, still forwarded.
    @Test
    func handleTransition_givenUncachedEnterConfiguredCircle_expectEnterStillForwarded() async {
        let setup = await makeSetup(fix: nil, withDwellCoordinator: true)
        let configured = Geofence(
            id: "999", latitude: 0, longitude: 0, radius: 300, name: "configured",
            transitionTypes: [.enter, .exit], lastUpdated: clock.now, dwellThresholdSeconds: 60
        )
        await setup.storage.recordRegistrationIntent(for: [configured], pruningToCache: true)

        await setup.resolver.handleTransition(
            identifier: "999", transition: .enter, occurredAt: clock.now, receivedForUserId: "user-1"
        )

        #expect(await setup.emitter.snapshot() == [.init(id: "999", transition: .enter, occurredAt: clock.now)])
    }

    /// The forward is not a licence to reattribute: an ENTER received for user-1 is dropped once
    /// user-2 has signed in, exactly as it is for a cached circle.
    @Test
    func handleTransition_givenUncachedGeofenceEnterAfterUserSwitch_expectDropped() async {
        let setup = await makeSetup(fix: nil, withDwellCoordinator: true)
        setup.contextStore.setUserId("user-2")

        await setup.resolver.handleTransition(
            identifier: "999", transition: .enter, occurredAt: clock.now, receivedForUserId: "user-1"
        )

        #expect(await setup.emitter.snapshot().isEmpty)
    }

    /// The ENTER is the event; the visit is best-effort bookkeeping behind a storage round trip.
    /// Recording the visit first put that round trip before the ENTER's user check, and a sign-out
    /// queued behind the callback ran inside it and dropped the crossing.
    @Test
    func circleEnter_givenSignOutQueuedBehindIt_expectEnterStillTracked() async {
        let setup = await makeSetup(fix: nil)
        let circle = circleGeofence()
        await setup.storage.setCachedGeofences([circle])
        let emitter = StalledEnterEmitter()
        await emitter.release() // nothing stalls: only whether the ENTER arrives is under test
        let resolver = resolver(setup, emitter: emitter)

        let enter = Task { @MainActor in
            await resolver.forwardCircleTransition(
                geofence: circle, transition: .enter, occurredAt: clock.now, receivedForUserId: "user-1"
            )
        }
        let signOut = Task { @MainActor in setup.contextStore.setUserId(nil) }
        await enter.value
        await signOut.value

        #expect(await emitter.entersReceived == 1)
    }

    /// A stalled ENTER send must not hold the visit write behind it. When it did, the EXIT found no
    /// visit and the write then landed for a device already outside, leaving a visit that could
    /// qualify a dwell for a stay that had ended.
    @Test
    func circleVisit_givenEnterSendStalledAcrossExitAndReentry_expectEachExitEndsItsOwnVisit() async {
        let setup = await makeSetup(fix: nil)
        let circle = circleGeofence(dwellThresholdSeconds: 60)
        await setup.storage.setCachedGeofences([circle])
        let emitter = StalledEnterEmitter()
        let resolver = resolver(setup, emitter: emitter)
        // Whole seconds: a visit's `enteredAt` round-trips through JSON, and a fractional one
        // comes back a hair off.
        let firstEntry = Date(timeIntervalSince1970: clock.now.timeIntervalSince1970.rounded(.down) - 7200)
        let firstExit = firstEntry.addingTimeInterval(60)
        let reentry = firstEntry.addingTimeInterval(3600)
        let finalExit = reentry.addingTimeInterval(120)

        let stalledEnter = Task { @MainActor in
            await resolver.handleTransition(
                identifier: circle.id, transition: .enter, occurredAt: firstEntry, receivedForUserId: "user-1"
            )
        }
        await waitUntil { await emitter.enterIsStalled }
        #expect(await emitter.enterIsStalled)
        await waitUntil { await setup.storage.getDwellVisit(geofenceId: circle.id) != nil }
        #expect(await setup.storage.getDwellVisit(geofenceId: circle.id)?.enteredAt == firstEntry)

        await resolver.handleTransition(
            identifier: circle.id, transition: .exit, occurredAt: firstExit, receivedForUserId: "user-1"
        )
        await emitter.release()
        _ = await stalledEnter.value
        #expect(await setup.storage.getDwellVisit(geofenceId: circle.id) == nil)

        await resolver.handleTransition(
            identifier: circle.id, transition: .enter, occurredAt: reentry, receivedForUserId: "user-1"
        )
        #expect(await setup.storage.getDwellVisit(geofenceId: circle.id)?.enteredAt == reentry)
        await resolver.handleTransition(
            identifier: circle.id, transition: .exit, occurredAt: finalExit, receivedForUserId: "user-1"
        )

        #expect(await emitter.exitsReceived == 2)
        #expect(await setup.storage.getDwellVisit(geofenceId: circle.id) == nil)
    }

    // MARK: - Covering-circle enter

    @Test
    func applyGivenPolygonMembershipChangesStartsOnlyConfirmedVisits() async {
        let setup = await makeSetup(fix: nil, withDwellCoordinator: true)
        let geofence = polygonGeofence(transitionTypes: [.exit], dwellThresholdSeconds: 60)
        await setup.storage.setCachedGeofences([geofence])
        let firstEntry = Date(timeIntervalSince1970: 1000)

        await setup.resolver.apply(.inside, to: geofence, evidence: firstEntry, confirmedByFix: true)
        let firstVisit = await setup.storage.getDwellVisit(geofenceId: geofence.id)
        await setup.resolver.apply(
            .inside,
            to: geofence,
            evidence: firstEntry.addingTimeInterval(10),
            confirmedByFix: true
        )
        #expect(await setup.storage.getDwellVisit(geofenceId: geofence.id) == firstVisit)

        await setup.resolver.apply(
            .outside,
            to: geofence,
            evidence: firstEntry.addingTimeInterval(20),
            confirmedByFix: true
        )
        let secondEntry = firstEntry.addingTimeInterval(30)
        await setup.resolver.apply(.inside, to: geofence, evidence: secondEntry, confirmedByFix: true)

        let secondVisit = await setup.storage.getDwellVisit(geofenceId: geofence.id)
        #expect(secondVisit?.visitId != firstVisit?.visitId)
        #expect(secondVisit?.enteredAt == secondEntry)
    }

    @Test
    func handleTransition_givenPolygonEnterAndFixInside_expectEnterDelivered() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: clock.now)

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1)
        #expect(delivered.first?.transition == .enter)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    /// Asserts polygon 3 too: a per-polygon "first one pays" flag would hand later polygons the
    /// pre-wake fix.
    @Test
    func evaluateAllPolygons_givenFreshFixRequiredButRequestFails_expectEveryPolygonUndecided() async {
        let setup = await makeSetup(fix: nil) // the forced request fails
        setup.fixResolver.handleResolvedFix(fix(latitude: 0, longitude: 0)) // pre-wake fix, inside
        await setup.storage.recordRegistration(
            center: LocationData(latitude: 0, longitude: 0), businessIds: ["1", "3"]
        )
        await setup.storage.setCachedGeofences([polygonGeofence(), polygonGeofence(id: "3")])

        await setup.resolver.evaluateAllPolygons(reason: .foreground, requiresFreshFix: true)

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"] == nil)
        #expect(await setup.storage.getPolygonMembership()["3"] == nil)
    }

    /// The `systemCachedFix` seam is live here on purpose; every other test stubs it to nil.
    @Test
    func handleTransition_givenSystemCacheAlwaysCurrent_expectEnterStillDelivered() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        // A cache the OS keeps refreshing: every read is "now".
        setup.fixResolver.systemCachedFix = { [weak fixResolver = setup.fixResolver] in
            _ = fixResolver
            return CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: clock.now
            )
        }
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: clock.now)

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1, "verdict was refused; got \(delivered)")
        #expect(delivered.first?.transition == .enter)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    /// Resolves through the delegate: the `handleResolvedFix` seam bypasses its filters.
    @Test
    func handleTransition_givenFixArrivingThroughTheDelegate_expectEnterDelivered() async {
        let setup = await makeSetup(fix: nil)
        setup.fixResolver.requestFreshFix = { [weak fixResolver = setup.fixResolver] in
            fixResolver?.locationManager(CLLocationManager(), didUpdateLocations: [
                fix(latitude: 0, longitude: 0)
            ])
        }
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: clock.now)

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1)
        #expect(delivered.first?.transition == .enter)
    }

    /// Known limit, pinned: on a cold process an echoed pre-wake fix inside `movementFixMaxAge`
    /// still decides.
    @Test
    func handleTransition_givenColdProcessAndEchoedPreWakeFix_expectVerdictFromTheStaleEcho() async {
        let setup = await makeSetup(fix: nil) // cold: nothing delivered, no system cache
        let preWakeFix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            timestamp: clock.now.addingTimeInterval(-Self.ageInsideGate)
        )
        setup.fixResolver.requestFreshFix = { [weak fixResolver = setup.fixResolver] in
            fixResolver?.locationManager(CLLocationManager(), didUpdateLocations: [preWakeFix])
        }
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: clock.now)

        #expect(await setup.emitter.snapshot().count == 1)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    @Test
    func evaluateAllPolygons_givenStaleDeliveredFixAndFreshSystemCache_expectTheFreshOneDecides() async {
        let setup = await makeSetup(fix: nil)
        // Outside the polygon and deliberately inside `movementFixMaxAge`, so the age gate can't be
        // what refuses it.
        setup.fixResolver.handleResolvedFix(CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0.01, longitude: 0.01),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            timestamp: clock.now.addingTimeInterval(-Self.ageInsideGate)
        ))
        // The system cache has moved on and sits inside the polygon, well within the age gate.
        setup.fixResolver.systemCachedFix = {
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: clock.now
            )
        }
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.evaluateAllPolygons(reason: .foreground)

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1, "decided from the stale delivered fix; got \(delivered)")
        #expect(delivered.first?.transition == .enter)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    /// Doesn't guard the `cached: nil` coupling;
    /// `handleTransition_givenSystemCacheAlwaysCurrent_expectEnterStillDelivered` does.
    @Test
    func handleTransition_givenFreshRequiredAndStaleHeldFix_expectNoVerdictFromIt() async {
        let setup = await makeSetup(fix: nil) // the forced request fails
        // Held, inside the polygon, and young enough that the fast path WOULD accept it as fresh.
        setup.fixResolver.handleResolvedFix(CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            timestamp: clock.now.addingTimeInterval(-Self.ageInsideGate)
        ))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: clock.now)

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"] == nil)
    }

    @Test
    func handleTransition_givenFreshFixRequiredButRequestFails_expectNoVerdictFromHeldFix() async {
        let setup = await makeSetup(fix: nil) // the forced request fails
        setup.fixResolver.handleResolvedFix(fix(latitude: 0, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: clock.now)

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"] == nil)
    }

    @Test
    func handleTransition_givenFreshFixRequiredOnFirstWake_expectNoVerdictFromSystemCache() async {
        let setup = await makeSetup(fix: nil) // the forced request fails
        setup.fixResolver.systemCachedFix = { fix(latitude: 0, longitude: 0) }
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: clock.now)

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"] == nil)
    }

    @Test
    func handleTransition_givenStoredRingThatCannotBuild_expectNothingForwarded() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        let degenerate = Geofence(
            id: "1", latitude: 0, longitude: 0, radius: 300, name: "poly",
            transitionTypes: [.enter, .exit], lastUpdated: clock.now,
            vertices: [LocationData(latitude: 0, longitude: 0), LocationData(latitude: 0, longitude: 0)]
        )
        await setup.storage.setCachedGeofences([degenerate])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: clock.now)

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"] == nil)
    }

    @Test
    func handleTransition_givenStoredRingThatCannotBuild_expectExitStillApplied() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])
        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: clock.now)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)

        let degenerate = Geofence(
            id: "1", latitude: 0, longitude: 0, radius: 300, name: "poly",
            transitionTypes: [.enter, .exit], lastUpdated: clock.now,
            vertices: [LocationData(latitude: 0, longitude: 0), LocationData(latitude: 0, longitude: 0)]
        )
        await setup.storage.setCachedGeofences([degenerate])
        // Dated after the enter, as a real exit would be.
        clock.givenNow = clock.now.addingTimeInterval(1)

        await setup.resolver.handleTransition(identifier: "1", transition: .exit, occurredAt: clock.now)

        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .outside)
        #expect(await setup.emitter.snapshot().map(\.transition) == [.enter, .exit])
    }

    @Test
    func handleTransition_givenExitOlderThanBelief_expectSuppressed() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])
        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: clock.now)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)

        await setup.resolver.handleTransition(
            identifier: "1", transition: .exit, occurredAt: Date(timeIntervalSince1970: 0)
        )

        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
        #expect(await setup.emitter.snapshot().map(\.transition) == [.enter])
    }

    @Test
    func evaluateMembership_givenUserChangesWhileResolving_expectNoBeliefAndNoEvent() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.evaluateMembership(
            geofenceIds: ["1"], reason: .foreground, isStillCurrent: { false }
        )

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"] == nil)
    }

    /// Control for the test above.
    @Test
    func evaluateMembership_givenUserUnchanged_expectVerdictRecorded() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.evaluateMembership(
            geofenceIds: ["1"], reason: .foreground, isStillCurrent: { true }
        )

        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    @Test
    func evaluateMembership_givenPolygonReplacedWhileFixPending_expectVerdictFromTheCurrentRing() async {
        let setup = await makeSetup(fix: nil)
        await registerPolygons(setup, ids: ["1"])
        let requested = Flag()
        setup.fixResolver.requestFreshFix = { requested.value = true }

        async let pass: Bool = setup.resolver.evaluateMembership(geofenceIds: ["1"], reason: .foreground)
        await yieldUntil { requested.value }
        await setup.storage.setCachedGeofences([movedPolygonGeofence()])
        setup.fixResolver.handleResolvedFix(fix(latitude: 0, longitude: 0))
        _ = await pass

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .outside)
    }

    /// Control for the test above.
    @Test
    func evaluateMembership_givenCatalogUnchangedWhileFixPending_expectEnterDelivered() async {
        let setup = await makeSetup(fix: nil)
        await registerPolygons(setup, ids: ["1"])
        let requested = Flag()
        setup.fixResolver.requestFreshFix = { requested.value = true }

        async let pass: Bool = setup.resolver.evaluateMembership(geofenceIds: ["1"], reason: .foreground)
        await yieldUntil { requested.value }
        setup.fixResolver.handleResolvedFix(fix(latitude: 0, longitude: 0))
        _ = await pass

        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
        #expect(await setup.emitter.snapshot().map(\.transition) == [.enter])
    }

    @Test
    func evaluateMembership_givenSeveralNewPolygons_expectOneRequestForTheBatch() async {
        let setup = await makeSetup(fix: nil)
        await registerPolygons(setup, ids: ["1", "2", "3"])
        let counter = countingRequests(setup)

        await setup.resolver.evaluateMembership(geofenceIds: ["1", "2", "3"], reason: .foreground)

        #expect(counter.count == 1)
    }

    /// Annulus: inside the covering circle, outside the polygon.
    @Test
    func handleTransition_givenPolygonEnterAndFixInAnnulus_expectNoEvent() async {
        let setup = await makeSetup(fix: fix(latitude: 0.0024, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: clock.now)

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .outside)
    }

    @Test
    func handleTransition_givenUndecidableFix_expectNoBelief() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0, accuracy: 400))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: clock.now)

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"] == nil)
    }

    @Test
    func handleTransition_givenNoFixObtainable_expectNothingRecorded() async {
        let setup = await makeSetup(fix: nil)
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: clock.now)

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"] == nil)
    }

    // MARK: - Covering-circle exit

    @Test
    func handleTransition_givenPolygonExitWhileInside_expectExitDeliveredWithoutFix() async {
        let setup = await makeSetup(fix: nil)
        await setup.storage.setCachedGeofences([polygonGeofence()])
        _ = await setup.storage.recordPolygonMembership(.inside, forIdentifier: "1", now: clock.now.addingTimeInterval(-1))

        await setup.resolver.handleTransition(identifier: "1", transition: .exit, occurredAt: clock.now)

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1)
        #expect(delivered.first?.transition == .exit)
    }

    @Test
    func handleTransition_givenExitRaisedForAReplacedCircle_expectRefusedAndBeliefKept() async {
        let setup = await makeSetup(fix: nil)
        let original = polygonGeofence()
        await setup.storage.setCachedGeofences([original])
        _ = await setup.storage.recordPolygonMembership(.inside, forIdentifier: "1", now: clock.now.addingTimeInterval(-1))
        await setup.storage.setCachedGeofences([replacedPolygonGeofence()])

        await setup.resolver.handleTransition(
            identifier: "1", transition: .exit, occurredAt: clock.now,
            eventCircle: .circle(MonitoredCircle(
                center: LocationData(latitude: original.latitude, longitude: original.longitude),
                radius: original.radius, maximumRadius: 1000
            ))
        )

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    /// Control for the test above.
    @Test
    func handleTransition_givenExitRaisedForTheCurrentCircle_expectExitDelivered() async {
        let setup = await makeSetup(fix: nil)
        let geofence = polygonGeofence()
        await setup.storage.setCachedGeofences([geofence])
        _ = await setup.storage.recordPolygonMembership(.inside, forIdentifier: "1", now: clock.now.addingTimeInterval(-1))

        await setup.resolver.handleTransition(
            identifier: "1", transition: .exit, occurredAt: clock.now,
            eventCircle: .circle(MonitoredCircle(
                center: LocationData(latitude: geofence.latitude, longitude: geofence.longitude),
                radius: geofence.radius, maximumRadius: 1000
            ))
        )

        #expect(await setup.emitter.snapshot().first?.transition == .exit)
    }

    /// Built from a real ledger history, not `.expired` directly. The belief predates the event, or
    /// evidence order would refuse it before the geometry guard.
    @Test
    func handleTransition_givenAnExitOlderThanEveryHeldGeneration_expectRefusedAndBeliefKept() async {
        let setup = await makeSetup(fix: nil)
        var ledger = RegisteredConditionLedger()
        let raisedAt = clock.now.addingTimeInterval(-90)
        let firstLiveAt = clock.now.addingTimeInterval(-60)
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0),
            radius: 300, transitionTypes: [.enter, .exit], at: firstLiveAt, liveFrom: firstLiveAt
        )
        let secondStagedAt = clock.now.addingTimeInterval(-30)
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0.005),
            radius: 300, transitionTypes: [.enter, .exit], at: secondStagedAt
        )
        ledger.confirm("1", stagedAt: secondStagedAt, at: clock.now.addingTimeInterval(-20))

        await setup.storage.setCachedGeofences([polygonGeofence()])
        _ = await setup.storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfBeliefPredates: clock.now.addingTimeInterval(-120), now: clock.now
        )
        await setup.storage.setCachedGeofences([replacedPolygonGeofence()])

        await setup.resolver.handleTransition(
            identifier: "1", transition: .exit, occurredAt: raisedAt,
            eventCircle: GeofenceEventCircle(
                ledger.attribution(for: "1", raisedAt: raisedAt), maximumRadius: 1000
            )
        )

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    /// The OS monitors `min(radius, maximumRegionMonitoringDistance)`, so the event circle is smaller
    /// than the fence's radius.
    @Test
    func handleTransition_givenExitForAnOverCapFence_expectExitDelivered() async {
        let setup = await makeSetup(fix: nil)
        let geofence = polygonGeofence(radius: 5000)
        await setup.storage.setCachedGeofences([geofence])
        _ = await setup.storage.recordPolygonMembership(.inside, forIdentifier: "1", now: clock.now.addingTimeInterval(-1))

        await setup.resolver.handleTransition(
            identifier: "1", transition: .exit, occurredAt: clock.now,
            eventCircle: .circle(MonitoredCircle(
                center: LocationData(latitude: 0, longitude: 0),
                radius: min(5000, 1000), maximumRadius: 1000
            ))
        )

        #expect(await setup.emitter.snapshot().first?.transition == .exit)
    }

    @Test
    func handleTransition_givenPolygonExitWhileNotInside_expectSilent() async {
        let setup = await makeSetup(fix: nil)
        await setup.storage.setCachedGeofences([polygonGeofence()])
        _ = await setup.storage.recordPolygonMembership(.outside, forIdentifier: "1", now: clock.now.addingTimeInterval(-1))

        await setup.resolver.handleTransition(identifier: "1", transition: .exit, occurredAt: clock.now)

        #expect(await setup.emitter.snapshot().isEmpty)
    }

    // MARK: - Foreground evaluation

    @Test
    func evaluateAllPolygons_givenPolygonReplacedWhileFixPending_expectVerdictFromTheCurrentRing() async {
        let setup = await makeSetup(fix: nil)
        await registerPolygons(setup, ids: ["1"])
        // Hold the pass inside its request so the swap lands strictly between the read and the verdict.
        let requested = Flag()
        setup.fixResolver.requestFreshFix = { requested.value = true }

        async let pass: Void = setup.resolver.evaluateAllPolygons(reason: .foreground)
        await yieldUntil { requested.value }
        await setup.storage.setCachedGeofences([movedPolygonGeofence()])
        setup.fixResolver.handleResolvedFix(fix(latitude: 0, longitude: 0))
        await pass

        // The device is inside the ring the pass started with and outside the one that replaced it.
        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .outside)
    }

    /// Control for the test above.
    @Test
    func evaluateAllPolygons_givenCatalogUnchangedWhileFixPending_expectEnterDelivered() async {
        let setup = await makeSetup(fix: nil)
        await registerPolygons(setup, ids: ["1"])
        let requested = Flag()
        setup.fixResolver.requestFreshFix = { requested.value = true }

        async let pass: Void = setup.resolver.evaluateAllPolygons(reason: .foreground)
        await yieldUntil { requested.value }
        setup.fixResolver.handleResolvedFix(fix(latitude: 0, longitude: 0))
        await pass

        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
        #expect(await setup.emitter.snapshot().map(\.transition) == [.enter])
    }

    /// Outcome only: storage also refuses the create as unmonitored, so this passes without the
    /// resolver's own registration re-read.
    @Test
    func evaluateAllPolygons_givenPolygonUnregisteredWhileFixPending_expectNoVerdict() async {
        let setup = await makeSetup(fix: nil)
        await registerPolygons(setup, ids: ["1"])
        let requested = Flag()
        setup.fixResolver.requestFreshFix = { requested.value = true }

        async let pass: Void = setup.resolver.evaluateAllPolygons(reason: .foreground)
        await yieldUntil { requested.value }
        await setup.storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: [])
        setup.fixResolver.handleResolvedFix(fix(latitude: 0, longitude: 0))
        await pass

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"] == nil)
    }

    @Test
    func evaluateAllPolygons_givenPolygonDroppedWhileFixPending_expectNoVerdict() async {
        let setup = await makeSetup(fix: nil)
        await registerPolygons(setup, ids: ["1"])
        let requested = Flag()
        setup.fixResolver.requestFreshFix = { requested.value = true }

        async let pass: Void = setup.resolver.evaluateAllPolygons(reason: .foreground)
        await yieldUntil { requested.value }
        await setup.storage.setCachedGeofences([])
        setup.fixResolver.handleResolvedFix(fix(latitude: 0, longitude: 0))
        await pass

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"] == nil)
    }

    /// The switch lands at fix delivery; the post-write check is pinned separately below.
    @Test
    func foreground_givenUserChangesWhileResolving_expectNoEvent() async {
        let contextStore = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        contextStore.setUserId("user-1")
        let switched = Flag()
        let setup = await makeSetup(
            fix: fix(latitude: 0, longitude: 0),
            contextStore: contextStore,
            onFixDelivered: {
                contextStore.setUserId("user-2")
                switched.value = true
            }
        )
        await registerPolygons(setup, ids: ["1"])

        setup.notificationCenter.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await yieldUntil { switched.value }
        // Wait on the recorded refusal, not a fixed yield count, or this goes vacuous when the path
        // gains an await.
        await yieldUntil { logged(setup.logger, PolygonUndecidedReason.userChanged.prose) }

        // `yieldUntil` gives up silently, so assert the refusal actually ran.
        #expect(logged(setup.logger, PolygonUndecidedReason.userChanged.prose))
        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"] == nil)
    }

    /// A belief exists, so the write takes the change path, which `monitoredGeofenceIds` doesn't guard.
    /// The write may stand; only the emit is refused.
    @Test
    func evaluateAllPolygons_givenUserChangesAfterTheWrite_expectNoEvent() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        await registerPolygons(setup, ids: ["1"])
        _ = await setup.storage.recordPolygonMembership(
            .outside, forIdentifier: "1", onlyIfBeliefPredates: Date(timeIntervalSince1970: 0), now: clock.now
        )
        // True while the verdict is formed, false by the time the delivery boundary asks.
        let asked = RequestCounter()

        await setup.resolver.evaluateAllPolygons(reason: .foreground, isStillCurrent: {
            asked.count += 1
            return asked.count == 1
        })

        // Dwell adds a second post-write attribution boundary before the existing transition
        // delivery boundary. Both refuse work after this simulated user switch.
        #expect(asked.count == 3)
        // The write said deliver, so the refusal is the switch and not an unchanged belief.
        #expect(logged(setup.logger, "delivered nothing: user_changed"))
        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    @Test
    func evaluateAllPolygons_givenEnterOnlyPolygonDecidedOutside_expectTheFilterNamed() async {
        let setup = await makeSetup(fix: fix(latitude: 5, longitude: 5))
        await setup.storage.recordRegistration(
            center: LocationData(latitude: 0, longitude: 0), businessIds: ["1"]
        )
        await setup.storage.setCachedGeofences([polygonGeofence(id: "1", transitionTypes: [.enter])])
        // Existing belief, so the write takes the change path and returns `.deliver(.exit)`.
        _ = await setup.storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfBeliefPredates: Date(timeIntervalSince1970: 0), now: clock.now
        )

        await setup.resolver.evaluateAllPolygons(reason: .foreground)

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(logged(setup.logger, "delivered nothing: transition_type_not_registered"))
        #expect(!logged(setup.logger, "delivered nothing: deliver"))
    }

    /// Control for `foreground_givenUserChangesWhileResolving_expectNoEvent`.
    @Test
    func foreground_givenUserUnchanged_expectVerdictRecorded() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        await registerPolygons(setup, ids: ["1"])

        setup.notificationCenter.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        for _ in 0 ..< 1000 where await setup.emitter.snapshot().isEmpty {
            await Task.yield()
        }

        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
        #expect(await setup.emitter.snapshot().map(\.transition) == [.enter])
    }

    /// The only test on `.default`, the centre production observes. Safe only while no other test
    /// posts to `.default` or builds the DI singleton.
    @Test
    func foreground_givenTheDefaultNotificationCentre_expectPassRuns() async {
        let storage = GeofenceStorage(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            dateUtil: clock
        )
        await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: ["1"])
        await storage.setCachedGeofences([polygonGeofence()])
        let contextStore = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        contextStore.setUserId("user-1")
        let emitter = EmitterSpy()
        let fixResolver = MovementFixResolver(logger: LoggerMock(), dateUtil: clock)
        fixResolver.systemCachedFix = { nil }
        fixResolver.requestFreshFix = { [weak fixResolver] in
            fixResolver?.handleResolvedFix(CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: clock.now
            ))
        }
        let resolver = PolygonMembershipResolver(
            storage: storage, transitionEmitter: emitter,
            logger: LoggerMock(), contextStore: contextStore, dateUtil: clock, fixResolver: fixResolver
        )

        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        for _ in 0 ..< 1000 where await emitter.snapshot().isEmpty {
            await Task.yield()
        }

        #expect(await emitter.snapshot().map(\.transition) == [.enter])
        _ = resolver
    }

    @Test
    func evaluateAllPolygons_givenDeviceInsideOneRegisteredPolygon_expectEnterForThatOneOnly() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        let distant = Geofence(
            id: "2", latitude: 1, longitude: 1, radius: 300, name: "far",
            transitionTypes: [.enter, .exit], lastUpdated: clock.now,
            vertices: Self.squareVertices.map {
                LocationData(latitude: $0.latitude + 1, longitude: $0.longitude + 1)
            }
        )
        await setup.storage.setCachedGeofences([polygonGeofence(), distant])
        await setup.storage.recordRegistration(
            center: LocationData(latitude: 0, longitude: 0), businessIds: ["1", "2"]
        )

        await setup.resolver.evaluateAllPolygons(reason: .foreground)

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1)
        #expect(delivered.first?.id == "1")
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
        #expect(await setup.storage.getPolygonMembership()["2"]?.membership == .outside)
    }

    @Test
    func evaluateAllPolygons_givenUnregisteredPolygon_expectSkipped() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])
        await setup.storage.recordRegistration(
            center: LocationData(latitude: 0, longitude: 0), businessIds: ["other"]
        )

        await setup.resolver.evaluateAllPolygons(reason: .foreground)

        #expect(await setup.emitter.snapshot().isEmpty)
    }

    // MARK: - Observed entry vs discovered inside

    /// The first verdict for a polygon placing the device inside is discovery: it was never seen
    /// outside, so the stay began at some unknown earlier time. The configured ENTER is still owed,
    /// and the stay still qualifies a DWELL, but that DWELL reports no `enteredAt` or duration.
    @Test
    func apply_givenFirstVerdictInside_expectEnterAndDwellWithoutEnteredAtOrDuration() async {
        let discovered = Date(timeIntervalSince1970: 1000)
        let dwellClock = ManualGeofenceClock(wall: discovered)
        let setup = await makeSetup(fix: nil, withDwellCoordinator: true, dwellClock: dwellClock)
        let geofence = polygonGeofence(dwellThresholdSeconds: 60)
        await setup.storage.setCachedGeofences([geofence])

        await setup.resolver.apply(.inside, to: geofence, evidence: discovered, confirmedByFix: true)
        dwellClock.advance(to: discovered.addingTimeInterval(120))
        await setup.resolver.apply(
            .inside, to: geofence, evidence: discovered.addingTimeInterval(120), confirmedByFix: true
        )

        #expect(await setup.emitter.snapshot().map(\.transition) == [.enter, .dwell])
        let visit = await setup.storage.getDwellVisit(geofenceId: geofence.id)
        #expect(visit?.entryObserved == false)
        #expect(visit?.dwellReservation != nil)
        #expect(visit?.dwellReservation?.enteredAt == nil)
        #expect(visit?.dwellReservation?.durationSeconds == nil)
    }

    /// Outside the OLD ring says nothing about when the device came to be inside the new one: the
    /// replacement may have been drawn around it. The ENTER is still delivered, but the stay it
    /// begins is discovered, so its DWELL reports no `enteredAt` or duration.
    @Test
    func apply_givenOutsideTheReplacedRingThenInsideTheNewOne_expectEnterAndDwellWithoutEnteredAtOrDuration() async {
        let entry = Date(timeIntervalSince1970: 1000)
        let dwellClock = ManualGeofenceClock(wall: entry.addingTimeInterval(-60))
        let setup = await makeSetup(fix: nil, withDwellCoordinator: true, dwellClock: dwellClock)
        let original = polygonGeofence(dwellThresholdSeconds: 60)
        await setup.storage.setCachedGeofences([original])
        await setup.resolver.apply(
            .outside, to: original, evidence: entry.addingTimeInterval(-60), confirmedByFix: true
        )
        let shifted = Self.squareVertices.map { LocationData(latitude: $0.latitude, longitude: $0.longitude + 0.005) }
        let replacement = Geofence(
            id: original.id, latitude: 0, longitude: 0.005, radius: 300, name: "poly",
            transitionTypes: [.enter, .exit], lastUpdated: clock.now, vertices: shifted,
            dwellThresholdSeconds: 60
        )
        await setup.storage.setCachedGeofences([replacement])

        dwellClock.advance(to: entry)
        await setup.resolver.apply(
            .inside, to: replacement, evidence: entry, confirmedByFix: true, evaluatedRing: shifted
        )
        dwellClock.advance(to: entry.addingTimeInterval(120))
        await setup.resolver.apply(
            .inside, to: replacement, evidence: entry.addingTimeInterval(120), confirmedByFix: true,
            evaluatedRing: shifted
        )

        #expect(await setup.emitter.snapshot().map(\.transition) == [.enter, .dwell])
        let visit = await setup.storage.getDwellVisit(geofenceId: replacement.id)
        #expect(visit?.entryObserved == false)
        #expect(visit?.dwellReservation != nil)
        #expect(visit?.dwellReservation?.enteredAt == nil)
        #expect(visit?.dwellReservation?.durationSeconds == nil)
    }

    /// Control for the two above: seen outside the same ring first, the arrival is a real crossing
    /// and its DWELL carries the observed entry and the time since it.
    @Test
    func apply_givenOutsideThenInsideOnTheSameRing_expectDwellCarriesObservedEntryAndDuration() async {
        let entry = Date(timeIntervalSince1970: 1000)
        let dwellClock = ManualGeofenceClock(wall: entry.addingTimeInterval(-60))
        let setup = await makeSetup(fix: nil, withDwellCoordinator: true, dwellClock: dwellClock)
        let geofence = polygonGeofence(dwellThresholdSeconds: 60)
        await setup.storage.setCachedGeofences([geofence])

        await setup.resolver.apply(
            .outside, to: geofence, evidence: entry.addingTimeInterval(-60), confirmedByFix: true
        )
        dwellClock.advance(to: entry)
        await setup.resolver.apply(.inside, to: geofence, evidence: entry, confirmedByFix: true)
        dwellClock.advance(to: entry.addingTimeInterval(120))
        await setup.resolver.apply(
            .inside, to: geofence, evidence: entry.addingTimeInterval(120), confirmedByFix: true
        )

        #expect(await setup.emitter.snapshot().map(\.transition) == [.enter, .dwell])
        let visit = await setup.storage.getDwellVisit(geofenceId: geofence.id)
        #expect(visit?.entryObserved == true)
        #expect(visit?.dwellReservation?.enteredAt == entry)
        #expect(visit?.dwellReservation?.durationSeconds == 120)
        let payload = await setup.emitter.dwellContextSnapshot()
        #expect(payload.map(\.enteredAt) == [entry])
        #expect(payload.map(\.durationSeconds) == [120])
    }

    /// An outside belief for the same ring, but proven hours before the arrival: the crossing
    /// happened somewhere in those hours, not at the inside fix. The ENTER is still delivered and
    /// the stay still qualifies a DWELL, but the payload the tracker receives carries no
    /// `enteredAt` or duration — the stale proof must not date the entry to the inside fix.
    @Test
    func apply_givenStaleOutsideThenInsideOnTheSameRing_expectEnterAndDwellWithoutEnteredAtOrDuration() async {
        let entry = Date(timeIntervalSince1970: 100000)
        let dwellClock = ManualGeofenceClock(wall: entry.addingTimeInterval(-3 * 60 * 60))
        let setup = await makeSetup(fix: nil, withDwellCoordinator: true, dwellClock: dwellClock)
        let geofence = polygonGeofence(dwellThresholdSeconds: 60)
        await setup.storage.setCachedGeofences([geofence])

        await setup.resolver.apply(
            .outside, to: geofence, evidence: entry.addingTimeInterval(-3 * 60 * 60), confirmedByFix: true
        )
        dwellClock.advance(to: entry)
        await setup.resolver.apply(.inside, to: geofence, evidence: entry, confirmedByFix: true)
        dwellClock.advance(to: entry.addingTimeInterval(120))
        await setup.resolver.apply(
            .inside, to: geofence, evidence: entry.addingTimeInterval(120), confirmedByFix: true
        )

        #expect(await setup.emitter.snapshot().map(\.transition) == [.enter, .dwell])
        #expect(await setup.emitter.snapshot().first?.occurredAt == entry)
        let visit = await setup.storage.getDwellVisit(geofenceId: geofence.id)
        #expect(visit?.entryObserved == false)
        let payload = await setup.emitter.dwellContextSnapshot()
        #expect(payload.count == 1)
        #expect(payload.first?.enteredAt == nil)
        #expect(payload.first?.durationSeconds == nil)
        #expect(payload.first?.thresholdSeconds == 60)
    }

    /// The stale proof re-established just before the arrival — a later outside fix confirming the
    /// held belief — makes the entry observed again, and its payload is dated from the inside fix.
    @Test
    func apply_givenStaleOutsideReconfirmedBeforeInside_expectDwellCarriesObservedEntryAndDuration() async {
        let entry = Date(timeIntervalSince1970: 100000)
        let dwellClock = ManualGeofenceClock(wall: entry.addingTimeInterval(-3 * 60 * 60))
        let setup = await makeSetup(fix: nil, withDwellCoordinator: true, dwellClock: dwellClock)
        let geofence = polygonGeofence(dwellThresholdSeconds: 60)
        await setup.storage.setCachedGeofences([geofence])

        await setup.resolver.apply(
            .outside, to: geofence, evidence: entry.addingTimeInterval(-3 * 60 * 60), confirmedByFix: true
        )
        dwellClock.advance(to: entry.addingTimeInterval(-15))
        await setup.resolver.apply(
            .outside, to: geofence, evidence: entry.addingTimeInterval(-15), confirmedByFix: true
        )
        dwellClock.advance(to: entry)
        await setup.resolver.apply(.inside, to: geofence, evidence: entry, confirmedByFix: true)
        dwellClock.advance(to: entry.addingTimeInterval(120))
        await setup.resolver.apply(
            .inside, to: geofence, evidence: entry.addingTimeInterval(120), confirmedByFix: true
        )

        #expect(await setup.emitter.snapshot().map(\.transition) == [.enter, .dwell])
        let payload = await setup.emitter.dwellContextSnapshot()
        #expect(payload.map(\.enteredAt) == [entry])
        #expect(payload.map(\.durationSeconds) == [120])
    }

    // MARK: - Transition-type filter

    @Test
    func handleTransition_givenEnterOnlyPolygon_expectExitSuppressed() async {
        let setup = await makeSetup(fix: nil)
        await setup.storage.setCachedGeofences([polygonGeofence(transitionTypes: [.enter])])
        _ = await setup.storage.recordPolygonMembership(.inside, forIdentifier: "1", now: clock.now.addingTimeInterval(-1))

        await setup.resolver.handleTransition(identifier: "1", transition: .exit, occurredAt: clock.now)

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .outside)
    }

    // MARK: - Newly registered polygons

    @Test
    func evaluateNewlyRegistered_givenCachedInsideAndFreshOutside_expectOnlyTheFreshVerdict() async {
        // The forced request is refused unless its answer is strictly newer than the held fix.
        let now = clock.now
        let setup = await makeSetup(fix: fix(latitude: 0.01, longitude: 0.01, at: now))
        // Held, inside, and young enough that the cached path would have accepted it.
        setup.fixResolver.handleResolvedFix(CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            timestamp: now.addingTimeInterval(-Self.ageInsideGate)
        ))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.evaluateNewlyRegistered(geofenceIds: ["1"])

        #expect(await setup.emitter.snapshot().isEmpty, "decided from the cached fix and emitted an enter")
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .outside)
    }

    @Test
    func evaluateNewlyRegistered_givenTheForcedRequestFails_expectTheCachedFixStillDecides() async {
        let setup = await makeSetup(fix: nil) // the forced request fails
        setup.fixResolver.handleResolvedFix(CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            timestamp: clock.now.addingTimeInterval(-Self.ageInsideGate)
        ))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.evaluateNewlyRegistered(geofenceIds: ["1"])

        #expect(await setup.emitter.snapshot().map(\.transition) == [.enter])
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    // MARK: - Belief across an OS eviction

    @Test
    func evaluateAllPolygons_givenEvictionWhileStillInside_expectNoDuplicateEnter() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        await registerPolygons(setup, ids: ["1"])
        // Dated behind the fix so a confirming pass visibly advances the stamp.
        let before = clock.now.addingTimeInterval(-60)
        _ = await setup.storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfBeliefPredates: before, now: clock.now
        )
        await evictCoveringCircle(setup, id: "1")

        await setup.resolver.evaluateAllPolygons(reason: .foreground)

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
        // Proves the pass decided: a confirming evaluation refreshes the stamp.
        let stamp = await setup.storage.getPolygonMembership()["1"]?.lastChangedAt
        #expect(stamp.map { $0 > before } == true)
    }

    @Test
    func evaluateAllPolygons_givenEvictionThenDeviceLeft_expectExitDelivered() async {
        let setup = await makeSetup(fix: fix(latitude: 0.0020, longitude: 0))
        await registerPolygons(setup, ids: ["1"])
        _ = await setup.storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfBeliefPredates: clock.now.addingTimeInterval(-60), now: clock.now
        )
        await evictCoveringCircle(setup, id: "1")

        await setup.resolver.evaluateAllPolygons(reason: .foreground)

        #expect(await setup.emitter.snapshot().map(\.transition) == [.exit])
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .outside)
    }

    /// The `.unmonitored` clear, then the next registration reseeding the circle baseline.
    private func evictCoveringCircle(_ setup: Setup, id: String) async {
        let center = LocationData(latitude: 0, longitude: 0)
        // Seeded first: the clear only removes a record that exists.
        await setup.storage.recordMonitorRegistration(
            identifier: id, transitionTypes: [.enter, .exit], initialState: .enter,
            center: center, radius: 300
        )
        await setup.storage.clearMonitorRegionRecord(identifier: id)
        await setup.storage.recordMonitorRegistration(
            identifier: id, transitionTypes: [.enter, .exit], initialState: .exit,
            center: center, radius: 300, forceReseed: true
        )
    }

    // MARK: - Crossing time

    @Test
    func handleTransition_givenEnterDecidedFromAFix_expectStampedWithTheFixNotTheVerdict() async {
        let takenAt = clock.now.addingTimeInterval(-1)
        let logger = LoggerMock()
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0, at: takenAt), logger: logger)
        await setup.storage.setCachedGeofences([polygonGeofence()])

        // A deliberately different date on the OS event, so a stamp taken from the wrong one shows.
        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: clock.now)

        // Checked first, so a fix that aged out reads as a stalled runner, not a lost emission.
        // Prose, not the tail: the tail needs diagnostics on.
        let tooOld = PolygonUndecidedReason.fixTooOld.prose
        // `contains("")` is always true, which would invert the guard below.
        #expect(!tooOld.isEmpty)
        #expect(
            !logger.debugReceivedInvocations.contains { $0.message.contains(tooOld) },
            "fix aged past movementFixMaxAge before the pass read it — stalled runner, not a stamping regression"
        )
        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1)
        #expect(delivered.first?.occurredAt == takenAt)
    }

    @Test
    func handleTransition_givenCoveringCircleExit_expectStampedWithTheOsEventDate() async {
        let setup = await makeSetup(fix: nil)
        await setup.storage.setCachedGeofences([polygonGeofence()])
        let leftAt = clock.now.addingTimeInterval(-300)
        _ = await setup.storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfBeliefPredates: leftAt.addingTimeInterval(-60), now: clock.now
        )

        await setup.resolver.handleTransition(identifier: "1", transition: .exit, occurredAt: leftAt)

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1)
        #expect(delivered.first?.occurredAt == leftAt)
    }

    @Test
    func handleTransition_givenCircleGeofence_expectStampedWithTheOsEventDate() async {
        let setup = await makeSetup(fix: nil)
        await setup.storage.setCachedGeofences([circleGeofence()])
        let crossedAt = clock.now.addingTimeInterval(-300)

        await setup.resolver.handleTransition(identifier: "2", transition: .enter, occurredAt: crossedAt)

        #expect(await setup.emitter.snapshot().first?.occurredAt == crossedAt)
    }

    // MARK: - Pass phase ordering

    /// Shifted north so a fix 3 m inside the square's north edge is marginal for `1`, decisive for `2`.
    private func deepPolygonGeofence(id: String) -> Geofence {
        Geofence(
            id: id, latitude: 0.0016, longitude: 0, radius: 300, name: "deep",
            transitionTypes: [.enter, .exit], lastUpdated: clock.now,
            vertices: Self.squareVertices.map {
                LocationData(latitude: $0.latitude + 0.0016, longitude: $0.longitude)
            }
        )
    }

    /// Decisive verdicts must be recorded before any corroboration request, or a slow request ages the
    /// fix every later polygon is judged on.
    private func expectDecisiveVerdictBeforeCorroboration(order ids: [String]) async {
        let logger = LoggerMock()
        let setup = await makeSetup(fix: nil, logger: logger)
        marginalPass(setup)
        await setup.storage.recordRegistration(
            center: LocationData(latitude: 0, longitude: 0), businessIds: Set(ids)
        )
        await setup.storage.setCachedGeofences([polygonGeofence(id: "1"), deepPolygonGeofence(id: "2")])
        let decisiveSeenAtRequest = RequestCounter()
        setup.fixResolver.requestFreshFix = { [weak fixResolver = setup.fixResolver] in
            decisiveSeenAtRequest.count = logger.debugReceivedInvocations
                .filter { $0.message.contains("Polygon membership inside for region 2") }.count
            fixResolver?.handleRequestFailure()
        }

        await setup.resolver.evaluateMembership(geofenceIds: ids, reason: .newPolygon)

        #expect(decisiveSeenAtRequest.count == 1)
    }

    @Test
    func evaluateMembership_givenMarginalPolygonFirst_expectDecisiveOneSettledBeforeCorroboration() async {
        await expectDecisiveVerdictBeforeCorroboration(order: ["1", "2"])
    }

    /// Reversed, so the result can't come from catalog order.
    @Test
    func evaluateMembership_givenMarginalPolygonLast_expectDecisiveOneSettledBeforeCorroboration() async {
        await expectDecisiveVerdictBeforeCorroboration(order: ["2", "1"])
    }

    @Test
    func runPass_givenBeliefTurnsInsideAfterClassification_expectNoCorroborationRequest() async {
        let logger = LoggerMock()
        let setup = await makeSetup(fix: nil, logger: logger)
        marginalPass(setup)
        await registerPolygons(setup, ids: ["1"])
        let requested = Flag()
        setup.fixResolver.requestFreshFix = { [weak fixResolver = setup.fixResolver] in
            requested.value = true
            fixResolver?.handleRequestFailure()
        }
        // Stands in for phase one landing this belief after "1" was classified as deferred.
        _ = await setup.storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfBeliefPredates: Date(timeIntervalSince1970: 0), now: clock.now
        )

        await setup.resolver.evaluateMembership(geofenceIds: ["1"], reason: .newPolygon)

        #expect(requested.value == false)
        #expect(logged(logger, "already believed inside, so no second fix was needed"))
    }

    // MARK: - Pass provenance

    @Test
    func evaluateAllPolygons_givenAForegroundPass_expectTheReasonRecorded() async {
        let logger = LoggerMock()
        let setup = await makeSetup(fix: nil, logger: logger)
        await registerPolygons(setup, ids: ["1", "2"])

        await setup.resolver.evaluateAllPolygons(reason: .foreground)

        #expect(logged(logger, "Evaluating 2 polygon(s) (foreground)"))
    }

    @Test
    func evaluateAllPolygons_givenAMovementPass_expectTheReasonRecorded() async {
        let logger = LoggerMock()
        let setup = await makeSetup(fix: nil, logger: logger)
        await registerPolygons(setup, ids: ["1"])

        await setup.resolver.evaluateAllPolygons(reason: .movement, requiresFreshFix: true)

        #expect(logged(logger, "Evaluating 1 polygon(s) (movement)"))
    }

    @Test
    func evaluateAllPolygons_givenNothingRegistered_expectAPassRecordWithZero() async {
        let logger = LoggerMock()
        let setup = await makeSetup(fix: nil, logger: logger)

        await setup.resolver.evaluateAllPolygons(reason: .foreground)

        #expect(logged(logger, "Evaluating 0 polygon(s) (foreground)"))
    }

    // MARK: - A pass running on a fix its caller already holds

    /// One polygon decided by a forced pass (so the resolver's baseline is that fix), then a second
    /// registered for the follow-up pass to decide.
    private func afterAnEntryPass(_ setup: Setup) async {
        await registerPolygons(setup, ids: ["1"])
        await setup.resolver.evaluateAllPolygons(reason: .movement, requiresFreshFix: true)
        await registerPolygons(setup, ids: ["1", "2"])
    }

    /// Control: without a held fix, the follow-up's own request is refused as not newer.
    @Test
    func evaluateAllPolygons_givenAForcedPassRightAfterAnEntry_expectItDecidesNothingOnItsOwn() async {
        let resolved = fix(latitude: 0, longitude: 0)
        let setup = await makeSetup(fix: resolved)
        await afterAnEntryPass(setup)

        await setup.resolver.evaluateAllPolygons(reason: .movement, requiresFreshFix: true)

        #expect(await setup.storage.getPolygonMembership()["2"] == nil)
        // Prose, not the `why=` token: the `ev=` tail is only appended when diagnostics are on.
        #expect(logged(setup.logger, "undecided for region 2: no usable fix"))
    }

    @Test
    func evaluateAllPolygons_givenTheCallersFix_expectItDecidesWithoutRequestingAnother() async {
        let resolved = fix(latitude: 0, longitude: 0)
        let setup = await makeSetup(fix: resolved)
        await afterAnEntryPass(setup)
        let counter = countingRequests(setup)

        await setup.resolver.evaluateAllPolygons(
            reason: .movement, requiresFreshFix: true, heldFix: ResolvedFix(resolved)
        )

        // Read into a local: `counter.count == 0` is rewritten to `.isEmpty` by the lint autofix.
        let requests = counter.count
        #expect(await setup.storage.getPolygonMembership()["2"]?.membership == .inside)
        #expect(requests == 0)
    }

    @Test
    func passFix_givenAReusedHeldFix_expectTheDecisionsAgeNotAFreshReading() async {
        let setup = await makeSetup(fix: nil)
        // ~29.95 s old by the clock, but the decision accepted it at 1 s.
        let held = ResolvedFix(fix(
            latitude: 0, longitude: 0,
            at: clock.now.addingTimeInterval(-GeofenceConstants.movementFixMaxAge + 0.05)
        ))
        let decision = PolygonMembershipResolver.HeldFixDecision(use: .reused, age: 1, newerFix: nil)

        let chosen = await setup.resolver.passFix(heldFix: held, decision: decision, requiringFresh: true)

        #expect(chosen?.age == 1)
    }

    /// Calls `evaluate` with the age passed explicitly, because the drift itself is a race.
    @Test
    func evaluate_givenTheFixAgedPastTheCapAfterThePassSettledIt_expectItStillDecides() async {
        let setup = await makeSetup(fix: nil)
        await registerPolygons(setup, ids: ["1"])
        // Older than the cap by the clock, so a recomputed age refuses it outright.
        let stale = fix(
            latitude: 0, longitude: 0,
            at: clock.now.addingTimeInterval(-GeofenceConstants.movementFixMaxAge - 5)
        )

        _ = await setup.resolver.evaluate(
            geofenceId: "1",
            fix: PolygonMembershipResolver.PassFix(location: stale, age: 0),
            pass: 1
        )

        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    @Test
    func evaluateAllPolygons_givenAHeldFixPastTheAgeCap_expectItRequestsRatherThanReuseIt() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        await afterAnEntryPass(setup)
        let newer = fix(latitude: 0, longitude: 0)
        setup.fixResolver.requestFreshFix = { [weak fixResolver = setup.fixResolver] in
            fixResolver?.handleResolvedFix(newer)
        }

        await setup.resolver.evaluateAllPolygons(
            reason: .movement, requiresFreshFix: true,
            heldFix: ResolvedFix(fix(
                latitude: 0, longitude: 0,
                at: clock.now.addingTimeInterval(-GeofenceConstants.movementFixMaxAge - 1)
            ))
        )

        // Reusing it instead would have left this nil, refused as `fix_too_old`.
        #expect(await setup.storage.getPolygonMembership()["2"]?.membership == .inside)
    }

    @Test
    func evaluateAllPolygons_givenACoarseHeldFix_expectItIsStillJudgedOnAccuracy() async {
        let resolved = fix(latitude: 0, longitude: 0)
        let setup = await makeSetup(fix: resolved)
        await afterAnEntryPass(setup)

        // 500 m of uncertainty around a ~360 m square: nothing about this point is decisive.
        await setup.resolver.evaluateAllPolygons(
            reason: .movement, requiresFreshFix: true,
            heldFix: ResolvedFix(fix(latitude: 0, longitude: 0, accuracy: 500))
        )

        #expect(await setup.storage.getPolygonMembership()["2"] == nil)
    }

    // MARK: - Corroboration independence

    /// A latitude `metres` inside the square's north edge; a 5 m fix there is marginal.
    private static func latitudeInsideNorthEdge(by metres: Double) -> Double {
        0.0016 - metres / 111320
    }

    /// The system cache isn't recorded in `latestFix`, so an echo of the pass fix gets past that guard.
    @Test
    func evaluateMembership_givenCorroborationEchoesThePassFix_expectEnterCommittedUnconfirmed() async {
        let marginal = fix(
            latitude: Self.latitudeInsideNorthEdge(by: 3),
            longitude: 0,
            accuracy: 5,
            at: clock.now.addingTimeInterval(-Self.ageInsideGate)
        )
        let setup = await makeSetup(fix: marginal)
        // The pass answers from here without recording it.
        setup.fixResolver.systemCachedFix = { marginal }
        await registerPolygons(setup, ids: ["1"])

        await setup.resolver.evaluateMembership(geofenceIds: ["1"], reason: .newPolygon)

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1)
        #expect(delivered.first?.transition == .enter)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    @Test
    func corroborationFix_givenTheSameBasisTwice_expectOneRequest() async {
        let setup = await makeSetup(fix: nil)
        let counter = countingRequests(setup)
        let basis = clock.now.addingTimeInterval(-Self.ageInsideGate)

        let cache = PassCorroboration()
        _ = await setup.resolver.corroborationFix(newerThan: basis, cache: cache)
        _ = await setup.resolver.corroborationFix(newerThan: basis, cache: cache)

        #expect(counter.count == 1)
    }

    @Test
    func corroborationFix_givenADifferentBasis_expectAFreshRequest() async {
        let delivered = fix(
            latitude: 0, longitude: 0, at: clock.now.addingTimeInterval(-Self.ageInsideGate)
        )
        let setup = await makeSetup(fix: delivered)
        let counter = RequestCounter()
        setup.fixResolver.requestFreshFix = { [weak fixResolver = setup.fixResolver] in
            counter.count += 1
            fixResolver?.handleResolvedFix(delivered)
        }
        let first = clock.now.addingTimeInterval(-20)

        // Succeeds and is cached.
        let cache = PassCorroboration()
        #expect(await setup.resolver.corroborationFix(newerThan: first, cache: cache).fix != nil)
        _ = await setup.resolver.corroborationFix(newerThan: first.addingTimeInterval(1), cache: cache)

        #expect(counter.count == 2)
    }

    @Test
    func corroborationFix_givenAnAnswerNotNewerThanTheBasis_expectNotIndependent() async {
        let basis = clock.now.addingTimeInterval(-Self.ageInsideGate)
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0, at: basis))

        #expect(await setup.resolver.corroborationFix(newerThan: basis, cache: PassCorroboration()) == .notIndependent)
    }

    private func deliveringSecondFix(_ setup: Setup, _ second: CLLocation) {
        setup.fixResolver.requestFreshFix = { [weak fixResolver = setup.fixResolver] in
            fixResolver?.handleResolvedFix(second)
        }
    }

    /// Marginal inside (edge +3 m, 5 m accuracy), resolved from the system cache.
    private func marginalPass(_ setup: Setup) {
        let passFix = fix(
            latitude: Self.latitudeInsideNorthEdge(by: 3), longitude: 0, accuracy: 5,
            at: clock.now.addingTimeInterval(-Self.ageInsideGate)
        )
        setup.fixResolver.systemCachedFix = { passFix }
    }

    /// Answers each corroboration with a fix far outside, so the arrival stays owed.
    private func countingContradictions(_ setup: Setup) -> RequestCounter {
        let counter = RequestCounter()
        setup.fixResolver.requestFreshFix = { [weak fixResolver = setup.fixResolver] in
            counter.count += 1
            fixResolver?.handleResolvedFix(fix(latitude: 1, longitude: 1, accuracy: 5))
        }
        return counter
    }

    /// Two `runPass` calls on one fix: the overlap a refresh's two fresh passes produce, made
    /// deterministic.
    @Test
    func runPass_givenASecondPassOnTheSameFix_expectItMakesItsOwnAttempt() async {
        let setup = await makeSetup(fix: nil)
        let passFix = fix(
            latitude: Self.latitudeInsideNorthEdge(by: 3), longitude: 0, accuracy: 5,
            at: clock.now.addingTimeInterval(-Self.ageInsideGate)
        )
        let counter = countingContradictions(setup)
        await registerPolygons(setup, ids: ["1"])

        // Distinct pass numbers because these ARE two passes.
        await setup.resolver.runPass(geofenceIds: ["1"], fix: .init(location: passFix, age: clock.now.timeIntervalSince(passFix.timestamp)), pass: 1)
        await setup.resolver.runPass(geofenceIds: ["1"], fix: .init(location: passFix, age: clock.now.timeIntervalSince(passFix.timestamp)), pass: 2)

        #expect(counter.count == 2)
    }

    /// The only test where a usable second fix agrees; without it that branch could be inverted
    /// unnoticed.
    @Test
    func evaluateMembership_givenSecondFixReadsInside_expectEnterDelivered() async {
        let setup = await makeSetup(fix: nil)
        marginalPass(setup)
        // Default timestamp, so it strictly postdates the pass fix by `ageInsideGate`.
        deliveringSecondFix(
            setup,
            fix(latitude: Self.latitudeInsideNorthEdge(by: 10), longitude: 0, accuracy: 5)
        )
        await registerPolygons(setup, ids: ["1"])

        await setup.resolver.evaluateMembership(geofenceIds: ["1"], reason: .newPolygon)

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1)
        #expect(delivered.first?.transition == .enter)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    @Test
    func evaluateMembership_givenSecondFixReadsOutside_expectCorroborationDisagreed() async {
        let logger = LoggerMock()
        let setup = await makeSetup(fix: nil, logger: logger)
        marginalPass(setup)
        deliveringSecondFix(setup, fix(latitude: 1, longitude: 1, accuracy: 5))
        await registerPolygons(setup, ids: ["1"])

        await setup.resolver.evaluateMembership(geofenceIds: ["1"], reason: .newPolygon)

        // The mock sees prose; the token is pinned in `GeofenceLogTailTests`.
        #expect(logged(logger, "the second fix read outside"))
        #expect(await setup.emitter.snapshot().isEmpty)
    }

    @Test
    func evaluateMembership_givenSecondFixCoarserThanTheVenue_expectEnterCommittedUnconfirmed() async {
        let setup = await makeSetup(fix: nil)
        marginalPass(setup)
        // Inside the ring, but the accuracy circle is wider than the venue is deep (~178 m).
        deliveringSecondFix(setup, fix(latitude: 0, longitude: 0, accuracy: 200))
        await registerPolygons(setup, ids: ["1"])

        await setup.resolver.evaluateMembership(geofenceIds: ["1"], reason: .newPolygon)

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1)
        #expect(delivered.first?.transition == .enter)
    }

    @Test
    func corroborationFix_givenNoFix_expectUnavailable() async {
        let setup = await makeSetup(fix: nil)

        #expect(await setup.resolver.corroborationFix(newerThan: clock.now, cache: PassCorroboration()) == .unavailable)
    }
}
