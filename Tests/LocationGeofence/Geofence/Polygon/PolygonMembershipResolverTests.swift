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
        let coordinator: GeofenceSyncCoordinatorMock
        let fixResolver: MovementFixResolver
    }

    private func makeSetup(fix: CLLocation?) async -> Setup {
        let storage = GeofenceStorage(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let emitter = EmitterSpy()
        let coordinator = GeofenceSyncCoordinatorMock()
        coordinator.reapplyRegistrationReturnValue = .success(())
        let fixResolver = MovementFixResolver(logger: LoggerMock())
        // Seam: resolve inline with the supplied fix instead of touching CoreLocation.
        fixResolver.requestFreshFix = { [weak fixResolver] in
            guard let fix else { return fixResolver?.handleRequestFailure() ?? () }
            fixResolver?.handleResolvedFix(fix)
        }
        return Setup(
            resolver: PolygonMembershipResolver(
                storage: storage,
                transitionEmitter: emitter,
                coordinator: coordinator,
                logger: LoggerMock(),
                fixResolver: fixResolver
            ),
            storage: storage,
            emitter: emitter,
            coordinator: coordinator,
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

    // MARK: - Circle fences pass through untouched

    @Test
    func handleTransition_givenCircleGeofence_expectForwardedUnchanged() async {
        let setup = await makeSetup(fix: nil)
        await setup.storage.setCachedGeofences([circleGeofence()])

        await setup.resolver.handleTransition(identifier: "2", transition: .enter, location: nil)

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1)
        #expect(delivered.first?.transition == .enter)
    }

    /// A sync can drop a geofence the OS still holds a condition for. Forwarding beats dropping:
    /// losing a real crossing is worse than one shaped like its covering circle.
    @Test
    func handleTransition_givenUncachedGeofence_expectForwarded() async {
        let setup = await makeSetup(fix: nil)

        await setup.resolver.handleTransition(identifier: "999", transition: .exit, location: nil)

        #expect(await setup.emitter.snapshot().count == 1)
    }

    // MARK: - Covering-circle enter

    @Test
    func handleTransition_givenPolygonEnterAndFixInside_expectEnterDelivered() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, location: nil)

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1)
        #expect(delivered.first?.transition == .enter)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    /// The annulus: inside the covering circle, outside the polygon. Nothing is delivered, and the
    /// tripwire is what will wake us to try again.
    @Test
    func handleTransition_givenPolygonEnterAndFixInAnnulus_expectNoEventButTripwirePlanted() async {
        let setup = await makeSetup(fix: fix(latitude: 0.0024, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, location: nil)

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .outside)
        #expect(await setup.storage.getPolygonTripwires()["1"] != nil)
        #expect(setup.coordinator.reapplyRegistrationCallsCount == 1)
    }

    /// A fix too coarse to place the device relative to the boundary must leave no belief behind,
    /// but must still plant the tripwire that buys another attempt.
    @Test
    func handleTransition_givenUndecidableFix_expectNoBeliefButTripwirePlanted() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0, accuracy: 400))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, location: nil)

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"] == nil)
        #expect(await setup.storage.getPolygonTripwires()["1"] != nil)
    }

    @Test
    func handleTransition_givenNoFixObtainable_expectNothingRecorded() async {
        let setup = await makeSetup(fix: nil)
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, location: nil)

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"] == nil)
        #expect(await setup.storage.getPolygonTripwires()["1"] == nil)
    }

    // MARK: - Covering-circle exit

    /// polygon ⊆ circle, so leaving the circle proves the polygon was left — no fix required.
    @Test
    func handleTransition_givenPolygonExitWhileInside_expectExitDeliveredWithoutFix() async {
        let setup = await makeSetup(fix: nil)
        await setup.storage.setCachedGeofences([polygonGeofence()])
        _ = await setup.storage.recordPolygonMembership(.inside, forIdentifier: "1")
        await setup.storage.setPolygonTripwire(
            PolygonTripwire(center: LocationData(latitude: 0, longitude: 0), radius: 100), forIdentifier: "1"
        )

        await setup.resolver.handleTransition(
            identifier: "1", transition: .exit, location: LocationData(latitude: 1, longitude: 1)
        )

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1)
        #expect(delivered.first?.transition == .exit)
        #expect(await setup.storage.getPolygonTripwires()["1"] == nil)
    }

    @Test
    func handleTransition_givenPolygonExitWhileNotInside_expectSilent() async {
        let setup = await makeSetup(fix: nil)
        await setup.storage.setCachedGeofences([polygonGeofence()])
        _ = await setup.storage.recordPolygonMembership(.outside, forIdentifier: "1")

        await setup.resolver.handleTransition(identifier: "1", transition: .exit, location: nil)

        #expect(await setup.emitter.snapshot().isEmpty)
    }

    // MARK: - Tripwire wake

    @Test
    func evaluateMembership_givenDeviceNowInsidePolygon_expectEnterDelivered() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])
        // Seeded older than the fix: a belief written *after* the fix was taken correctly outranks
        // it, which is the `onlyIfBeliefPredates` guard and not what this test is about.
        _ = await setup.storage.recordPolygonMembership(
            .outside, forIdentifier: "1", now: Date().addingTimeInterval(-60)
        )

        await setup.resolver.evaluateMembership(geofenceId: "1", reason: "test")

        let delivered = await setup.emitter.snapshot()
        #expect(delivered.count == 1)
        #expect(delivered.first?.transition == .enter)
    }

    /// The tripwire reaches the polygon boundary, so leaving it is exactly when the verdict stops
    /// being safe to trust. Here the fix sits ~89 m outside the square's edge.
    @Test
    func evaluateMembership_expectTripwireRadiusReachesPolygonEdge() async {
        let setup = await makeSetup(fix: fix(latitude: 0.0024, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.evaluateMembership(geofenceId: "1", reason: "test")

        let tripwire = await setup.storage.getPolygonTripwires()["1"]
        #expect(tripwire != nil)
        #expect((tripwire?.radius ?? 0) >= GeofenceConstants.polygonTripwireMinRadius)
    }

    /// Below the floor the OS promotes crossings too unreliably for the slot to be worth spending.
    @Test
    func evaluateMembership_givenDeviceNearEdge_expectTripwireFloored() async {
        let setup = await makeSetup(fix: fix(latitude: 0.00175, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.evaluateMembership(geofenceId: "1", reason: "test")

        #expect(await setup.storage.getPolygonTripwires()["1"]?.radius == GeofenceConstants.polygonTripwireMinRadius)
    }

    /// Field case, 2026-08-29: the OS delivered a covering-circle ENTER while our cached fix was
    /// 15.5 s old — inside `movementFixMaxAge`, but ~400 m stale at driving speed, so it placed the
    /// device outside the very circle the OS had just reported entering. The containment gate then
    /// retired the tripwire and the device spent 12 minutes in the annulus with no wake source.
    /// The OS's own statement outranks our fix on this path.
    @Test
    func handleTransition_givenCoveringCircleEnterAndStaleFixOutsideCircle_expectTripwirePlanted() async {
        let setup = await makeSetup(fix: fix(latitude: 0.01, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.handleTransition(identifier: "1", transition: .enter, location: nil)

        #expect(await setup.storage.getPolygonTripwires()["1"] != nil)
    }

    /// Without an OS statement, a fix that lands just outside the circle is inside its own
    /// uncertainty. Keeping the tripwire costs a slot; dropping it can cost a crossing.
    @Test
    func evaluateMembership_givenFixMarginallyOutsideCircle_expectTripwireKept() async {
        let setup = await makeSetup(fix: fix(latitude: 0.0028, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])
        await setup.storage.setPolygonTripwire(
            PolygonTripwire(center: LocationData(latitude: 0.0024, longitude: 0), radius: 120),
            forIdentifier: "1"
        )

        await setup.resolver.evaluateMembership(geofenceId: "1", reason: "test")

        #expect(await setup.storage.getPolygonTripwires()["1"] != nil)
    }

    /// Found in the field: a foreground evaluation runs over EVERY registered polygon, including
    /// ones the device is kilometres away from. Planting there spends one of the 20 OS regions on a
    /// circle that can never fire before the covering circle's own exit does, and with a full fence
    /// set those wasted slots evict real fences.
    @Test
    func evaluateMembership_givenDeviceOutsideCoveringCircle_expectNoTripwire() async {
        let setup = await makeSetup(fix: fix(latitude: 0.02, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.evaluateMembership(geofenceId: "1", reason: "test")

        #expect(await setup.storage.getPolygonTripwires()["1"] == nil)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .outside)
    }

    /// Leaving the covering circle must retire an existing tripwire, not strand it: a stranded one
    /// keeps costing a slot and gets re-registered by every later sync.
    @Test
    func evaluateMembership_givenTripwireAndDeviceOutsideCoveringCircle_expectTripwireCleared() async {
        let setup = await makeSetup(fix: fix(latitude: 0.02, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])
        await setup.storage.setPolygonTripwire(
            PolygonTripwire(center: LocationData(latitude: 0.0024, longitude: 0), radius: 300),
            forIdentifier: "1"
        )

        await setup.resolver.evaluateMembership(geofenceId: "1", reason: "test")

        #expect(await setup.storage.getPolygonTripwires()["1"] == nil)
    }

    /// The radius reaches the polygon edge and is NOT clipped to the covering circle. A tripwire
    /// wider than the circle is redundant, not harmful — the circle's own exit fires first — but a
    /// small one is never promoted by the OS at all, which is the failure actually measured in the
    /// field. Promotability wins over tidiness.
    @Test
    func evaluateMembership_givenPolygonFarInsideLargeCircle_expectRadiusReachesPolygonNotCircle() async throws {
        let setup = await makeSetup(fix: fix(latitude: 0.0135, longitude: 0))
        let wide = Geofence(
            id: "1", latitude: 0, longitude: 0, radius: 2000, name: "poly",
            transitionTypes: [.enter, .exit], lastUpdated: Date(), vertices: Self.squareVertices
        )
        await setup.storage.setCachedGeofences([wide])

        await setup.resolver.evaluateMembership(geofenceId: "1", reason: "test")

        let radius = try #require(await setup.storage.getPolygonTripwires()["1"]?.radius)
        // ~1493 m from the centre, so ~1316 m to the polygon edge — well past the ~507 m of
        // circle that remains.
        #expect(radius > 1200)
    }

    /// Re-registering an unchanged circle risks absorbing a crossing the OS detected but has not
    /// delivered, so an evaluation that does not move the tripwire must not touch the OS set.
    @Test
    func evaluateMembership_givenUnchangedTripwire_expectNoReregistration() async {
        let setup = await makeSetup(fix: fix(latitude: 0, longitude: 0))
        await setup.storage.setCachedGeofences([polygonGeofence()])

        await setup.resolver.evaluateMembership(geofenceId: "1", reason: "test")
        let afterFirst = setup.coordinator.reapplyRegistrationCallsCount
        await setup.resolver.evaluateMembership(geofenceId: "1", reason: "test")

        #expect(afterFirst == 1)
        #expect(setup.coordinator.reapplyRegistrationCallsCount == 1)
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

        await setup.resolver.handleTransition(identifier: "1", transition: .exit, location: nil)

        #expect(await setup.emitter.snapshot().isEmpty)
        #expect(await setup.storage.getPolygonMembership()["1"]?.membership == .outside)
    }
}
