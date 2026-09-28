@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

/// Pins the RELATIONSHIP between the SDK's two edge-distance conventions, which are opposite:
/// `PolygonRegion.signedEdgeDistance` is positive inside, while the circle path's edge distance
/// (`distanceFromCenter - radius`, as `BaselineHealDecision` computes it) is negative inside. Each
/// side's own tests are self-consistent, so mixing the two up inverts verdicts without failing them.
///
/// Phrased in terms of PHYSICAL POSITION rather than sign, so flipping either convention breaks them.
@Suite("Edge-distance sign conventions")
struct SignConventionTests {
    private static let square = [
        LocationData(latitude: -0.0016, longitude: -0.0016),
        LocationData(latitude: -0.0016, longitude: 0.0016),
        LocationData(latitude: 0.0016, longitude: 0.0016),
        LocationData(latitude: 0.0016, longitude: -0.0016)
    ]

    private func circleGeofence() -> Geofence {
        Geofence(
            id: "c", latitude: 0, longitude: 0, radius: 200, name: nil,
            transitionTypes: [.enter, .exit], lastUpdated: Date()
        )
    }

    /// One physical fact — the device is inside — must be reported as inside by BOTH layers, even
    /// though they express it with opposite signs.
    @Test
    func deviceInside_expectBothLayersAgreeDespiteOppositeSigns() {
        let at = LocationData(latitude: 0, longitude: 0)
        let polygon = PolygonRegion(vertices: Self.square)
        let circle = circleGeofence()

        let polygonSigned = polygon?.signedEdgeDistance(to: at) ?? 0
        let circleEdge = circle.distanceTo(at) - circle.radius

        #expect(polygonSigned > 0, "polygon convention: positive inside")
        #expect(circleEdge < 0, "circle convention: negative inside")

        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: polygonSigned, horizontalAccuracy: 5, fixAge: 1
        ) == .inside)
        // The heal reads the circle convention: a stored `.exit` baseline contradicted by a device
        // that is actually inside must synthesize `.enter`.
        #expect(BaselineHealDecision.synthesizedTransition(
            distanceFromCenter: circle.distanceTo(at), radius: circle.radius,
            horizontalAccuracy: 5, fixAge: 1, lastState: .exit
        ) == .enter)
    }

    /// The mirror image, so a decision that ignores position cannot pass both tests.
    @Test
    func deviceOutside_expectBothLayersAgreeDespiteOppositeSigns() {
        let at = LocationData(latitude: 0.01, longitude: 0)
        let polygon = PolygonRegion(vertices: Self.square)
        let circle = circleGeofence()

        let polygonSigned = polygon?.signedEdgeDistance(to: at) ?? 0
        let circleEdge = circle.distanceTo(at) - circle.radius

        #expect(polygonSigned < 0, "polygon convention: negative outside")
        #expect(circleEdge > 0, "circle convention: positive outside")

        #expect(PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: polygonSigned, horizontalAccuracy: 5, fixAge: 1
        ) == .outside)
        #expect(BaselineHealDecision.synthesizedTransition(
            distanceFromCenter: circle.distanceTo(at), radius: circle.radius,
            horizontalAccuracy: 5, fixAge: 1, lastState: .enter
        ) == .exit)
    }
}
