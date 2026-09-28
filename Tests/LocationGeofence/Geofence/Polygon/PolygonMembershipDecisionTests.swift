@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

@Suite("PolygonMembershipDecision")
struct PolygonMembershipDecisionTests {
    private let freshAge: TimeInterval = 1

    // MARK: - Verdicts

    @Test
    func resolvedMembership_givenFixWellInside_expectInside() {
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: 100, horizontalAccuracy: 10, fixAge: freshAge
        ) == .inside)
    }

    @Test
    func resolvedMembership_givenFixWellOutside_expectOutside() {
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: -100, horizontalAccuracy: 10, fixAge: freshAge
        ) == .outside)
    }

    // MARK: - Ambiguity band

    @Test(arguments: [0.0, 0.9, -0.9])
    func resolvedMembership_givenDistanceInsideAccuracy_expectNoVerdict(distance: Double) {
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: distance, horizontalAccuracy: 1, fixAge: freshAge
        ) == nil)
    }

    @Test
    func resolvedMembership_givenRetailDepthOnAGoodFix_expectInside() {
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: 15, horizontalAccuracy: 5, fixAge: freshAge
        ) == .inside)
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: 4, horizontalAccuracy: 5, fixAge: freshAge
        ) == nil)
    }

    @Test
    func resolvedMembership_givenDistanceExactlyAtAccuracy_expectNoVerdict() {
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: 10, horizontalAccuracy: 10, fixAge: freshAge
        ) == nil)
    }

    // MARK: - Fix quality guards

    @Test
    func resolvedMembership_givenStaleFix_expectNoVerdict() {
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: 100,
            horizontalAccuracy: 10,
            fixAge: GeofenceConstants.movementFixMaxAge + 1
        ) == nil)
    }

    @Test
    func resolvedMembership_givenFutureDatedFix_expectNoVerdict() {
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: 100, horizontalAccuracy: 10, fixAge: -1
        ) == nil)
    }

    @Test(arguments: [0.0, -1.0])
    func resolvedMembership_givenNonPositiveAccuracy_expectNoVerdict(accuracy: Double) {
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: 100, horizontalAccuracy: accuracy, fixAge: freshAge
        ) == nil)
    }

    @Test
    func resolvedMembership_givenFixAtMaxAge_expectVerdict() {
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: 100,
            horizontalAccuracy: 10,
            fixAge: GeofenceConstants.movementFixMaxAge
        ) == .inside)
    }

    // MARK: - The arrival rule (three-state outcome)

    /// Big enough that the venue ceiling never applies.
    private let roomyVenue: Double = 200

    @Test
    func resolvedOutcome_givenClearanceBeyondAccuracy_expectDecidedAlone() {
        #expect(PolygonMembershipDecision.resolvedOutcome(
            signedEdgeDistance: 30, horizontalAccuracy: 10, fixAge: freshAge, venueScale: roomyVenue
        ) == .decided(.inside))
    }

    @Test
    func resolvedOutcome_givenMarginalInside_expectCorroboration() {
        #expect(PolygonMembershipDecision.resolvedOutcome(
            signedEdgeDistance: 3, horizontalAccuracy: 10, fixAge: freshAge, venueScale: roomyVenue
        ) == .needsCorroboration(.inside))
    }

    @Test
    func resolvedOutcome_givenMarginalOutside_expectUndecidedNotCorroboration() {
        #expect(PolygonMembershipDecision.resolvedOutcome(
            signedEdgeDistance: -3, horizontalAccuracy: 10, fixAge: freshAge, venueScale: roomyVenue
        ) == .undecided(.withinAccuracy))
    }

    @Test
    func resolvedOutcome_givenClearanceOutside_expectDecidedOutside() {
        #expect(PolygonMembershipDecision.resolvedOutcome(
            signedEdgeDistance: -30, horizontalAccuracy: 10, fixAge: freshAge, venueScale: roomyVenue
        ) == .decided(.outside))
    }

    // MARK: - The per-fence ceiling

    @Test
    func resolvedOutcome_givenAccuracyWiderThanTheVenue_expectAccuracyTooLow() {
        #expect(PolygonMembershipDecision.resolvedOutcome(
            signedEdgeDistance: 5, horizontalAccuracy: 30, fixAge: freshAge, venueScale: 24.2
        ) == .undecided(.accuracyTooLow))
    }

    /// The ceiling gates arrivals only: a clear exit from a thin ring still decides.
    @Test
    func resolvedOutcome_givenClearOfAThinVenueByMoreThanAccuracy_expectDecidedOutside() {
        #expect(PolygonMembershipDecision.resolvedOutcome(
            signedEdgeDistance: -30, horizontalAccuracy: 25, fixAge: freshAge, venueScale: 19.05
        ) == .decided(.outside))
    }

    /// Control for the test above: the exit must still clear the fix's accuracy.
    @Test
    func resolvedOutcome_givenInsideAThinVenuesAccuracyBand_expectStillRefused() {
        #expect(PolygonMembershipDecision.resolvedOutcome(
            signedEdgeDistance: -20, horizontalAccuracy: 25, fixAge: freshAge, venueScale: 19.05
        ) == .undecided(.accuracyTooLow))
    }

    @Test
    func resolvedOutcome_givenInsideAThinVenue_expectAccuracyTooLow() {
        #expect(PolygonMembershipDecision.resolvedOutcome(
            signedEdgeDistance: 8, horizontalAccuracy: 25, fixAge: freshAge, venueScale: 19.05
        ) == .undecided(.accuracyTooLow))
    }

    /// Control for the 24.2 m venue test: the same 30 m fix on a larger venue is corroborated.
    @Test
    func resolvedOutcome_givenTheSameFixOnALargerVenue_expectCorroboration() {
        #expect(PolygonMembershipDecision.resolvedOutcome(
            signedEdgeDistance: 5, horizontalAccuracy: 30, fixAge: freshAge, venueScale: 229.3
        ) == .needsCorroboration(.inside))
    }

    @Test
    func resolvedOutcome_givenStaleFix_expectFixTooOldNotWithinAccuracy() {
        #expect(PolygonMembershipDecision.resolvedOutcome(
            signedEdgeDistance: 100, horizontalAccuracy: 5,
            fixAge: GeofenceConstants.movementFixMaxAge + 1, venueScale: roomyVenue
        ) == .undecided(.fixTooOld))
    }

    @Test
    func resolvedMembership_givenMarginalInside_expectNil() {
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: 3, horizontalAccuracy: 10, fixAge: freshAge
        ) == nil)
    }

    // MARK: - PolygonRegion.scale (the per-fence ceiling)

    /// At the equator, so tests can use a fixed metres-per-degree.
    private func square(sideDegrees: Double) -> PolygonRegion? {
        PolygonRegion(vertices: [
            LocationData(latitude: 0, longitude: 0),
            LocationData(latitude: 0, longitude: sideDegrees),
            LocationData(latitude: sideDegrees, longitude: sideDegrees),
            LocationData(latitude: sideDegrees, longitude: 0)
        ])
    }

    @Test
    func scale_givenASquare_expectHalfTheSide() throws {
        let region = try #require(square(sideDegrees: 0.001))
        let side = 0.001 * 111320.0
        #expect(abs(region.scale - side / 2) < side * 0.02)
    }

    @Test
    func scale_givenAnExplicitlyClosedRing_expectTheSameAsItsOpenTwin() throws {
        let open = try #require(square(sideDegrees: 0.001))
        let closed = try #require(PolygonRegion(vertices: [
            LocationData(latitude: 0, longitude: 0),
            LocationData(latitude: 0, longitude: 0.001),
            LocationData(latitude: 0.001, longitude: 0.001),
            LocationData(latitude: 0.001, longitude: 0),
            LocationData(latitude: 0, longitude: 0)
        ]))
        #expect(abs(open.scale - closed.scale) < 0.5)
    }

    @Test
    func scale_givenCollinearVertices_expectZeroSoNothingDecides() throws {
        let sliver = try #require(PolygonRegion(vertices: [
            LocationData(latitude: 0, longitude: 0),
            LocationData(latitude: 0, longitude: 0.001),
            LocationData(latitude: 0, longitude: 0.002)
        ]))
        #expect(sliver.scale < 1)
        #expect(PolygonMembershipDecision.resolvedOutcome(
            signedEdgeDistance: 5, horizontalAccuracy: 5, fixAge: freshAge, venueScale: sliver.scale
        ) == .undecided(.accuracyTooLow))
    }

    @Test
    func scale_givenAThinRectangle_expectAtLeastHalfTheShortSide() throws {
        let region = try #require(PolygonRegion(vertices: [
            LocationData(latitude: 0, longitude: 0),
            LocationData(latitude: 0, longitude: 0.01),
            LocationData(latitude: 0.0002, longitude: 0.01),
            LocationData(latitude: 0.0002, longitude: 0)
        ]))
        let shortSide = 0.0002 * 111320.0
        #expect(region.scale >= shortSide / 2 * 0.95)
    }
}
