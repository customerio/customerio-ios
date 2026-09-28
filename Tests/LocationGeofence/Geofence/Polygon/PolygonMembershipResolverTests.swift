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
    /// One frozen clock for the SDK and every timestamp the tests build, so a stalled runner cannot
    /// age a fix past `movementFixMaxAge`. Fresh per test: Swift Testing builds a new suite
    /// instance for each one.
    private let clock = DateUtilStub()

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

    /// A ~360 m square centred on the origin, so a precise fix at the centre is decisive.
    private static let squareVertices = [
        LocationData(latitude: -0.0016, longitude: -0.0016),
        LocationData(latitude: -0.0016, longitude: 0.0016),
        LocationData(latitude: 0.0016, longitude: 0.0016),
        LocationData(latitude: 0.0016, longitude: -0.0016)
    ]

    /// An age that predates the wake yet stays well inside `movementFixMaxAge`.
    private static let ageInsideGate: TimeInterval = 5

    private func polygonGeofence(
        id: String = "1",
        transitionTypes: Set<GeofenceTransition> = [.enter, .exit],
        radius: Double = 300
    ) -> Geofence {
        Geofence(
            id: id, latitude: 0, longitude: 0, radius: radius, name: "poly",
            transitionTypes: transitionTypes, lastUpdated: clock.now, vertices: Self.squareVertices
        )
    }

    /// The same fence after a refresh replaced it: the server recomputes the enclosing circle from
    /// the new ring, so the covering circle moves with the geometry.
    private func replacedPolygonGeofence(id: String = "1") -> Geofence {
        Geofence(
            id: id, latitude: 0, longitude: 0.005, radius: 300, name: "poly",
            transitionTypes: [.enter, .exit], lastUpdated: clock.now,
            vertices: Self.squareVertices.map {
                LocationData(latitude: $0.latitude, longitude: $0.longitude + 0.005)
            }
        )
    }

    private func circleGeofence(id: String = "2") -> Geofence {
        Geofence(
            id: id, latitude: 0, longitude: 0, radius: 300, name: "circle",
            transitionTypes: [.enter, .exit], lastUpdated: clock.now
        )
    }

    // MARK: - Held-fix selection

    /// The pass that handed this fix over may have spent a corroboration request and been answered
    /// with a NEWER fix that read outside, refusing the enter. Reusing the held fix would re-propose
    /// that arrival, and its own corroboration would be refused as an echo of the newer fix,
    /// committing the enter UNCONFIRMED on older evidence.
    @Test
    func heldFixUse_givenResolverDeliveredANewerFix_expectTheNewerFixUsed() async {
        let setup = await makeSetup(fix: nil)
        let held = ResolvedFix(fix(latitude: 0, longitude: 0, at: clock.now.addingTimeInterval(-5)))
        // The corroboration answer that contradicted it.
        let newer = fix(latitude: 1, longitude: 1, at: clock.now)
        setup.fixResolver.handleResolvedFix(newer)

        let decision = setup.resolver.heldFixUse(held)

        #expect(decision.use == .newer)
        #expect(decision.newerFix?.timestamp == newer.timestamp)
    }

    /// Substituting must spend no request: a forced request here is refused as an echo, losing
    /// every polygon in the pass to `no_usable_fix`.
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

    /// The age travels with the fix that was chosen, not with the one the caller handed over.
    @Test
    func heldFixUse_givenANewerFixIsHeld_expectTheNewerFixAge() async {
        let setup = await makeSetup(fix: nil)
        let held = ResolvedFix(fix(latitude: 0, longitude: 0, at: clock.now.addingTimeInterval(-20)))
        setup.fixResolver.handleResolvedFix(fix(latitude: 1, longitude: 1, at: clock.now))

        let decision = setup.resolver.heldFixUse(held)

        #expect(decision.age < 5)
    }

    /// A newer fix that is itself past the cap leaves nothing usable held — the caller's is older
    /// still — so the pass must request rather than judge on either.
    ///
    /// The `.tooOld` verdict alone would pass either way — with the substitution removed the held
    /// fix is past the cap too — so the age bound below is what makes this discriminate.
    @Test
    func heldFixUse_givenTheNewerFixIsAlsoPastTheCap_expectTooOld() async {
        let setup = await makeSetup(fix: nil)
        let cap = GeofenceConstants.movementFixMaxAge
        let held = ResolvedFix(fix(latitude: 0, longitude: 0, at: clock.now.addingTimeInterval(-(cap + 20))))
        setup.fixResolver.handleResolvedFix(fix(latitude: 1, longitude: 1, at: clock.now.addingTimeInterval(-(cap + 5))))

        let decision = setup.resolver.heldFixUse(held)

        #expect(decision.use == .tooOld)
        #expect(decision.newerFix == nil)
        // The age comes from whichever fix was looked at: ~cap+5 on the newer path, the held
        // fix's ~cap+20 without the substitution.
        #expect(decision.age < GeofenceConstants.movementFixMaxAge + 10)
    }

    /// With nothing newer delivered the held fix is reused, so the caller is not made to re-ask
    /// and hit the echo refusal.
    @Test
    func heldFixUse_givenNothingNewerDelivered_expectReused() async {
        let setup = await makeSetup(fix: nil)
        let delivered = fix(latitude: 0, longitude: 0, at: clock.now.addingTimeInterval(-5))
        setup.fixResolver.handleResolvedFix(delivered)

        let decision = setup.resolver.heldFixUse(ResolvedFix(delivered))

        #expect(decision.use == .reused)
    }

    /// Age still wins over supersession: past the cap the pass must request rather than reuse,
    /// whatever the resolver has delivered since.
    @Test
    func heldFixUse_givenHeldFixPastTheAgeCap_expectTooOld() async {
        let setup = await makeSetup(fix: nil)
        let stale = clock.now.addingTimeInterval(-(GeofenceConstants.movementFixMaxAge + 5))

        let decision = setup.resolver.heldFixUse(ResolvedFix(fix(latitude: 0, longitude: 0, at: stale)))

        #expect(decision.use == .tooOld)
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
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            dateUtil: clock
        )
        // A belief is only created for a registered polygon, so the fixture has to be registered or
        // every write comes back `.suppressedUnmonitored`.
        await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: ["1"])
        let emitter = EmitterSpy()
        let fixResolver = MovementFixResolver(logger: LoggerMock(), dateUtil: clock)
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
                dateUtil: clock,
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
        // One request, not two: the second wake coalesces onto the in-flight one. Pinned because
        // it bounds what not skipping buys: the second wake gets an answer, not a fix of its own.
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

        await setup.resolver.handleTransition(identifier: "2", transition: .enter, occurredAt: clock.now)

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1)
        #expect(delivered.first?.transition == .enter)
    }

    /// A sync can drop a geofence the OS still holds a condition for. Forwarding beats dropping:
    /// losing a real crossing is worse than one shaped like its covering circle.
    @Test
    func handleTransition_givenUncachedGeofence_expectForwarded() async {
        let setup = await makeSetup(fix: nil)

        await setup.resolver.handleTransition(identifier: "999", transition: .exit, occurredAt: clock.now)

        #expect(await setup.emitter.snapshot().count == 1)
    }

    // MARK: - Covering-circle enter

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

    /// CoreLocation's own cache advances on its own, so a system fix is about as fresh as anything
    /// a request can return. A forced-fresh baseline taken from `cachedFix`, which reports the
    /// newest of both sources, would be unbeatable and every verdict would be "no usable fix".
    ///
    /// The seam is LIVE here on purpose: every other test stubs `systemCachedFix` to nil.
    @Test
    func handleTransition_givenSystemCacheAlwaysCurrent_expectEnterStillDelivered() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        // Stands in for a cache the OS keeps refreshing: every read is "now", so it is never older
        // than the fix the request delivers.
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

    /// Resolves through `locationManager(_:didUpdateLocations:)` rather than the `handleResolvedFix`
    /// seam, which bypasses the delegate path's filters: the `movementFixMaxAge` echo check,
    /// `horizontalAccuracy > 0`, and the invalid-coordinate drop.
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

    /// KNOWN LIMIT, pinned so it cannot change silently. CoreLocation can echo its cached fix as a
    /// new manager's first delivery, and the delegate accepts an echo inside `movementFixMaxAge`.
    /// On the first pass of a process there is no delivered fix to be newer than, so a cold wake
    /// can be decided by a fix up to `movementFixMaxAge` older than the wake, several hundred
    /// metres at speed. Narrowing it needs an assumed-speed constant.
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

    /// A pass that does NOT require a fresh fix must act on the newest position available, not on
    /// the last one this resolver delivered. `resolve`'s fast path answers from the caller's cached
    /// fix without recording it, so `latestFix` can be an old delivered fix while the fresh system
    /// fix is what let the pass proceed.
    @Test
    func evaluateAllPolygons_givenStaleDeliveredFixAndFreshSystemCache_expectTheFreshOneDecides() async {
        let setup = await makeSetup(fix: nil)
        // Delivered ~1.5 km away, outside the polygon, and deliberately INSIDE `movementFixMaxAge`:
        // a fix the decision's own age gate rejects would make this pass on that gate instead.
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

    /// Pins that a failed forced request never falls back to the held fix.
    ///
    /// Passes with or without the `cached: nil` coupling: without it, `resolve`'s fast path answers
    /// without recording, so `resolved` and `priorTimestamp` are the same `latestFix` and the strict
    /// `>` refuses it. The coupling guards the opposite failure, a current system cache
    /// short-circuiting the request, and
    /// `handleTransition_givenSystemCacheAlwaysCurrent_expectEnterStillDelivered` fails without it.
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

    /// A wake fires BECAUSE the device moved, so the fix it already holds describes where it was.
    /// When the forced request fails, falling back to that fix re-affirms the stale verdict — the
    /// exact silent miss the fresh-fix rule exists to prevent — so no verdict must be reached.
    @Test
    func handleTransition_givenFreshFixRequiredButRequestFails_expectNoVerdictFromHeldFix() async {
        let setup = await makeSetup(fix: nil) // the forced request fails
        // Seed a pre-wake fix that is inside the polygon and still within `movementFixMaxAge`.
        setup.fixResolver.handleResolvedFix(fix(latitude: 0, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: clock.now)

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"] == nil)
    }

    /// The first wake of a process has delivered no fix, so the freshness comparison has nothing to
    /// reject. CoreLocation's cached fix, the pre-movement one, must still not answer the forced
    /// request.
    @Test
    func handleTransition_givenFreshFixRequiredOnFirstWake_expectNoVerdictFromSystemCache() async {
        let setup = await makeSetup(fix: nil) // the forced request fails
        // No fix delivered to this resolver yet: a cold process with only CoreLocation's cache.
        setup.fixResolver.systemCachedFix = { fix(latitude: 0, longitude: 0) }
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: clock.now)

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
            transitionTypes: [.enter, .exit], lastUpdated: clock.now,
            vertices: [LocationData(latitude: 0, longitude: 0), LocationData(latitude: 0, longitude: 0)]
        )
        await setup.storage.setCachedGeofences([degenerate])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: clock.now)

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

    /// A replayed or synthesized exit arriving after a newer enter must not overwrite it: the device
    /// would be believed outside while sitting inside, with the enter cooldown blocking recovery.
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

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: clock.now)

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .outside)
    }

    /// A fix too coarse to place the device relative to the boundary must leave no belief behind:
    /// guessing either way would deliver an event we cannot stand behind.
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

    /// polygon ⊆ circle, so leaving the circle proves the polygon was left — no fix required.
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

    /// Leaving a circle only proves leaving the ring that circle encloses. A refresh moves both, so
    /// an exit raised for the old circle says nothing about the new ring — the device can be
    /// standing inside it. Writing `outside` here would also stamp a date that then refuses the
    /// very fix that would correct it, so the belief sticks rather than self-heals.
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

    /// Control: an exit for the circle the fence still has is the case the containment argument
    /// covers, and must still deliver without a fix.
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

    /// The same refusal when the producer cannot name the circle at all: the exit predates every
    /// generation the ledger still holds. It must not arrive as `unknown`, which is the cold-wake
    /// case and is taken as current: that stores `outside` for a device inside the replacement
    /// polygon, stamped with a date no later fix can correct.
    ///
    /// Driven from a real ledger history through the production mapping rather than by handing
    /// `.expired` in. The belief is stamped OLDER than the event on purpose, or evidence order would
    /// refuse it before the geometry guard is reached.
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

    /// The OS registers `min(radius, maximumRegionMonitoringDistance)`, so an over-cap fence is
    /// monitored by a smaller circle than it declares. Comparing the event against the fence's own
    /// radius would read every such fence as replaced and refuse its exits for good.
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

    /// A polygon unregistered while the request is out must not be judged either.
    ///
    /// Pins the OUTCOME only, and passes without the resolver's registration re-read: storage also
    /// refuses the create as unmonitored. That guard covers only the create path, which is why the
    /// resolver re-reads registration too.
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
            .outside, forIdentifier: "1", onlyIfBeliefPredates: Date(timeIntervalSince1970: 0), now: clock.now
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
    /// and the transition filter refuses it. The log must name the filter, not the write's
    /// `deliver` outcome.
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
            .inside, forIdentifier: "1", onlyIfBeliefPredates: Date(timeIntervalSince1970: 0), now: clock.now
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
    /// one, so without this nothing would notice if that default broke and foreground evaluation
    /// stopped in production. Safe only while no other test posts to `.default` or builds the DI
    /// singleton; if that changes, this is the test that will start cross-talking.
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

    /// The case no OS event reaches: a device already standing inside a polygon when monitoring
    /// begins has crossed nothing, and standing still produces no movement pass either.
    /// Foregrounding is the remaining signal.
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
        _ = await setup.storage.recordPolygonMembership(.inside, forIdentifier: "1", now: clock.now.addingTimeInterval(-1))

        await setup.resolver.handleTransition(identifier: "1", transition: .exit, occurredAt: clock.now)

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .outside)
    }

    // MARK: - Newly registered polygons

    /// The two passes a refresh starts must not disagree. `evaluatePolygonsAfterMovement` forces a
    /// fresh fix, so deciding here from the cached one could deliver an enter from a position up to
    /// `movementFixMaxAge` old and then its own correcting exit.
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

    /// The fallback the forced request needs: enter-when-inside is owed for a polygon the device is
    /// standing in, and the movement pass fails on the same request, so a failed request must not
    /// cost the enter outright.
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

    /// The eviction sequence end to end: the `.unmonitored` clear, then the re-registration that
    /// reseeds the circle baseline, then a pass. The device never left, so the surviving belief
    /// makes this a no-change and the customer gets no second enter for a visit already reported.
    @Test
    func evaluateAllPolygons_givenEvictionWhileStillInside_expectNoDuplicateEnter() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        await registerPolygons(setup, ids: ["1"])
        // Dated behind the fix so the confirming pass visibly advances the stamp: a belief stamped
        // at the fix's own instant would not move.
        let before = clock.now.addingTimeInterval(-60)
        _ = await setup.storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfBeliefPredates: before, now: clock.now
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
            .inside, forIdentifier: "1", onlyIfBeliefPredates: clock.now.addingTimeInterval(-60), now: clock.now
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
    /// the whole wake-to-fix-to-verdict pipeline, and the OS event's own date is a third value,
    /// so the assertion names the fix's timestamp exactly rather than a tolerance around now.
    @Test
    func handleTransition_givenEnterDecidedFromAFix_expectStampedWithTheFixNotTheVerdict() async {
        let takenAt = clock.now.addingTimeInterval(-1)
        let logger = LoggerMock()
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0, at: takenAt), logger: logger)
        await setup.storage.setCachedGeofences([polygonGeofence()])

        // A deliberately different date on the OS event, so a stamp taken from the wrong one shows.
        await setup.resolver.handleTransition(identifier: "1", transition: .enter, occurredAt: clock.now)

        // Before the count, so a fix aged out reads as that and not as a lost emission. Prose, not
        // the tail: the tail needs diagnostics on. Taken from the enum so a reworded sentence
        // cannot silently stop this matching.
        let tooOld = PolygonUndecidedReason.fixTooOld.prose
        // `contains("")` is always true, which would invert the guard below into asserting the
        // line WAS logged.
        #expect(!tooOld.isEmpty)
        #expect(
            !logger.debugReceivedInvocations.contains { $0.message.contains(tooOld) },
            "fix aged past movementFixMaxAge before the pass read it — stalled runner, not a stamping regression"
        )
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

    /// A ring shifted north so a fix 3 m inside the standard square's north edge sits deep inside
    /// this one — marginal for `1`, decisive for `2`, from the same fix.
    private func deepPolygonGeofence(id: String) -> Geofence {
        Geofence(
            id: id, latitude: 0.0016, longitude: 0, radius: 300, name: "deep",
            transitionTypes: [.enter, .exit], lastUpdated: clock.now,
            vertices: Self.squareVertices.map {
                LocationData(latitude: $0.latitude + 0.0016, longitude: $0.longitude)
            }
        )
    }

    /// Every decisive verdict is recorded BEFORE any corroboration request is issued. Corroborating
    /// inline lets one marginal polygon's request burn its timeout mid-loop, handing every later
    /// polygon the same fix up to ten seconds older and possibly past `movementFixMaxAge`, so an
    /// arrival would depend on another venue being marginal.
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

    /// Reversed, so the property cannot come from catalog order.
    @Test
    func evaluateMembership_givenMarginalPolygonLast_expectDecisiveOneSettledBeforeCorroboration() async {
        await expectDecisiveVerdictBeforeCorroboration(order: ["2", "1"])
    }

    /// The already-inside guard must be read immediately before the request it saves, because
    /// phase one can land that belief after the deferred polygon was classified.
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

    /// A capture has to say which pass produced a verdict.
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

    /// A pass with nothing to judge still logs, so "nothing registered" and "never ran" differ in a
    /// capture.
    @Test
    func evaluateAllPolygons_givenNothingRegistered_expectAPassRecordWithZero() async {
        let logger = LoggerMock()
        let setup = await makeSetup(fix: nil, logger: logger)

        await setup.resolver.evaluateAllPolygons(reason: .foreground)

        #expect(logged(logger, "Evaluating 0 polygon(s) (foreground)"))
    }

    // MARK: - A pass running on a fix its caller already holds

    /// Sets up the state a circle-entry re-arm leaves behind: one polygon already decided by a
    /// forced pass, so this resolver's baseline now stands at that fix, and a second polygon
    /// registered afterwards that the follow-up pass is supposed to decide.
    private func afterAnEntryPass(_ setup: Setup) async {
        await registerPolygons(setup, ids: ["1"])
        await setup.resolver.evaluateAllPolygons(reason: .movement, requiresFreshFix: true)
        await registerPolygons(setup, ids: ["1", "2"])
    }

    /// The defect the held fix exists for, asserted as a control so the fix below cannot pass
    /// vacuously. `resolveFix(requiringFresh:)` demands a fix strictly newer than the last one
    /// delivered, and the entry pass has just made that the current one — so the follow-up's own
    /// request is refused and decides nothing at all.
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

    /// The same sequence with the entry's fix handed through: the pass judges against it and the
    /// second polygon gets a verdict.
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

    /// The age `heldFixUse` accepted the fix at must travel with it. Re-reading the clock would put
    /// a fix accepted at 29.95 s past `movementFixMaxAge`, recording `fix_too_old` for every
    /// polygon while `.tooOld`, the branch that requests a replacement, was never taken.
    @Test
    func passFix_givenAReusedHeldFix_expectTheDecisionsAgeNotAFreshReading() async {
        let setup = await makeSetup(fix: nil)
        // Deliberately far apart so a re-measurement is unmistakable: the fix reads ~29.95 s old
        // by the clock, but the decision accepted it at 1 s.
        let held = ResolvedFix(fix(
            latitude: 0, longitude: 0,
            at: clock.now.addingTimeInterval(-GeofenceConstants.movementFixMaxAge + 0.05)
        ))
        let decision = PolygonMembershipResolver.HeldFixDecision(use: .reused, age: 1, newerFix: nil)

        let chosen = await setup.resolver.passFix(heldFix: held, decision: decision, requiringFresh: true)

        #expect(chosen?.age == 1)
    }

    /// The pass settles its fix's age once. Re-reading the clock per polygon lets a fix taken just
    /// inside `movementFixMaxAge` cross it mid-pass, and every later polygon records `fix_too_old`.
    /// Driven through `evaluate` with the age passed explicitly, because the drift itself is a race.
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

    /// A movement deferred at the gate replays with the fix it was recorded with, aged by however
    /// long the holder ran. Past `movementFixMaxAge` the decision layer refuses it as
    /// `fix_too_old` and the pass decides nothing — the same loss the held fix exists to prevent,
    /// reached from the other side. So the resolver must drop it and request instead.
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

    /// A held fix is judged on its own accuracy like any other, not waved through because a caller
    /// supplied it.
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

    /// A latitude `metres` INSIDE the square's northern edge, so `signedEdgeDistance` is that many
    /// metres positive and a 5 m fix there is marginal rather than decisive.
    private static func latitudeInsideNorthEdge(by metres: Double) -> Double {
        0.0016 - metres / 111320
    }

    /// The pass fix comes from the SYSTEM cache, which `MovementFixResolver` answers with but never
    /// records in `latestFix`, so a CoreLocation echo of that same fix clears a guard measured
    /// against `latestFix`. An echo is not evidence the device is outside, so the arrival commits,
    /// but as `corroboration_not_independent`, never as `cor=true`.
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

    /// The same fix judged twice still costs one request — the batching the pass depends on.
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

    /// A SUCCEEDED attempt must not answer for a different fix: the cache is keyed on the basis.
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

    /// A fix at or before the basis is the first fix over again, not a second opinion — and it
    /// reports as its own outcome, so a capture can tell an echo from location not answering.
    @Test
    func corroborationFix_givenAnAnswerNotNewerThanTheBasis_expectNotIndependent() async {
        let basis = clock.now.addingTimeInterval(-Self.ageInsideGate)
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
            at: clock.now.addingTimeInterval(-Self.ageInsideGate)
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

    /// One refresh starts BOTH `evaluateNewlyRegistered` and the movement pass, both
    /// `requiresFreshFix`, and the in-flight guard lets a fresh pass through, so two passes
    /// routinely judge the same fix at once. Each must make its own corroboration attempt, or one
    /// pass's transient timeout suppresses the other's arrival.
    ///
    /// Driven through `runPass` twice against one fix: the same shared-basis condition the overlap
    /// produces, deterministically.
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

    /// The only case where a usable second fix reaches the side check and agrees. Without it,
    /// inverting that branch would leave the suite green.
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

    /// Side disagreement has its own record, distinct from `within_accuracy`, which describes a fix
    /// that could not pick a side.
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

    /// A second fix too coarse to judge this venue adds nothing to the first, which is not the
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

        #expect(await setup.resolver.corroborationFix(newerThan: clock.now, cache: PassCorroboration()) == .unavailable)
    }
}
