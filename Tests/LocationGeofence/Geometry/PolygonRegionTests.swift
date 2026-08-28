@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

@Suite("PolygonRegion")
struct PolygonRegionTests {
    @Test
    func fixtures_givenCrossSDKVectors_expectInsideAndDistanceAgree() throws {
        for fixture in polygonGeometryFixtures {
            let region = try #require(PolygonRegion(vertices: fixture.vertices), "\(fixture.name)")
            for sample in fixture.samples {
                #expect(
                    region.contains(sample.point) == sample.inside,
                    "\(fixture.name): \(sample.note)"
                )
                let sd = region.signedEdgeDistance(to: sample.point)
                #expect(
                    abs(sd - sample.signedEdgeDistance) <= PolygonGeometryFixture.toleranceMeters,
                    "\(fixture.name): \(sample.note) — got \(sd), expected \(sample.signedEdgeDistance)"
                )
            }
        }
    }

    @Test
    func init_givenClosedRing_expectRingUnclosedAndGeometryIntact() throws {
        let fixture = try #require(polygonGeometryFixtures.first)
        var closed = fixture.vertices
        closed.append(closed[0])
        let region = try #require(PolygonRegion(vertices: closed))
        #expect(region.vertices.count == fixture.vertices.count)
        let sample = try #require(fixture.samples.first)
        #expect(region.contains(sample.point) == sample.inside)
    }

    @Test
    func init_givenDegenerateInput_expectNil() {
        #expect(PolygonRegion(vertices: []) == nil)
        let a = LocationData(latitude: 31.37, longitude: 74.17)
        let b = LocationData(latitude: 31.371, longitude: 74.171)
        #expect(PolygonRegion(vertices: [a, b]) == nil)
        // closed ring of 3 entries = 2 distinct vertices
        #expect(PolygonRegion(vertices: [a, b, a]) == nil)
    }

    @Test
    func signedEdgeDistance_givenSignFlipAcrossEdge_expectContinuousMagnitude() throws {
        // Walk a straight line across the square's eastern edge; the signed distance must
        // change sign exactly once and |sd| must be continuous (no jumps at the boundary).
        let square = try #require(polygonGeometryFixtures.first { $0.name == "square400" })
        let region = try #require(PolygonRegion(vertices: square.vertices))
        let lat = square.vertices.map(\.latitude).reduce(0, +) / Double(square.vertices.count)
        let lonInside = square.vertices.map(\.longitude).min()! * 0.3 + square.vertices.map(\.longitude).max()! * 0.7
        var previous: Double?
        var signFlips = 0
        for step in 0 ... 100 {
            let lon = lonInside + Double(step) * 0.00002 // ~1.9 m east per step; walk starts ~80 m
            // east of center, so 100 steps crosses the edge at +200 m with ~70 m to spare
            let sd = region.signedEdgeDistance(to: LocationData(latitude: lat, longitude: lon))
            if let previous, previous.sign != sd.sign, previous != 0 {
                signFlips += 1
                #expect(abs(previous) < 2.0, "jump at boundary: \(previous) -> \(sd)")
                #expect(abs(sd) < 2.0, "jump at boundary: \(previous) -> \(sd)")
            }
            previous = sd
        }
        #expect(signFlips == 1)
    }
}
