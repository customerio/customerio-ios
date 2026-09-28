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

    /// A fix hugging the boundary never decides ALONE: the margin is the fix's own accuracy.
    @Test(arguments: [0.0, 0.9, -0.9])
    func resolvedMembership_givenDistanceInsideAccuracy_expectNoVerdict(distance: Double) {
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: distance, horizontalAccuracy: 1, fixAge: freshAge
        ) == nil)
    }

    /// No margin floor: a 15 m edge on a 5 m fix is a real position inside a retail venue only 24 m
    /// deep, and any floor at or above 15 m would leave it undecided.
    @Test
    func resolvedMembership_givenRetailDepthOnAGoodFix_expectInside() {
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: 15, horizontalAccuracy: 5, fixAge: freshAge
        ) == .inside)
        // Negative control: inside the accuracy is still not a solo verdict.
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: 4, horizontalAccuracy: 5, fixAge: freshAge
        ) == nil)
    }

    /// Boundary is exclusive: exactly at the margin is still ambiguous, not a verdict.
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

    /// A negative age means a fix timestamped in the future — unusable, not "extra fresh".
    @Test
    func resolvedMembership_givenFutureDatedFix_expectNoVerdict() {
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: 100, horizontalAccuracy: 10, fixAge: -1
        ) == nil)
    }

    /// CoreLocation reports a non-positive accuracy when the fix is invalid.
    @Test(arguments: [0.0, -1.0])
    func resolvedMembership_givenNonPositiveAccuracy_expectNoVerdict(accuracy: Double) {
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: 100, horizontalAccuracy: accuracy, fixAge: freshAge
        ) == nil)
    }

    /// The age bound is inclusive.
    @Test
    func resolvedMembership_givenFixAtMaxAge_expectVerdict() {
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: 100,
            horizontalAccuracy: 10,
            fixAge: GeofenceConstants.movementFixMaxAge
        ) == .inside)
    }

    // MARK: - The arrival rule (three-state outcome)

    /// A big venue: the ceiling is far away, so behaviour is the plain accuracy test.
    private let roomyVenue: Double = 200

    @Test
    func resolvedOutcome_givenClearanceBeyondAccuracy_expectDecidedAlone() {
        #expect(PolygonMembershipDecision.resolvedOutcome(
            signedEdgeDistance: 30, horizontalAccuracy: 10, fixAge: freshAge, venueScale: roomyVenue
        ) == .decided(.inside))
    }

    /// The case the rule exists for: inside, but not by more than the fix's own accuracy.
    @Test
    func resolvedOutcome_givenMarginalInside_expectCorroboration() {
        #expect(PolygonMembershipDecision.resolvedOutcome(
            signedEdgeDistance: 3, horizontalAccuracy: 10, fixAge: freshAge, venueScale: roomyVenue
        ) == .needsCorroboration(.inside))
    }

    /// The asymmetry: an equally marginal fix on the OUTSIDE is not a verdict and is never
    /// corroborated, so an ambiguous fix can never end a visit early.
    @Test
    func resolvedOutcome_givenMarginalOutside_expectUndecidedNotCorroboration() {
        #expect(PolygonMembershipDecision.resolvedOutcome(
            signedEdgeDistance: -3, horizontalAccuracy: 10, fixAge: freshAge, venueScale: roomyVenue
        ) == .undecided(.withinAccuracy))
    }

    /// Clearance beyond accuracy on the outside still decides — that is how an exit is claimed.
    @Test
    func resolvedOutcome_givenClearanceOutside_expectDecidedOutside() {
        #expect(PolygonMembershipDecision.resolvedOutcome(
            signedEdgeDistance: -30, horizontalAccuracy: 10, fixAge: freshAge, venueScale: roomyVenue
        ) == .decided(.outside))
    }

    // MARK: - The per-fence ceiling

    /// A small retail ring with scale 24.2 m. A 30 m fix says nothing about a venue that shallow,
    /// so it is refused rather than corroborated: a second equally blind fix adds nothing.
    @Test
    func resolvedOutcome_givenAccuracyWiderThanTheVenue_expectAccuracyTooLow() {
        #expect(PolygonMembershipDecision.resolvedOutcome(
            signedEdgeDistance: 5, horizontalAccuracy: 30, fixAge: freshAge, venueScale: 24.2
        ) == .undecided(.accuracyTooLow))
    }

    /// The ceiling gates ARRIVALS only. A 400 m x 20 m ring has a scale of ~19 m, and a fix 30 m
    /// clear of it at 25 m accuracy is decisively outside. Refusing it would leave the visit open:
    /// the point is still inside the covering circle, so no circle exit closes it, and the next
    /// return misses its enter.
    @Test
    func resolvedOutcome_givenClearOfAThinVenueByMoreThanAccuracy_expectDecidedOutside() {
        #expect(PolygonMembershipDecision.resolvedOutcome(
            signedEdgeDistance: -30, horizontalAccuracy: 25, fixAge: freshAge, venueScale: 19.05
        ) == .decided(.outside))
    }

    /// Clearance is measured against the fix's own accuracy, so a fix that does NOT clear a thin
    /// ring is still refused. Without this, the test above would pass for a rule that skipped the
    /// ceiling for anything negative.
    @Test
    func resolvedOutcome_givenInsideAThinVenuesAccuracyBand_expectStillRefused() {
        #expect(PolygonMembershipDecision.resolvedOutcome(
            signedEdgeDistance: -20, horizontalAccuracy: 25, fixAge: freshAge, venueScale: 19.05
        ) == .undecided(.accuracyTooLow))
    }

    /// An ARRIVAL on the same thin venue stays refused: being within a 25 m circle of a ring only
    /// 19 m deep says nothing about being in it.
    @Test
    func resolvedOutcome_givenInsideAThinVenue_expectAccuracyTooLow() {
        #expect(PolygonMembershipDecision.resolvedOutcome(
            signedEdgeDistance: 8, horizontalAccuracy: 25, fixAge: freshAge, venueScale: 19.05
        ) == .undecided(.accuracyTooLow))
    }

    /// Negative control for the ceiling: the SAME fix against a venue big enough to resolve is
    /// corroborated, not refused. Without this the test above would pass for a rule that simply
    /// rejected 30 m accuracy everywhere.
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

    /// `resolvedMembership` has no corroboration step, so a marginal inside must read as no verdict
    /// rather than silently deciding.
    @Test
    func resolvedMembership_givenMarginalInside_expectNil() {
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: 3, horizontalAccuracy: 10, fixAge: freshAge
        ) == nil)
    }

    // MARK: - PolygonRegion.scale (the per-fence ceiling)

    /// At the equator, so the tests can use a fixed metres-per-degree: they assert ratios and
    /// tolerances, not absolute geodesy.
    private func square(sideDegrees: Double) -> PolygonRegion? {
        PolygonRegion(vertices: [
            LocationData(latitude: 0, longitude: 0),
            LocationData(latitude: 0, longitude: sideDegrees),
            LocationData(latitude: sideDegrees, longitude: sideDegrees),
            LocationData(latitude: sideDegrees, longitude: 0)
        ])
    }

    /// For a square, `2A/P` is exactly half the side, which is also its true inradius.
    @Test
    func scale_givenASquare_expectHalfTheSide() throws {
        let region = try #require(square(sideDegrees: 0.001))
        let side = 0.001 * 111320.0
        #expect(abs(region.scale - side / 2) < side * 0.02)
    }

    /// A ring whose last vertex repeats the first must measure the same: the closing edge has zero
    /// length and contributes nothing to either sum.
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

    /// A degenerate ring measures 0, so no arrival can be decided: the ceiling fails closed, not
    /// open.
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

    /// A long thin ring is where `2A/P` is least like the inradius. It must still err HIGH, widening
    /// what we accept instead of refusing a real venue.
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
