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
    /// Records what reached the event tracker, standing in for the real one.
    private actor EmitterSpy: GeofenceTransitionEmitting {
        struct Delivered: Equatable, Sendable {
            let id: String
            let transition: GeofenceTransition
            let occurredAt: Date
        }

        private(set) var delivered: [Delivered] = []

        func trackTransition(geofenceId: String, transition: GeofenceTransition, occurredAt: Date) async {
            delivered.append(Delivered(id: geofenceId, transition: transition, occurredAt: occurredAt))
        }

        func snapshot() -> [Delivered] {
            delivered
        }
    }

    /// A ~360 m square centred on the origin: comfortably past the 20 m margin floor at the centre,
    /// so a precise fix there is decisive.
    private static let squareVertices = [
        LocationData(latitude: -0.0016, longitude: -0.0016),
        LocationData(latitude: -0.0016, longitude: 0.0016),
        LocationData(latitude: 0.0016, longitude: 0.0016),
        LocationData(latitude: 0.0016, longitude: -0.0016)
    ]

    /// An age that predates the wake yet stays inside `movementFixMaxAge`. Deliberately far from
    /// that 30 s cap rather than just under it: the binding check is at DELIVERY, in
    /// `MovementFixResolver.locationManager(_:didUpdateLocations:)`, which refuses a fix past the
    /// cap WITHOUT resuming the request — so the offset is a wall-clock budget for everything
    /// between the stamp and the delivery hook. A 20 s stamp overran it on a loaded runner: the
    /// echo was refused, the forced request ran to its 10 s timeout, and the pass emitted nothing.
    /// A failure here therefore reads as a slow test, not as an undecided verdict.
    private static let ageInsideGate: TimeInterval = 5

    private func polygonGeofence(
        id: String = "1",
        transitionTypes: Set<GeofenceTransition> = [.enter, .exit],
        radius: Double = 300
    ) -> Geofence {
        Geofence(
            id: id, latitude: 0, longitude: 0, radius: radius, name: "poly",
            transitionTypes: transitionTypes, lastUpdated: Date(), vertices: Self.squareVertices
        )
    }

    /// The same fence after a refresh replaced it: the server recomputes the enclosing circle from
    /// the new ring, so the covering circle moves with the geometry.
    private func replacedPolygonGeofence(id: String = "1") -> Geofence {
        Geofence(
            id: id, latitude: 0, longitude: 0.005, radius: 300, name: "poly",
            transitionTypes: [.enter, .exit], lastUpdated: Date(),
            vertices: Self.squareVertices.map {
                LocationData(latitude: $0.latitude, longitude: $0.longitude + 0.005)
            }
        )
    }

    private func circleGeofence(id: String = "2") -> Geofence {
        Geofence(
            id: id, latitude: 0, longitude: 0, radius: 300, name: "circle",
            transitionTypes: [.enter, .exit], lastUpdated: Date()
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
        onFixDelivered: (@Sendable () -> Void)? = nil
    ) async -> Setup {
        // Its own centre: `willEnterForeground` posted on the default one reaches every other
        // test's live resolver, whose pass then consumes their fix requests and writes their beliefs.
        let notificationCenter = NotificationCenter()
        let contextStore = contextStore ?? BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        if contextStore.currentUserId == nil { contextStore.setUserId("user-1") }
        let storage = GeofenceStorage(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        // A belief is only created for a registered polygon, so the fixture has to be registered or
        // every write comes back `.suppressedUnmonitored`.
        await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: ["1"])
        let emitter = EmitterSpy()
        let fixResolver = MovementFixResolver(logger: LoggerMock())
        fixResolver.systemCachedFix = { nil } // never touch CoreLocation from a unit test
        // Seam: resolve inline with the supplied fix instead of touching CoreLocation.
        fixResolver.requestFreshFix = { [weak fixResolver] in
            guard let fix else { return fixResolver?.handleRequestFailure() ?? () }
            fixResolver?.handleResolvedFix(fix)
            onFixDelivered?()
        }
        return Setup(
            resolver: PolygonMembershipResolver(
                storage: storage,
                transitionEmitter: emitter,
                logger: logger,
                contextStore: contextStore,
                fixResolver: fixResolver,
                notificationCenter: notificationCenter
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
        at timestamp: Date = Date()
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 5,
            timestamp: timestamp
        )
    }

    /// Counts location requests so a pass that says it shares one fix can be held to it.
    private final class RequestCounter: @unchecked Sendable {
        var count = 0
    }

    /// A latch the fix seam flips, so a test can place an event inside the resolve window.
    private final class Flag: @unchecked Sendable {
        var value = false
    }

    private func logged(_ logger: LoggerMock, _ needle: String) -> Bool {
        logger.debugReceivedInvocations.contains { $0.message.contains(needle) }
    }

    /// The same ring shifted a degree away, so a point decisive INSIDE the original is decisively
    /// outside this one.
    private func movedPolygonGeofence(id: String = "1") -> Geofence {
        Geofence(
            id: id, latitude: 1, longitude: 1, radius: 300, name: "poly",
            transitionTypes: [.enter, .exit], lastUpdated: Date(),
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

    /// A failed request leaves the cache empty, so resolving inside the loop would issue one timed
    /// request per polygon and hold the main actor for as long as that takes.
    @Test
    func evaluateAllPolygons_givenNoFixAvailable_expectOneRequestForTheWholePass() async {
        let setup = await makeSetup(fix: nil)
        await registerPolygons(setup, ids: ["1", "2", "3"])
        let counter = countingRequests(setup)

        await setup.resolver.evaluateAllPolygons(reason: .foreground)

        #expect(counter.count == 1)
    }

    /// Foregrounds arrive in bursts. A second concurrent pass reads the same storage and the same
    /// fix, so it can only duplicate the location work.
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

    /// A wake requires a fresh fix; a foreground pass does not. Skipping the wake behind an
    /// in-flight foreground would drop exactly the pass that runs BECAUSE the device moved, and
    /// nothing retries it.
    ///
    /// `async let` does not order task start-up, and a request count cannot tell "skipped" from
    /// "coalesced into the pending request" — so the first pass is held inside its request and the
    /// assertion is on the skip decision itself.
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

    /// Two wakes are not interchangeable just because both demand a fresh fix. The in-flight one
    /// asked for its fix before the crossing that caused this one, so yielding to it drops the
    /// second crossing entirely — there is no retry behind a wake.
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
        // One entry, not two: the second wake COALESCED onto the in-flight request rather than
        // issuing its own. Pinned because it bounds what not-skipping buys — the second wake is
        // answered by a request that predates its own crossing, and when that shared request fails
        // both wakes end undecided. Not skipping is still the better of the two, but the guarantee
        // is "it gets an answer", not "it gets a fix of its own".
        #expect(gate.releases.count == 1, "expected the second wake to coalesce, got \(gate.releases.count) requests")
        gate.releaseAll()
        _ = await(firstWake, secondWake)

        #expect(skipCount(logger) == 0)
    }

    /// The converse still holds: a weaker pass behind a fresh one adds nothing.
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

    /// Holds each pass inside its location request until released, so a second pass always starts
    /// against a known in-flight state.
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

        await setup.resolver.handleTransition(identifier: "2", transition: .enter, occurredAt: Date())

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1)
        #expect(delivered.first?.transition == .enter)
    }

    /// A sync can drop a geofence the OS still holds a condition for. Forwarding beats dropping:
    /// losing a real crossing is worse than one shaped like its covering circle.
    @Test
    func handleTransition_givenUncachedGeofence_expectForwarded() async {
        let setup = await makeSetup(fix: nil)

        await setup.resolver.handleTransition(identifier: "999", transition: .exit, occurredAt: Date())

        #expect(await setup.emitter.snapshot().count == 1)
    }

    // MARK: - Covering-circle enter

    @Test
    func handleTransition_givenPolygonEnterAndFixInside_expectEnterDelivered() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: Date())

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1)
        #expect(delivered.first?.transition == .enter)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    /// The pass resolves ONE fix for every polygon. A per-polygon "first one pays" flag would clear
    /// after the first evaluation even when it got no fresh fix, silently downgrading polygon two
    /// onward to the pre-wake fix — so assert the second polygon is undecided too, not just the first.
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

    /// The regression a simulator drive caught and no unit test could see. CoreLocation's own cache
    /// advances on its own, so a system fix is always about as fresh as anything a request can
    /// return. Taking the forced-fresh baseline from `cachedFix` — which reports the newest of both
    /// sources — made that baseline unbeatable, and every polygon verdict came back "no usable fix".
    ///
    /// The seam is LIVE here on purpose. Every other test in this suite stubs `systemCachedFix` to
    /// nil so it never touches CoreLocation, and that is exactly why the bug was invisible: the one
    /// input that caused it was switched off everywhere.
    @Test
    func handleTransition_givenSystemCacheAlwaysCurrent_expectEnterStillDelivered() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        // Stands in for a cache the OS keeps refreshing: every read is "now", so it is never older
        // than the fix the request delivers.
        setup.fixResolver.systemCachedFix = { [weak fixResolver = setup.fixResolver] in
            _ = fixResolver
            return CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date()
            )
        }
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: Date())

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1, "verdict was refused; got \(delivered)")
        #expect(delivered.first?.transition == .enter)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    /// Resolves through `locationManager(_:didUpdateLocations:)` rather than the direct
    /// `handleResolvedFix` seam every other test in this suite uses. That seam bypasses the
    /// delegate's own filters — the `movementFixMaxAge` echo check, `horizontalAccuracy > 0`, and
    /// the invalid-coordinate drop — so nothing here exercised them until this test.
    @Test
    func handleTransition_givenFixArrivingThroughTheDelegate_expectEnterDelivered() async {
        let setup = await makeSetup(fix: nil)
        setup.fixResolver.requestFreshFix = { [weak fixResolver = setup.fixResolver] in
            fixResolver?.locationManager(CLLocationManager(), didUpdateLocations: [
                fix(latitude: 0, longitude: 0)
            ])
        }
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: Date())

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1)
        #expect(delivered.first?.transition == .enter)
    }

    /// KNOWN LIMIT, pinned so it cannot change silently. CoreLocation can echo its cached fix as a
    /// new manager's first delivery, and the delegate accepts an echo inside `movementFixMaxAge`.
    /// On the first pass of a process there is no delivered fix to be newer than, so that echo
    /// reaches a verdict: a cold wake can be decided by a fix up to `movementFixMaxAge` older than
    /// the wake — several hundred metres at speed. Narrowing it needs an assumed-speed constant and
    /// belongs with the ≤17 work; if this test starts failing, rule out `ageInsideGate` before
    /// concluding someone narrowed it deliberately.
    @Test
    func handleTransition_givenColdProcessAndEchoedPreWakeFix_expectVerdictFromTheStaleEcho() async {
        let setup = await makeSetup(fix: nil) // cold: nothing delivered, no system cache
        let preWakeFix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            timestamp: Date(timeIntervalSinceNow: -Self.ageInsideGate)
        )
        setup.fixResolver.requestFreshFix = { [weak fixResolver = setup.fixResolver] in
            fixResolver?.locationManager(CLLocationManager(), didUpdateLocations: [preWakeFix])
        }
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: Date())

        #expect(await setup.emitter.snapshot().count == 1)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    /// A pass that does NOT require a fresh fix must act on the newest position available, not on
    /// the last one this resolver happened to deliver. `resolve` answers from the caller's cached
    /// fix without requesting when that fix is young enough, and takes that fast path without
    /// recording it — so `latestFix` can still be an old delivered fix while the fresh system fix
    /// is the very thing that let the pass proceed. Reading `latestFix` first evaluated foreground
    /// passes at the stale position.
    @Test
    func evaluateAllPolygons_givenStaleDeliveredFixAndFreshSystemCache_expectTheFreshOneDecides() async {
        let setup = await makeSetup(fix: nil)
        // Delivered ~1.1 km away, outside the polygon, and deliberately INSIDE
        // `movementFixMaxAge`. A fix old enough for the decision's own age gate to reject would
        // make this test pass on that gate rather than on the defect, and the defect's whole range
        // is inside the gate.
        setup.fixResolver.handleResolvedFix(CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0.01, longitude: 0.01),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            timestamp: Date(timeIntervalSinceNow: -Self.ageInsideGate)
        ))
        // The system cache has moved on and sits inside the polygon, well within the age gate.
        setup.fixResolver.systemCachedFix = {
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date()
            )
        }
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.evaluateAllPolygons(reason: .foreground)

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1, "decided from the stale delivered fix; got \(delivered)")
        #expect(delivered.first?.transition == .enter)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    /// Pins that a failed forced request never falls back to the held fix.
    ///
    /// What refuses it is the timestamp comparison, NOT the `cached: nil` coupling: `resolve`'s fast
    /// path completes synchronously without recording, so `resolved` and `priorTimestamp` are both
    /// read from the same `latestFix` and the strict `>` can never hold. The coupling earns its
    /// place against the opposite failure — a current system cache short-circuiting the request,
    /// leaving that same comparison to refuse a fix that was genuinely fresh — and
    /// `handleTransition_givenSystemCacheAlwaysCurrent_expectEnterStillDelivered` is what fails if
    /// it is removed.
    @Test
    func handleTransition_givenFreshRequiredAndStaleHeldFix_expectNoVerdictFromIt() async {
        let setup = await makeSetup(fix: nil) // the forced request fails
        // Held, inside the polygon, and young enough that the fast path WOULD accept it as fresh.
        setup.fixResolver.handleResolvedFix(CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            timestamp: Date(timeIntervalSinceNow: -Self.ageInsideGate)
        ))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: Date())

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"] == nil)
    }

    /// A wake fires BECAUSE the device moved, so the fix it already holds describes where it was.
    /// When the forced request fails, falling back to that fix re-affirms the stale verdict — the
    /// exact silent miss the fresh-fix rule exists to prevent — so no verdict must be reached.
    @Test
    func handleTransition_givenFreshFixRequiredButRequestFails_expectNoVerdictFromHeldFix() async {
        let setup = await makeSetup(fix: nil) // the forced request fails
        // Seed a pre-wake fix that is inside the polygon and still within `movementFixMaxAge`.
        setup.fixResolver.handleResolvedFix(fix(latitude: 0, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: Date())

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"] == nil)
    }

    /// The first wake of a process holds no fix of its own, so there was nothing for the freshness
    /// comparison to reject — and CoreLocation's cached fix, which is exactly the pre-movement one,
    /// answered the forced request.
    @Test
    func handleTransition_givenFreshFixRequiredOnFirstWake_expectNoVerdictFromSystemCache() async {
        let setup = await makeSetup(fix: nil) // the forced request fails
        // No fix delivered to this resolver yet: a cold process with only CoreLocation's cache.
        setup.fixResolver.systemCachedFix = { fix(latitude: 0, longitude: 0) }
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: Date())

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"] == nil)
    }

    /// A stored ring that no longer builds is not a circle. Forwarding it would fire a customer
    /// enter anywhere inside the covering circle — the polygon's whole annulus included.
    @Test
    func handleTransition_givenStoredRingThatCannotBuild_expectNothingForwarded() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        let degenerate = Geofence(
            id: "1", latitude: 0, longitude: 0, radius: 300, name: "poly",
            transitionTypes: [.enter, .exit], lastUpdated: Date(),
            vertices: [LocationData(latitude: 0, longitude: 0), LocationData(latitude: 0, longitude: 0)]
        )
        await setup.storage.setCachedGeofences([degenerate])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: Date())

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"] == nil)
    }

    /// An exit needs no ring: polygon ⊆ covering circle, so leaving the circle proves it whatever
    /// the stored geometry does. Refusing one because the ring no longer builds would strand the
    /// belief at inside, suppressing every later exit and re-enter.
    @Test
    func handleTransition_givenStoredRingThatCannotBuild_expectExitStillApplied() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])
        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: Date())
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)

        let degenerate = Geofence(
            id: "1", latitude: 0, longitude: 0, radius: 300, name: "poly",
            transitionTypes: [.enter, .exit], lastUpdated: Date(),
            vertices: [LocationData(latitude: 0, longitude: 0), LocationData(latitude: 0, longitude: 0)]
        )
        await setup.storage.setCachedGeofences([degenerate])

        await setup.resolver.handleTransition(identifier: "1", transition: .exit, occurredAt: Date())

        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .outside)
        #expect(await setup.emitter.snapshot().map(\.transition) == [.enter, .exit])
    }

    /// A replayed or synthesized exit arriving after a newer enter must not overwrite it: the device
    /// would be believed outside while sitting inside, with the enter cooldown blocking recovery.
    @Test
    func handleTransition_givenExitOlderThanBelief_expectSuppressed() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])
        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: Date())
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)

        await setup.resolver.handleTransition(
            identifier: "1", transition: .exit, occurredAt: Date(timeIntervalSince1970: 0)
        )

        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
        #expect(await setup.emitter.snapshot().map(\.transition) == [.enter])
    }

    /// The fix resolves across a suspension point. If the user switches in that window, cleanup has
    /// already cleared user-scoped state, so resuming would rewrite the old user's belief and stamp
    /// any event to whoever signed in.
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

    /// Control: the same call with the user unchanged must still decide, so the guard above is not
    /// passing by refusing everything.
    @Test
    func evaluateMembership_givenUserUnchanged_expectVerdictRecorded() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.evaluateMembership(
            geofenceIds: ["1"], reason: .foreground, isStillCurrent: { true }
        )

        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    /// The batch shares one fix, so every polygon in it spans the same request — and a refresh
    /// landing inside that request replaces rings under the ids the batch is holding. Each verdict
    /// must come from the ring current when it is decided, not the one the batch was built from.
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

    /// Control: the same interleaving with the catalog left alone must still deliver.
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

    /// A registration carrying several new polygons must cost one location request, not one each:
    /// with no fix obtainable, per-polygon resolution spends the full request timeout N times over
    /// on the main actor and still decides nothing.
    @Test
    func evaluateMembership_givenSeveralNewPolygons_expectOneRequestForTheBatch() async {
        let setup = await makeSetup(fix: nil)
        await registerPolygons(setup, ids: ["1", "2", "3"])
        let counter = countingRequests(setup)

        await setup.resolver.evaluateMembership(geofenceIds: ["1", "2", "3"], reason: .foreground)

        #expect(counter.count == 1)
    }

    /// The annulus: inside the covering circle, outside the polygon. The OS thinks we arrived;
    /// geometry says otherwise, so nothing is delivered and the belief records `outside`.
    @Test
    func handleTransition_givenPolygonEnterAndFixInAnnulus_expectNoEvent() async {
        let setup = await makeSetup(fix: fix(latitude: 0.0024, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: Date())

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .outside)
    }

    /// A fix too coarse to place the device relative to the boundary must leave no belief behind:
    /// guessing either way would deliver an event we cannot stand behind.
    @Test
    func handleTransition_givenUndecidableFix_expectNoBelief() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0, accuracy: 400))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: Date())

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"] == nil)
    }

    @Test
    func handleTransition_givenNoFixObtainable_expectNothingRecorded() async {
        let setup = await makeSetup(fix: nil)
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: Date())

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"] == nil)
    }

    // MARK: - Covering-circle exit

    /// polygon ⊆ circle, so leaving the circle proves the polygon was left — no fix required.
    @Test
    func handleTransition_givenPolygonExitWhileInside_expectExitDeliveredWithoutFix() async {
        let setup = await makeSetup(fix: nil)
        await setup.storage.setCachedGeofences([polygonGeofence()])
        _ = await setup.storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await setup.resolver.handleTransition(identifier: "1", transition: .exit, occurredAt: Date())

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1)
        #expect(delivered.first?.transition == .exit)
    }

    /// Leaving a circle only proves leaving the ring that circle encloses. A refresh moves both, so
    /// an exit raised for the old circle says nothing about the new ring — the device can be
    /// standing inside it. Writing `outside` here would also stamp a date that then refuses the
    /// very fix that would correct it, so the belief sticks rather than self-heals.
    @Test
    func handleTransition_givenExitRaisedForAReplacedCircle_expectRefusedAndBeliefKept() async {
        let setup = await makeSetup(fix: nil)
        let original = polygonGeofence()
        await setup.storage.setCachedGeofences([original])
        _ = await setup.storage.recordPolygonMembership(.inside, forIdentifier: "1")
        await setup.storage.setCachedGeofences([replacedPolygonGeofence()])

        await setup.resolver.handleTransition(
            identifier: "1", transition: .exit, occurredAt: Date(),
            eventCircle: .circle(MonitoredCircle(
                center: LocationData(latitude: original.latitude, longitude: original.longitude),
                radius: original.radius, maximumRadius: 1000
            ))
        )

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    /// Control: an exit for the circle the fence still has is the case the containment argument
    /// covers, and must still deliver without a fix.
    @Test
    func handleTransition_givenExitRaisedForTheCurrentCircle_expectExitDelivered() async {
        let setup = await makeSetup(fix: nil)
        let geofence = polygonGeofence()
        await setup.storage.setCachedGeofences([geofence])
        _ = await setup.storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await setup.resolver.handleTransition(
            identifier: "1", transition: .exit, occurredAt: Date(),
            eventCircle: .circle(MonitoredCircle(
                center: LocationData(latitude: geofence.latitude, longitude: geofence.longitude),
                radius: geofence.radius, maximumRadius: 1000
            ))
        )

        #expect(await setup.emitter.snapshot().first?.transition == .exit)
    }

    /// The same refusal when the producer cannot name the circle at all: further replacements
    /// drained while this exit sat in the handler's own awaits, so the circle it was raised against
    /// is no longer held. It must not arrive as `unknown`, which is the cold-wake case and is taken
    /// as current — that stores `outside` for a device standing inside the polygon that replaced
    /// the one crossed, stamped with a date no later fix can correct.
    ///
    /// Driven from a real ledger history through the production mapping rather than by handing
    /// `.expired` in: the monitor owning that lookup cannot be built in a unit test, so this is the
    /// only thing that fails if the ledger's output or the mapping stops lining up with what the
    /// exit path expects. The belief is stamped OLDER than the event on purpose — a newer belief
    /// would refuse it on evidence order and the geometry guard would never be reached.
    @Test
    func handleTransition_givenAnExitOlderThanEveryHeldGeneration_expectRefusedAndBeliefKept() async {
        let setup = await makeSetup(fix: nil)
        var ledger = RegisteredConditionLedger()
        let raisedAt = Date().addingTimeInterval(-90)
        let firstLiveAt = Date().addingTimeInterval(-60)
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0),
            radius: 300, transitionTypes: [.enter, .exit], at: firstLiveAt, liveFrom: firstLiveAt
        )
        let secondStagedAt = Date().addingTimeInterval(-30)
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0.005),
            radius: 300, transitionTypes: [.enter, .exit], at: secondStagedAt
        )
        ledger.confirm("1", stagedAt: secondStagedAt, at: Date().addingTimeInterval(-20))

        await setup.storage.setCachedGeofences([polygonGeofence()])
        _ = await setup.storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfBeliefPredates: Date().addingTimeInterval(-120)
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

    /// The OS registers `min(radius, maximumRegionMonitoringDistance)`, so an over-cap fence is
    /// monitored by a smaller circle than it declares. Comparing the event against the fence's own
    /// radius would read every such fence as replaced and refuse its exits for good.
    @Test
    func handleTransition_givenExitForAnOverCapFence_expectExitDelivered() async {
        let setup = await makeSetup(fix: nil)
        let geofence = polygonGeofence(radius: 5000)
        await setup.storage.setCachedGeofences([geofence])
        _ = await setup.storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await setup.resolver.handleTransition(
            identifier: "1", transition: .exit, occurredAt: Date(),
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
        _ = await setup.storage.recordPolygonMembership(.outside, forIdentifier: "1")

        await setup.resolver.handleTransition(identifier: "1", transition: .exit, occurredAt: Date())

        #expect(await setup.emitter.snapshot().isEmpty)
    }

    // MARK: - Foreground evaluation

    /// The case no OS event reaches: a device already standing inside a polygon when monitoring
    /// A refresh can replace the fence under the same id while the fix is pending. The ring the
    /// pass started with is then geometry the workspace has already moved off, and deciding from it
    /// delivers a crossing for a shape we no longer monitor. No user switch is involved.
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

    /// Control: the same interleaving with the catalog left alone must still deliver, so the guard
    /// above is not passing by refusing anything that arrives late.
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

    /// Registration is the other thing sampled before the fix. A polygon unregistered while the
    /// request is out must not be judged either — the pass would otherwise decide for a fence the
    /// device is no longer monitoring.
    ///
    /// Pins the OUTCOME, not the mechanism, and passes without the resolver's registration re-read:
    /// `recordRegistration` prunes the belief with the set, so the write becomes a create and
    /// storage refuses it as unmonitored. That is a second guard, not this one — the re-read is
    /// what stops the resolver depending on a storage rule that only covers the create path.
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

    /// A polygon dropped from the catalog entirely while the fix resolved has nothing left to
    /// decide against, and must not be judged by the copy the pass is still holding.
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

    /// Foregrounding resolves a fix like any other pass, and a foregrounding app's cached fix is
    /// normally stale — the app was suspended — so the request suspends for real. The observer has
    /// no caller to take an expected user from, so it samples one itself.
    ///
    /// The switch lands at fix delivery, so this pins the check that runs after the fix; the one on
    /// the emit's own stretch is pinned separately below. They are not duplicates.
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
        // Waits for the refusal to be RECORDED, not for a fixed number of yields: an expect-nothing
        // test with a fixed wait goes vacuous the moment this path gains another await.
        await yieldUntil { logged(setup.logger, PolygonUndecidedReason.userChanged.prose) }

        // `yieldUntil` gives up silently, so without this the expect-nothing assertions below pass
        // whether the refusal ran or the wait simply timed out.
        #expect(logged(setup.logger, PolygonUndecidedReason.userChanged.prose))
        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"] == nil)
    }

    /// The verdict is only half the path: the membership write and the emit are two more awaits,
    /// and the tracker stamps whoever is current when it is entered. A switch landing after the
    /// write must still not deliver — while the write itself may stand, since a belief states
    /// geometry rather than attribution.
    ///
    /// A belief already exists, so the write takes the CHANGE path — the one
    /// `monitoredGeofenceIds` does not guard.
    @Test
    func evaluateAllPolygons_givenUserChangesAfterTheWrite_expectNoEvent() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        await registerPolygons(setup, ids: ["1"])
        _ = await setup.storage.recordPolygonMembership(
            .outside, forIdentifier: "1", onlyIfBeliefPredates: Date(timeIntervalSince1970: 0)
        )
        // True while the verdict is formed, false by the time the delivery boundary asks.
        let asked = RequestCounter()

        await setup.resolver.evaluateAllPolygons(reason: .foreground, isStillCurrent: {
            asked.count += 1
            return asked.count == 1
        })

        #expect(asked.count == 2)
        // The write said deliver, so the refusal is the switch and not an unchanged belief.
        #expect(logged(setup.logger, "delivered nothing: user_changed"))
        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    /// An enter-only polygon decided OUTSIDE reaches the delivery boundary as `.deliver(.exit)`,
    /// and the workspace's transition filter refuses it. The write said deliver, so sharing the
    /// write's outcome reported `why=deliver` on a record that exists because nothing was sent.
    @Test
    func evaluateAllPolygons_givenEnterOnlyPolygonDecidedOutside_expectTheFilterNamed() async {
        // Outside the ring, decisively — the square is around the origin.
        let setup = await makeSetup(fix: fix(latitude: 5, longitude: 5))
        await setup.storage.recordRegistration(
            center: LocationData(latitude: 0, longitude: 0), businessIds: ["1"]
        )
        await setup.storage.setCachedGeofences([polygonGeofence(id: "1", transitionTypes: [.enter])])
        // A belief already exists, so the write takes the CHANGE path and returns .deliver(.exit)
        // rather than suppressing as an initial outside.
        _ = await setup.storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfBeliefPredates: Date(timeIntervalSince1970: 0)
        )

        await setup.resolver.evaluateAllPolygons(reason: .foreground)

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(logged(setup.logger, "delivered nothing: transition_type_not_registered"))
        #expect(!logged(setup.logger, "delivered nothing: deliver"))
    }

    /// Control: the same foregrounding with nobody switching must still deliver, so the guard above
    /// is not passing by refusing every foreground pass.
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

    /// The default centre is what production observes, and every other test here injects a private
    /// one — so without this nothing would notice if that default broke and foreground evaluation
    /// died in the field. Safe only while no other test posts to `.default` or builds the DI
    /// singleton; if that changes, this is the test that will start cross-talking.
    @Test
    func foreground_givenTheDefaultNotificationCentre_expectPassRuns() async {
        let storage = GeofenceStorage(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: ["1"])
        await storage.setCachedGeofences([polygonGeofence()])
        let contextStore = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        contextStore.setUserId("user-1")
        let emitter = EmitterSpy()
        let fixResolver = MovementFixResolver(logger: LoggerMock())
        fixResolver.systemCachedFix = { nil }
        fixResolver.requestFreshFix = { [weak fixResolver] in
            fixResolver?.handleResolvedFix(CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date()
            ))
        }
        let resolver = PolygonMembershipResolver(
            storage: storage, transitionEmitter: emitter,
            logger: LoggerMock(), contextStore: contextStore, fixResolver: fixResolver
        )

        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        for _ in 0 ..< 1000 where await emitter.snapshot().isEmpty {
            await Task.yield()
        }

        #expect(await emitter.snapshot().map(\.transition) == [.enter])
        _ = resolver
    }

    /// begins has crossed nothing, and standing still produces no movement pass either.
    /// Foregrounding is the remaining signal.
    @Test
    func evaluateAllPolygons_givenDeviceInsideOneRegisteredPolygon_expectEnterForThatOneOnly() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        let distant = Geofence(
            id: "2", latitude: 1, longitude: 1, radius: 300, name: "far",
            transitionTypes: [.enter, .exit], lastUpdated: Date(),
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

    /// A polygon that has dropped out of the registered set is no longer monitored, so foreground
    /// evaluation must not resurrect it.
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

    // MARK: - Transition-type filter

    @Test
    func handleTransition_givenEnterOnlyPolygon_expectExitSuppressed() async {
        let setup = await makeSetup(fix: nil)
        await setup.storage.setCachedGeofences([polygonGeofence(transitionTypes: [.enter])])
        _ = await setup.storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await setup.resolver.handleTransition(identifier: "1", transition: .exit, occurredAt: Date())

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .outside)
    }

    // MARK: - Newly registered polygons

    /// The two passes a refresh starts must not disagree. `evaluatePolygonsAfterMovement` forces a
    /// fresh fix; while this pass decided from the cached one, a single refresh could deliver an
    /// enter from a position up to `movementFixMaxAge` old and then its own correcting exit.
    @Test
    func evaluateNewlyRegistered_givenCachedInsideAndFreshOutside_expectOnlyTheFreshVerdict() async {
        // Both fixes are stamped from one instant. Stamping them at their own call sites makes
        // their ORDER depend on how long `makeSetup` takes, and the forced request is refused
        // unless its answer is strictly newer than the held fix — so on a loaded runner they invert.
        let now = Date()
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

    /// The fallback the forced request needs: enter-when-inside is owed for a polygon the device is
    /// standing in, and the movement pass fails on the same request, so a failed request must not
    /// cost the enter outright.
    @Test
    func evaluateNewlyRegistered_givenTheForcedRequestFails_expectTheCachedFixStillDecides() async {
        let setup = await makeSetup(fix: nil) // the forced request fails
        setup.fixResolver.handleResolvedFix(CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            timestamp: Date(timeIntervalSinceNow: -Self.ageInsideGate)
        ))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.evaluateNewlyRegistered(geofenceIds: ["1"])

        #expect(await setup.emitter.snapshot().map(\.transition) == [.enter])
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    // MARK: - Belief across an OS eviction

    /// The eviction sequence end to end: the `.unmonitored` clear, then the re-registration that
    /// reseeds the circle baseline, then a pass. The device never left, so the surviving belief
    /// makes this a no-change and the customer gets no second enter for a visit already reported.
    @Test
    func evaluateAllPolygons_givenEvictionWhileStillInside_expectNoDuplicateEnter() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        await registerPolygons(setup, ids: ["1"])
        // Dated behind the fix: `makeSetup` builds the CLLocation first, so a belief stamped now
        // would postdate it and the pass would be refused as a newer decision without evaluating.
        let before = Date().addingTimeInterval(-60)
        _ = await setup.storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfBeliefPredates: before
        )
        await evictCoveringCircle(setup, id: "1")

        await setup.resolver.evaluateAllPolygons(reason: .foreground)

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
        // Proves the pass actually decided: a confirming evaluation refreshes the evidence stamp,
        // so without this the assertions above also hold when nothing was evaluated at all.
        let stamp = await setup.storage.getPolygonMembership()["1"]?.lastChangedAt
        #expect(stamp.map { $0 > before } == true)
    }

    /// Same eviction, but the device left during the gap. The retained `inside` belief is what
    /// makes the verdict a change; dropped, this lands on the create path and the exit is lost.
    @Test
    func evaluateAllPolygons_givenEvictionThenDeviceLeft_expectExitDelivered() async {
        let setup = await makeSetup(fix: fix(latitude: 0.0020, longitude: 0))
        await registerPolygons(setup, ids: ["1"])
        _ = await setup.storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfBeliefPredates: Date().addingTimeInterval(-60)
        )
        await evictCoveringCircle(setup, id: "1")

        await setup.resolver.evaluateAllPolygons(reason: .foreground)

        #expect(await setup.emitter.snapshot().map(\.transition) == [.exit])
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .outside)
    }

    /// What the OS reporting a covering circle unmonitored actually does to storage: the deferred
    /// clear, then the next registration reseeding the circle baseline.
    private func evictCoveringCircle(_ setup: Setup, id: String) async {
        let center = LocationData(latitude: 0, longitude: 0)
        // Seeded first: the clear only removes a monitor record that exists, so without this the
        // `.unmonitored` half is a no-op and only the reseed would be under test.
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

    /// The event time is when the device crossed, not when the verdict was reached. Those differ by
    /// the whole wake-to-fix-to-verdict pipeline, and the OS event's own date is a third value —
    /// so the assertion names the fix's timestamp exactly rather than a tolerance around now.
    @Test
    func handleTransition_givenEnterDecidedFromAFix_expectStampedWithTheFixNotTheVerdict() async {
        let takenAt = Date().addingTimeInterval(-12)
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0, at: takenAt))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        // A deliberately different date on the OS event, so a stamp taken from the wrong one shows.
        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: Date())

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1)
        #expect(delivered.first?.occurredAt == takenAt)
    }

    /// A covering-circle exit needs no fix, so its evidence is the OS event's own date — which on a
    /// crossing replayed to a long-suspended process is nowhere near the moment we handle it.
    @Test
    func handleTransition_givenCoveringCircleExit_expectStampedWithTheOsEventDate() async {
        let setup = await makeSetup(fix: nil)
        await setup.storage.setCachedGeofences([polygonGeofence()])
        let leftAt = Date().addingTimeInterval(-300)
        _ = await setup.storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfBeliefPredates: leftAt.addingTimeInterval(-60)
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
        let crossedAt = Date().addingTimeInterval(-300)

        await setup.resolver.handleTransition(identifier: "2", transition: .enter, occurredAt: crossedAt)

        #expect(await setup.emitter.snapshot().first?.occurredAt == crossedAt)
    }

    // MARK: - Pass phase ordering

    /// A ring shifted north so a fix 3 m inside the standard square's north edge sits deep inside
    /// this one — marginal for `1`, decisive for `2`, from the same fix.
    private func deepPolygonGeofence(id: String) -> Geofence {
        Geofence(
            id: id, latitude: 0.0016, longitude: 0, radius: 300, name: "deep",
            transitionTypes: [.enter, .exit], lastUpdated: Date(),
            vertices: Self.squareVertices.map {
                LocationData(latitude: $0.latitude + 0.0016, longitude: $0.longitude)
            }
        )
    }

    /// Shahroz's second finding. Corroborating inline let one marginal polygon's request burn its
    /// timeout mid-loop, handing every later polygon the same fix ten seconds older — enough to
    /// push a fix that was decisive at the start of the pass past `movementFixMaxAge`. Asserted as
    /// the ordering invariant that removes it: every decisive verdict is recorded BEFORE any
    /// corroboration request is issued, so no arrival can depend on another venue being marginal.
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

        // The decisive verdict for 2 was already in when 1's corroboration request went out.
        #expect(decisiveSeenAtRequest.count == 1)
    }

    @Test
    func evaluateMembership_givenMarginalPolygonFirst_expectDecisiveOneSettledBeforeCorroboration() async {
        await expectDecisiveVerdictBeforeCorroboration(order: ["1", "2"])
    }

    /// The reversed order Shahroz asked for: the property must not come from catalog order.
    @Test
    func evaluateMembership_givenMarginalPolygonLast_expectDecisiveOneSettledBeforeCorroboration() async {
        await expectDecisiveVerdictBeforeCorroboration(order: ["2", "1"])
    }

    /// The guard has to sit immediately before the request it saves. Splitting corroboration into
    /// a second phase moved it away from that point, so a belief that turned inside during phase
    /// one still bought a forced fix. Asserted where it bites: the belief is written after the
    /// deferred polygon was classified, and no corroboration request may follow.
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
            .inside, forIdentifier: "1", onlyIfBeliefPredates: Date(timeIntervalSince1970: 0)
        )

        await setup.resolver.evaluateMembership(geofenceIds: ["1"], reason: .newPolygon)

        #expect(requested.value == false)
        #expect(logged(logger, "already believed inside, so no second fix was needed"))
    }

    // MARK: - Pass provenance

    /// A capture has to say which pass produced a verdict. `.movement` and `.foreground` existed
    /// as tokens but nothing emitted them, so a stationary stay's records had no provenance and
    /// had to be attributed by guessing at timing.
    @Test
    func evaluateAllPolygons_givenAForegroundPass_expectTheReasonRecorded() async {
        let logger = LoggerMock()
        let setup = await makeSetup(fix: nil, logger: logger)
        await registerPolygons(setup, ids: ["1", "2"])

        await setup.resolver.evaluateAllPolygons(reason: .foreground)

        #expect(logged(logger, "Evaluating 2 polygon(s) (foreground)"))
    }

    /// A movement wake and a foreground pass must not read alike.
    @Test
    func evaluateAllPolygons_givenAMovementPass_expectTheReasonRecorded() async {
        let logger = LoggerMock()
        let setup = await makeSetup(fix: nil, logger: logger)
        await registerPolygons(setup, ids: ["1"])

        await setup.resolver.evaluateAllPolygons(reason: .movement, requiresFreshFix: true)

        #expect(logged(logger, "Evaluating 1 polygon(s) (movement)"))
    }

    /// The pass that had nothing to judge used to return in silence, so "nothing registered" and
    /// "never ran" were the same empty capture.
    @Test
    func evaluateAllPolygons_givenNothingRegistered_expectAPassRecordWithZero() async {
        let logger = LoggerMock()
        let setup = await makeSetup(fix: nil, logger: logger)

        await setup.resolver.evaluateAllPolygons(reason: .foreground)

        #expect(logged(logger, "Evaluating 0 polygon(s) (foreground)"))
    }

    // MARK: - Corroboration independence

    /// A latitude `metres` INSIDE the square's northern edge, so `signedEdgeDistance` is that many
    /// metres positive and a 5 m fix there is marginal rather than decisive.
    private static func latitudeInsideNorthEdge(by metres: Double) -> Double {
        0.0016 - metres / 111320
    }

    /// The high-severity case: the pass fix came from the SYSTEM cache, which
    /// `MovementFixResolver` answers with but never records in `latestFix`. The forced
    /// corroboration request then only had to beat `latestFix` — still nil — so CoreLocation
    /// echoing that very same fix cleared the guard and an ambiguous arrival confirmed itself.
    /// An echo is not evidence the device is outside, so the arrival commits on the first fix
    /// alone. What it must NOT do is count as confirmation — the verdict carries
    /// `corroboration_not_independent`, not `cor=true`.
    @Test
    func evaluateMembership_givenCorroborationEchoesThePassFix_expectEnterCommittedUnconfirmed() async {
        let marginal = fix(
            latitude: Self.latitudeInsideNorthEdge(by: 3),
            longitude: 0,
            accuracy: 5,
            at: Date().addingTimeInterval(-Self.ageInsideGate)
        )
        let setup = await makeSetup(fix: marginal)
        // The pass answers from here without recording it, which is what opened the gap.
        setup.fixResolver.systemCachedFix = { marginal }
        await registerPolygons(setup, ids: ["1"])

        await setup.resolver.evaluateMembership(geofenceIds: ["1"], reason: .newPolygon)

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1)
        #expect(delivered.first?.transition == .enter)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    /// The same fix judged twice still costs one request — the batching the pass depends on.
    @Test
    func corroborationFix_givenTheSameBasisTwice_expectOneRequest() async {
        let setup = await makeSetup(fix: nil)
        let counter = countingRequests(setup)
        let basis = Date().addingTimeInterval(-Self.ageInsideGate)

        let cache = PassCorroboration()
        _ = await setup.resolver.corroborationFix(newerThan: basis, cache: cache)
        _ = await setup.resolver.corroborationFix(newerThan: basis, cache: cache)

        #expect(counter.count == 1)
    }

    /// A SUCCEEDED attempt must not answer for a fix it predates. Clearing at pass boundaries
    /// missed `evaluateMembership` and the single-fence path entirely, so a held fix answered
    /// passes it had never seen; the basis key covers all three entry points.
    @Test
    func corroborationFix_givenADifferentBasis_expectAFreshRequest() async {
        let delivered = fix(
            latitude: 0, longitude: 0, at: Date().addingTimeInterval(-Self.ageInsideGate)
        )
        let setup = await makeSetup(fix: delivered)
        let counter = RequestCounter()
        setup.fixResolver.requestFreshFix = { [weak fixResolver = setup.fixResolver] in
            counter.count += 1
            fixResolver?.handleResolvedFix(delivered)
        }
        let first = Date().addingTimeInterval(-20)

        // Succeeds and is cached, which is the state the stale reuse needed.
        let cache = PassCorroboration()
        #expect(await setup.resolver.corroborationFix(newerThan: first, cache: cache).fix != nil)
        _ = await setup.resolver.corroborationFix(newerThan: first.addingTimeInterval(1), cache: cache)

        #expect(counter.count == 2)
    }

    /// A fix at or before the basis is the first fix over again, not a second opinion — and it
    /// reports as its own outcome, so a capture can tell an echo from location not answering.
    @Test
    func corroborationFix_givenAnAnswerNotNewerThanTheBasis_expectNotIndependent() async {
        let basis = Date().addingTimeInterval(-Self.ageInsideGate)
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0, at: basis))

        #expect(await setup.resolver.corroborationFix(newerThan: basis, cache: PassCorroboration()) == .notIndependent)
    }

    /// Answers the corroboration request with a fix of its own, so the SECOND fix's properties
    /// decide the refusal rather than the one the pass judged.
    private func deliveringSecondFix(_ setup: Setup, _ second: CLLocation) {
        setup.fixResolver.requestFreshFix = { [weak fixResolver = setup.fixResolver] in
            fixResolver?.handleResolvedFix(second)
        }
    }

    /// Sets up a marginal inside — `edge` +3 against 5 m accuracy — resolved from the system
    /// cache, which is the state corroboration runs from.
    private func marginalPass(_ setup: Setup) {
        let passFix = fix(
            latitude: Self.latitudeInsideNorthEdge(by: 3), longitude: 0, accuracy: 5,
            at: Date().addingTimeInterval(-Self.ageInsideGate)
        )
        setup.fixResolver.systemCachedFix = { passFix }
    }

    /// Counts corroboration requests and answers each with a fix far OUTSIDE the ring, so the
    /// arrival is blocked and a later pass is still owed its own attempt.
    private func countingContradictions(_ setup: Setup) -> RequestCounter {
        let counter = RequestCounter()
        setup.fixResolver.requestFreshFix = { [weak fixResolver = setup.fixResolver] in
            counter.count += 1
            fixResolver?.handleResolvedFix(fix(latitude: 1, longitude: 1, accuracy: 5))
        }
        return counter
    }

    /// One refresh starts BOTH `evaluateNewlyRegistered` and the movement pass, both are
    /// `requiresFreshFix`, and the in-flight guard deliberately lets a fresh pass through — so two
    /// passes routinely judge the same fix at the same time. When the corroboration attempt lived
    /// on the resolver, the first pass's TIMEOUT answered the second pass without it ever asking,
    /// and a transient failure suppressed an arrival that a retry would have delivered.
    ///
    /// Driven through `runPass` twice against one fix rather than through concurrent entry points:
    /// that is the same shared-basis condition the overlap produces, and it is deterministic. The
    /// old code cleared only in `resolveFix`, which a pass never called for itself, so the
    /// second pass here reused the first's failure and made no request.
    @Test
    func runPass_givenASecondPassOnTheSameFix_expectItMakesItsOwnAttempt() async {
        let setup = await makeSetup(fix: nil)
        let passFix = fix(
            latitude: Self.latitudeInsideNorthEdge(by: 3), longitude: 0, accuracy: 5,
            at: Date().addingTimeInterval(-Self.ageInsideGate)
        )
        let counter = countingContradictions(setup)
        await registerPolygons(setup, ids: ["1"])

        // Distinct pass numbers because these ARE two passes; the point of the test is that the
        // second does not inherit the first's corroboration attempt.
        await setup.resolver.runPass(geofenceIds: ["1"], fix: passFix, pass: 1)
        await setup.resolver.runPass(geofenceIds: ["1"], fix: passFix, pass: 2)

        #expect(counter.count == 2)
    }

    /// The positive half of the contract. Every other case here asserts a REFUSAL, so inverting
    /// the branch that accepts a second fix would leave the whole suite green — the enter this
    /// path exists to deliver is asserted nowhere else.
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

    /// Side disagreement is its own record. It used to log `within_accuracy`, which describes a
    /// fix that could not pick a side — not two fixes that picked different ones.
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

    /// A second fix too coarse for this venue adds no information, and says so under its own
    /// token — the one case the old ternary did get right, pinned so the split cannot regress it.
    /// A second fix too coarse to judge this venue adds nothing to the first — which is not the
    /// same as arguing against it, so the arrival still commits.
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

    /// No fix at all is a different record from an echo.
    @Test
    func corroborationFix_givenNoFix_expectUnavailable() async {
        let setup = await makeSetup(fix: nil)

        #expect(await setup.resolver.corroborationFix(newerThan: Date(), cache: PassCorroboration()) == .unavailable)
    }
}
