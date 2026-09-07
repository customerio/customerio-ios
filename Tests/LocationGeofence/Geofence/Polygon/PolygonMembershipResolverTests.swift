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
        private(set) var delivered: [(id: String, transition: GeofenceTransition)] = []

        func trackTransition(geofenceId: String, transition: GeofenceTransition) async {
            delivered.append((geofenceId, transition))
        }

        func snapshot() -> [(id: String, transition: GeofenceTransition)] {
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

    private func fix(latitude: Double, longitude: Double, accuracy: Double = 5) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 5,
            timestamp: Date()
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

    private func yieldUntil(_ condition: () -> Bool) async {
        for _ in 0 ..< 1000 where !condition() {
            await Task.yield()
        }
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

        await setup.resolver.evaluateAllPolygons()

        #expect(counter.count == 1)
    }

    /// Foregrounds arrive in bursts. A second concurrent pass reads the same storage and the same
    /// fix, so it can only duplicate the location work.
    @Test
    func evaluateAllPolygons_givenConcurrentPasses_expectSecondSkipped() async {
        let setup = await makeSetup(fix: nil)
        await registerPolygons(setup, ids: ["1", "2"])
        let counter = countingRequests(setup)

        async let first: Void = setup.resolver.evaluateAllPolygons()
        async let second: Void = setup.resolver.evaluateAllPolygons()
        _ = await(first, second)

        #expect(counter.count == 1)
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
            geofenceIds: ["1"], reason: "test", isStillCurrent: { false }
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
            geofenceIds: ["1"], reason: "test", isStillCurrent: { true }
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

        async let pass: Void = setup.resolver.evaluateMembership(geofenceIds: ["1"], reason: "test")
        await yieldUntil { requested.value }
        await setup.storage.setCachedGeofences([movedPolygonGeofence()])
        setup.fixResolver.handleResolvedFix(fix(latitude: 0, longitude: 0))
        await pass

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

        async let pass: Void = setup.resolver.evaluateMembership(geofenceIds: ["1"], reason: "test")
        await yieldUntil { requested.value }
        setup.fixResolver.handleResolvedFix(fix(latitude: 0, longitude: 0))
        await pass

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

        await setup.resolver.evaluateMembership(geofenceIds: ["1", "2", "3"], reason: "test")

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
            eventCircle: MonitoredCircle(
                center: LocationData(latitude: original.latitude, longitude: original.longitude),
                radius: original.radius, maximumRadius: 1000
            )
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
            eventCircle: MonitoredCircle(
                center: LocationData(latitude: geofence.latitude, longitude: geofence.longitude),
                radius: geofence.radius, maximumRadius: 1000
            )
        )

        #expect(await setup.emitter.snapshot().first?.transition == .exit)
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
            eventCircle: MonitoredCircle(
                center: LocationData(latitude: 0, longitude: 0),
                radius: min(5000, 1000), maximumRadius: 1000
            )
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

        async let pass: Void = setup.resolver.evaluateAllPolygons()
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

        async let pass: Void = setup.resolver.evaluateAllPolygons()
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

        async let pass: Void = setup.resolver.evaluateAllPolygons()
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

        async let pass: Void = setup.resolver.evaluateAllPolygons()
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
        await yieldUntil { logged(setup.logger, "user changed while resolving the fix") }

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

        await setup.resolver.evaluateAllPolygons(isStillCurrent: {
            asked.count += 1
            return asked.count == 1
        })

        #expect(asked.count == 2)
        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
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

        await setup.resolver.evaluateAllPolygons()

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

        await setup.resolver.evaluateAllPolygons()

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
}
