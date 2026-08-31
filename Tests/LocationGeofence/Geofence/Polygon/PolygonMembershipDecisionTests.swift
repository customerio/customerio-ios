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

    /// The margin floor is 20 m even when the fix claims better accuracy, so a fix hugging the
    /// boundary never produces a verdict.
    @Test(arguments: [0.0, 5.0, -5.0, 19.9, -19.9])
    func resolvedMembership_givenDistanceInsideMarginFloor_expectNoVerdict(distance: Double) {
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: distance, horizontalAccuracy: 1, fixAge: freshAge
        ) == nil)
    }

    /// With accuracy worse than the floor, the accuracy is the margin.
    @Test
    func resolvedMembership_givenDistanceInsideAccuracyMargin_expectNoVerdict() {
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: 50, horizontalAccuracy: 65, fixAge: freshAge
        ) == nil)
    }

    @Test
    func resolvedMembership_givenDistanceJustBeyondAccuracyMargin_expectVerdict() {
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: 66, horizontalAccuracy: 65, fixAge: freshAge
        ) == .inside)
    }

    /// Boundary is exclusive: exactly at the margin is still ambiguous.
    @Test
    func resolvedMembership_givenDistanceExactlyAtMargin_expectNoVerdict() {
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: 20, horizontalAccuracy: 10, fixAge: freshAge
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

    /// The guard is on age, not on the fix being at the very edge of the window.
    @Test
    func resolvedMembership_givenFixAtMaxAge_expectVerdict() {
        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: 100,
            horizontalAccuracy: 10,
            fixAge: GeofenceConstants.movementFixMaxAge
        ) == .inside)
    }
}
