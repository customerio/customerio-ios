@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

/// A region we can't read as described is dropped entirely, never degraded to its circle fields.
@Suite("GeofencePolygonDecode")
struct GeofencePolygonDecodeTests {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private func decode(_ json: String) throws -> GeofenceApiResponse {
        try decoder.decode(GeofenceApiResponse.self, from: Data(json.utf8))
    }

    private static let centre = (latitude: 31.36896, longitude: 74.169508)

    /// 400 m square around the centre, closed, longitude-first.
    private static let squareRing = """
    [[
      [74.1674038, 31.3671634],
      [74.1716122, 31.3671634],
      [74.1716122, 31.3707566],
      [74.1674038, 31.3707566],
      [74.1674038, 31.3671634]
    ]]
    """

    private func circleJson(id: Int = 1, radius: Double = 300, shape: String? = "circle") -> String {
        let shapeField = shape.map { "\"shape\": \"\($0)\", " } ?? ""
        return """
        {"id": \(id), \(shapeField)"latitude": \(Self.centre.latitude),
         "longitude": \(Self.centre.longitude), "radius": \(radius)}
        """
    }

    private func polygonJson(
        id: Int = 1,
        radius: Double = 300,
        type: String = "Polygon",
        ring: String? = squareRing,
        enclosingCircle: Bool = true
    ) -> String {
        let geometry = ring.map { "\"geometry\": {\"type\": \"\(type)\", \"coordinates\": \($0)}" }
        let circle = enclosingCircle
            ? """
            "enclosing_circle": {"latitude": \(Self.centre.latitude),
             "longitude": \(Self.centre.longitude), "base_radius_m": \(radius)}
            """
            : nil
        let fields = ["\"id\": \(id)", "\"shape\": \"polygon\""] + [geometry, circle].compactMap { $0 }
        return "{\(fields.joined(separator: ","))}"
    }

    private func responseJson(_ regions: [String]) -> String {
        "{\"geofences\":[\(regions.joined(separator: ","))]}"
    }

    /// A ring of `count` distinct positions ~90 m from the centre, well inside the enclosing circle.
    private static func ringInsideCircle(count: Int, repeatingFirstPosition: Bool = false) -> String {
        var positions = (0 ..< count).map { i -> String in
            let angle = 2 * Double.pi * Double(i) / Double(count)
            return "[\(centre.longitude + 0.0009 * sin(angle)), \(centre.latitude + 0.0008 * cos(angle))]"
        }
        if repeatingFirstPosition, let first = positions.first { positions.insert(first, at: 1) }
        return "[[\(positions.joined(separator: ","))]]"
    }

    // MARK: - Circles

    @Test
    func toDomain_givenShapeCircle_expectCircleGeofence() throws {
        let regions = try decode(responseJson([circleJson()])).toDomainRegions()
        #expect(regions.count == 1)
        #expect(regions[0].vertices == nil)
        #expect(regions[0].polygonRegion == nil)
    }

    @Test
    func toDomain_givenNoShapeKey_expectCircleGeofence() throws {
        let regions = try decode(responseJson([circleJson(shape: nil)])).toDomainRegions()
        #expect(regions.count == 1)
        #expect(regions[0].vertices == nil)
    }

    @Test
    func toDomain_givenUnknownShape_expectRegionDroppedNotCircled() throws {
        let response = try decode(responseJson([circleJson(shape: "corridor"), circleJson(id: 2)]))
        var invalidIds: [String] = []
        let regions = response.toDomainRegions(onInvalidRegion: { id, _ in invalidIds.append(id) })
        #expect(regions.map(\.id) == ["2"])
        #expect(invalidIds == ["1"])
    }

    // MARK: - Valid polygons

    @Test
    func toDomain_givenValidSquare_expectPolygonGeofence() throws {
        let regions = try decode(responseJson([polygonJson()])).toDomainRegions()
        #expect(regions.count == 1)
        #expect(regions[0].vertices?.count == 4)
        #expect(regions[0].radius == 300)
        let polygon = try #require(regions[0].polygonRegion)
        #expect(polygon.contains(LocationData(latitude: Self.centre.latitude, longitude: Self.centre.longitude)))
        #expect(!polygon.contains(LocationData(latitude: 31.38, longitude: Self.centre.longitude)))
    }

    /// Asserts the decoded corner, not the count: swapped axes would still yield 4 vertices.
    @Test
    func toDomain_givenGeoJsonOrdering_expectLongitudeFirst() throws {
        let regions = try decode(responseJson([polygonJson()])).toDomainRegions()
        let first = try #require(regions[0].vertices?.first)
        #expect(abs(first.latitude - 31.3671634) < 1e-9)
        #expect(abs(first.longitude - 74.1674038) < 1e-9)
    }

    @Test
    func toDomain_givenClosedRing_expectUnclosedCanonicalVertices() throws {
        let regions = try decode(responseJson([polygonJson()])).toDomainRegions()
        #expect(regions[0].vertices?.count == 4)
    }

    @Test
    func toDomain_givenPositionsWithElevation_expectAccepted() throws {
        let ring = """
        [[
          [74.1674038, 31.3671634, 210.0],
          [74.1716122, 31.3671634, 210.0],
          [74.1716122, 31.3707566, 210.0],
          [74.1674038, 31.3707566, 210.0]
        ]]
        """
        let regions = try decode(responseJson([polygonJson(ring: ring)])).toDomainRegions()
        #expect(regions.count == 1)
        #expect(regions[0].vertices?.count == 4)
    }

    @Test
    func toDomain_givenLargeRing_expectAccepted() throws {
        let regions = try decode(responseJson([polygonJson(ring: Self.ringInsideCircle(count: 500))])).toDomainRegions()
        #expect(regions.count == 1)
    }

    // MARK: - "No illusions": unusable polygons drop the region

    @Test
    func toDomain_givenSelfIntersectingRing_expectRegionDropped() throws {
        let bowtie = """
        [[[74.1674038, 31.3671634], [74.1716122, 31.3707566],
          [74.1716122, 31.3671634], [74.1674038, 31.3707566]]]
        """
        let response = try decode(responseJson([polygonJson(ring: bowtie)]))
        #expect(response.toDomainRegions().isEmpty)
    }

    @Test
    func toDomain_givenZeroAreaRing_expectRegionDropped() throws {
        let line = """
        [[[74.1674038, 31.3671634], [74.1674038, 31.3681634], [74.1674038, 31.3691634]]]
        """
        let response = try decode(responseJson([polygonJson(ring: line)]))
        #expect(response.toDomainRegions().isEmpty)
    }

    @Test
    func toDomain_givenPolygonFieldsWithoutShape_expectRegionDropped() throws {
        let inconsistent = """
        {"id": 1, "latitude": \(Self.centre.latitude), "longitude": \(Self.centre.longitude),
         "radius": 300,
         "geometry": {"type": "Polygon", "coordinates": \(Self.squareRing)},
         "enclosing_circle": {"latitude": \(Self.centre.latitude),
          "longitude": \(Self.centre.longitude), "base_radius_m": 300}}
        """
        var reasons: [String: GeofenceRegionDropReason] = [:]
        let regions = try decode(responseJson([inconsistent])).toDomainRegions(onInvalidRegion: { reasons[$0] = $1 })
        #expect(regions.isEmpty)
        #expect(reasons["1"] == .undescribedShape)
    }

    /// As its own string a blank shape would report `unknownShape`, the one reason the all-dropped
    /// guard exempts, so a payload of these would clear the whole fence set.
    @Test(arguments: ["\"\"", "\" \"", "\"  circle \""])
    func toDomain_givenBlankOrPaddedShape_expectRoutedAsIfAbsent(shapeJson: String) throws {
        let withPolygonFields = """
        {"id": 1, "shape": \(shapeJson),
         "latitude": \(Self.centre.latitude), "longitude": \(Self.centre.longitude), "radius": 300,
         "geometry": {"type": "Polygon", "coordinates": \(Self.squareRing)}}
        """
        var reasons: [String: GeofenceRegionDropReason] = [:]
        let regions = try decode(responseJson([withPolygonFields]))
            .toDomainRegions(onInvalidRegion: { reasons[$0] = $1 })
        // Either it resolves (padded "circle") or it drops under a reason that COUNTS as unreadable.
        #expect(reasons["1"] != .unknownShape, "blank/padded shape must not take the exempt branch")
        if regions.isEmpty { #expect(reasons["1"] == .undescribedShape) }
    }

    /// These fields decode with `try?`; keyed on the decoded value, a malformed one would read as a
    /// v1 circle.
    @Test
    func toDomain_givenUndecodablePolygonFieldsWithoutShape_expectRegionDropped() throws {
        let malformed = """
        {"id": 1, "latitude": \(Self.centre.latitude), "longitude": \(Self.centre.longitude),
         "radius": 300, "geometry": "not-an-object"}
        """
        var reasons: [String: GeofenceRegionDropReason] = [:]
        let regions = try decode(responseJson([malformed])).toDomainRegions(onInvalidRegion: { reasons[$0] = $1 })
        #expect(regions.isEmpty)
        #expect(reasons["1"] == .undescribedShape)
    }

    @Test
    func toDomain_givenNullPolygonFieldsWithoutShape_expectCircleAccepted() throws {
        let nulled = """
        {"id": 1, "latitude": \(Self.centre.latitude), "longitude": \(Self.centre.longitude),
         "radius": 300, "geometry": null, "enclosing_circle": null}
        """
        let regions = try decode(responseJson([nulled])).toDomainRegions()
        #expect(regions.count == 1)
        #expect(regions.first?.vertices == nil)
    }

    @Test
    func toDomain_givenMultiPolygonType_expectRegionDropped() throws {
        let response = try decode(responseJson([polygonJson(type: "MultiPolygon")]))
        #expect(response.toDomainRegions().isEmpty)
    }

    @Test
    func toDomain_givenMultipleRings_expectRegionDropped() throws {
        let withHole = """
        [[
          [74.1674038, 31.3671634], [74.1716122, 31.3671634],
          [74.1716122, 31.3707566], [74.1674038, 31.3707566]
        ],[
          [74.1690000, 31.3685000], [74.1700000, 31.3685000],
          [74.1700000, 31.3695000], [74.1690000, 31.3695000]
        ]]
        """
        let response = try decode(responseJson([polygonJson(ring: withHole)]))
        #expect(response.toDomainRegions().isEmpty)
    }

    @Test
    func toDomain_givenMissingGeometry_expectRegionDropped() throws {
        let response = try decode(responseJson([polygonJson(ring: nil)]))
        #expect(response.toDomainRegions().isEmpty)
    }

    @Test
    func toDomain_givenMissingEnclosingCircle_expectRegionDropped() throws {
        let response = try decode(responseJson([polygonJson(enclosingCircle: false)]))
        #expect(response.toDomainRegions().isEmpty)
    }

    @Test
    func toDomain_givenWrongTypedGeometry_expectRegionDroppedNotCircled() throws {
        let broken = """
        {"id": 1, "shape": "polygon", "geometry": "not-a-geometry",
         "enclosing_circle": {"latitude": \(Self.centre.latitude),
          "longitude": \(Self.centre.longitude), "base_radius_m": 300}}
        """
        let response = try decode(responseJson([broken, circleJson(id: 2)]))
        var invalidIds: [String] = []
        let regions = response.toDomainRegions(onInvalidRegion: { id, _ in invalidIds.append(id) })
        #expect(regions.map(\.id) == ["2"])
        #expect(invalidIds == ["1"])
    }

    @Test
    func toDomain_givenPositionMissingCoordinate_expectRegionDropped() throws {
        let ring = "[[[74.1674038, 31.3671634], [74.1716122], [74.1716122, 31.3707566]]]"
        let response = try decode(responseJson([polygonJson(ring: ring)]))
        #expect(response.toDomainRegions().isEmpty)
    }

    @Test
    func toDomain_givenFewerThanThreeDistinctVertices_expectRegionDropped() throws {
        let ring = """
        [[[74.1674038, 31.3671634], [74.1716122, 31.3707566], [74.1674038, 31.3671634]]]
        """
        let response = try decode(responseJson([polygonJson(ring: ring)]))
        #expect(response.toDomainRegions().isEmpty)
    }

    @Test
    func toDomain_givenRepeatedPositions_expectCollapsedToUnique() throws {
        let unique = 500
        let response = try decode(responseJson([
            polygonJson(ring: Self.ringInsideCircle(count: unique, repeatingFirstPosition: true))
        ]))

        let regions = response.toDomainRegions()
        #expect(regions.count == 1)
        #expect(regions.first?.vertices?.count == unique)
    }

    // MARK: - Cache round-trip

    @Test
    func geofenceCodable_givenPolygon_expectVerticesSurviveRoundTrip() throws {
        let original = Geofence(
            id: "7",
            latitude: Self.centre.latitude,
            longitude: Self.centre.longitude,
            radius: 283,
            name: "poly",
            transitionTypes: [.enter, .exit],
            lastUpdated: Date(timeIntervalSince1970: 1000),
            vertices: [
                LocationData(latitude: 31.3671634, longitude: 74.1674038),
                LocationData(latitude: 31.3671634, longitude: 74.1716122),
                LocationData(latitude: 31.3707566, longitude: 74.1716122)
            ]
        )
        let decoded = try JSONDecoder().decode(Geofence.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.polygonRegion != nil)
    }

    @Test
    func geofenceDecode_givenLegacyCacheWithoutVertices_expectCircleGeofence() throws {
        let legacy = """
        {"id":"7","latitude":31.36896,"longitude":74.169508,"radius":283,
         "transitionTypes":["enter","exit"],"lastUpdated":0}
        """
        let decoded = try JSONDecoder().decode(Geofence.self, from: Data(legacy.utf8))
        #expect(decoded.vertices == nil)
        #expect(decoded.polygonRegion == nil)
    }
}
