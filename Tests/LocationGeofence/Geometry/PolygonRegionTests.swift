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

    /// A bow-tie's lobes both read as inside under even-odd, at a signed distance decisive enough
    /// to clear the delivery gate — measured +33 m — so it would fire an enter for ground the
    /// polygon never covered. Rejected at construction, matching Android.
    @Test
    func init_givenSelfIntersectingRing_expectRejected() {
        let bowtie = [
            LocationData(latitude: 0.000, longitude: 0.000),
            LocationData(latitude: 0.002, longitude: 0.002),
            LocationData(latitude: 0.002, longitude: 0.000),
            LocationData(latitude: 0.000, longitude: 0.002)
        ]
        #expect(PolygonRegion(validating: bowtie) == nil)
    }

    /// Zero area: never contains anything, but would still hold an OS slot and drag the shared wake
    /// circle to its floor, so every other fence in the set wakes more often.
    @Test
    func init_givenCollinearRing_expectRejected() {
        let line = [
            LocationData(latitude: 0.000, longitude: 0.000),
            LocationData(latitude: 0.001, longitude: 0.000),
            LocationData(latitude: 0.002, longitude: 0.000)
        ]
        #expect(PolygonRegion(validating: line) == nil)
    }

    /// Two lobes joined at a single point: the bow-tie with its crossing degenerated to a vertex.
    /// Android rejects touches as well as crossings, so a crossing-only test here would let this
    /// through on iOS and drop it on Android.
    @Test
    func init_givenRingTouchingAtAVertex_expectRejected() {
        let touching = [
            LocationData(latitude: 0.000, longitude: 0.000),
            LocationData(latitude: 0.002, longitude: 0.000),
            LocationData(latitude: 0.001, longitude: 0.001),
            LocationData(latitude: 0.002, longitude: 0.002),
            LocationData(latitude: 0.000, longitude: 0.002),
            LocationData(latitude: 0.001, longitude: 0.001)
        ]
        #expect(PolygonRegion(validating: touching) == nil)
    }

    /// A non-consecutive repeat survives collapsing on both SDKs (both collapse consecutive repeats
    /// only), so the drop has to come from the intersection test: the two edges leaving the repeated
    /// vertex are non-adjacent and touch.
    @Test
    func init_givenNonConsecutiveRepeatedVertex_expectRejected() {
        let repeated = [
            LocationData(latitude: 0.000, longitude: 0.000),
            LocationData(latitude: 0.002, longitude: 0.000),
            LocationData(latitude: 0.000, longitude: 0.000),
            LocationData(latitude: 0.000, longitude: 0.002)
        ]
        #expect(PolygonRegion(validating: repeated) == nil)
    }

    /// Concave rings are the point of polygons and must survive the new rejection.
    @Test
    func init_givenConcaveRing_expectAccepted() {
        let lShape = [
            LocationData(latitude: 0.000, longitude: 0.000),
            LocationData(latitude: 0.000, longitude: 0.003),
            LocationData(latitude: 0.001, longitude: 0.003),
            LocationData(latitude: 0.001, longitude: 0.001),
            LocationData(latitude: 0.003, longitude: 0.001),
            LocationData(latitude: 0.003, longitude: 0.000)
        ]
        #expect(PolygonRegion(validating: lShape) != nil)
    }

    /// A repeated position is a zero-length edge: geometrically nothing, but it inflates the count
    /// the vertex cap is compared against, and the server states that cap in UNIQUE vertices. So a
    /// ring the server considers valid must not be dropped for carrying a duplicate.
    @Test
    func init_givenConsecutiveDuplicateVertices_expectCollapsedAndGeometryUnchanged() throws {
        let fixture = try #require(polygonGeometryFixtures.first)
        var withDuplicates: [LocationData] = []
        for vertex in fixture.vertices {
            withDuplicates.append(vertex)
            withDuplicates.append(vertex)
        }
        let plain = try #require(PolygonRegion(vertices: fixture.vertices))
        let collapsed = try #require(PolygonRegion(vertices: withDuplicates))

        #expect(collapsed.vertices == plain.vertices)
        for sample in fixture.samples {
            #expect(collapsed.contains(sample.point) == sample.inside, "\(sample.note)")
            #expect(
                abs(collapsed.signedEdgeDistance(to: sample.point) - plain.signedEdgeDistance(to: sample.point)) < 0.001,
                "\(sample.note)"
            )
        }
    }

    /// A triangle written with every point doubled is still a triangle, not a six-sided ring.
    @Test
    func init_givenOnlyDuplicatesLeavingTwoDistinct_expectNil() {
        let a = LocationData(latitude: 0, longitude: 0)
        let b = LocationData(latitude: 0.001, longitude: 0)
        #expect(PolygonRegion(vertices: [a, a, b, b, a]) == nil)
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

    /// Pins the half-open ray cast documented on the type: boundary points are NOT symmetric.
    /// Nothing depends on the asymmetry (delivery never acts within the accuracy-gate floor), but
    /// it is the rule the cross-SDK fixtures encode, so a silent flip would diverge from Android.
    @Test
    func contains_givenPointsExactlyOnBoundary_expectHalfOpenRule() throws {
        let square = try #require(polygonGeometryFixtures.first { $0.name == "square400" })
        let region = try #require(PolygonRegion(vertices: square.vertices))
        let minLat = square.vertices.map(\.latitude).min()!
        let maxLat = square.vertices.map(\.latitude).max()!
        let minLon = square.vertices.map(\.longitude).min()!
        let maxLon = square.vertices.map(\.longitude).max()!
        let midLat = (minLat + maxLat) / 2
        let midLon = (minLon + maxLon) / 2

        #expect(region.contains(LocationData(latitude: midLat, longitude: minLon))) // west edge
        #expect(region.contains(LocationData(latitude: minLat, longitude: midLon))) // south edge
        #expect(region.contains(LocationData(latitude: minLat, longitude: minLon))) // SW vertex
        #expect(!region.contains(LocationData(latitude: midLat, longitude: maxLon))) // east edge
        #expect(!region.contains(LocationData(latitude: maxLat, longitude: midLon))) // north edge
        #expect(!region.contains(LocationData(latitude: maxLat, longitude: maxLon))) // NE vertex
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
