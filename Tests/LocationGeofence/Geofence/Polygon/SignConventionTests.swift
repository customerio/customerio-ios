@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

/// The two edge-distance conventions are opposite: polygon is positive inside, circle is negative
/// inside. Asserted by physical position, so flipping either convention breaks these.
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
        #expect(BaselineHealDecision.synthesizedTransition(
            distanceFromCenter: circle.distanceTo(at), radius: circle.radius,
            horizontalAccuracy: 5, fixAge: 1, lastState: .exit
        ) == .enter)
    }

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
