@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

/// Pins the RELATIONSHIP between the two edge-distance conventions in the SDK, which are opposite.
///
/// `PolygonRegion.signedEdgeDistance` is positive inside; the circle path's edge distance
/// (`distanceFromCenter - radius`, what `BaselineHealDecision` consumes) is negative inside. The
/// kernel's doc comment once claimed they were interchangeable, and the polygon decision function
/// was written against that claim — producing inverted verdicts that neither side's unit tests
/// could see, because each was self-consistent.
///
/// These tests are deliberately phrased in terms of PHYSICAL POSITION rather than sign, so flipping
/// either convention breaks them. They are the cross-check that survives both implementations
/// being ours.
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

    /// And the mirror image, so a test that passes by flipping both conventions at once fails here.
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
