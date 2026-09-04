@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import CoreLocation
import Foundation
import SharedTests
import Testing

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

    private func polygonGeofence(id: String = "1", transitionTypes: Set<GeofenceTransition> = [.enter, .exit]) -> Geofence {
        Geofence(
            id: id, latitude: 0, longitude: 0, radius: 300, name: "poly",
            transitionTypes: transitionTypes, lastUpdated: Date(), vertices: Self.squareVertices
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
    }

    private func makeSetup(fix: CLLocation?) async -> Setup {
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
        }
        return Setup(
            resolver: PolygonMembershipResolver(
                storage: storage,
                transitionEmitter: emitter,
                logger: LoggerMock(),
                fixResolver: fixResolver
            ),
            storage: storage,
            emitter: emitter,
            fixResolver: fixResolver
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
    private final class RequestCounter {
        var count = 0
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
