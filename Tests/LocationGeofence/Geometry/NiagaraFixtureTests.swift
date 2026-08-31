@testable import CioInternalCommon
@testable import CioLocationGeofence
import CoreLocation
import Foundation
import Testing

@Suite("Niagara fixture")
struct NiagaraFixtureTests {
    /// Closed ring as supplied; the kernel unclosees it.
    private static let ring = [
        (43.2620, -79.0750), (43.2600, -79.0200), (43.2200, -79.0550), (43.1600, -79.0550),
        (43.1500, -79.1200), (43.1800, -79.1800), (43.2300, -79.1500), (43.2620, -79.0750)
    ].map { LocationData(latitude: $0.0, longitude: $0.1) }

    /// Minimum enclosing circle of the ring, radius measured on WGS84 — the farthest vertex sits
    /// 7877.1 m out, which is what the server computes (PostGIS `geography`) and what
    /// `CLLocation.distance` measures here. A spherical model puts the same circle at 7864 m, 13 m
    /// short; `niagaraRing_expectSphericalRadiusRejected` pins that we depend on the WGS84 value.
    private static let covering = (latitude: 43.219062, longitude: -79.099117, radius: 7878.0)

    private static let sphericalCoveringRadius = 7864.0

    @Test
    func niagaraRing_expectAcceptedByKernel() {
        let region = PolygonRegion(vertices: Self.ring)
        #expect(region != nil)
        #expect(region?.vertices.count == 7)
    }

    private static func apiRegion(coveringRadius: Double) -> GeofenceApiRegion {
        GeofenceApiRegion(
            id: "niagara", name: "Niagara-on-the-Lake", shape: "polygon",
            latitude: nil, longitude: nil, radius: nil,
            geometry: GeofenceApiGeometry(
                type: "Polygon",
                // GeoJSON is longitude-first, and the ring stays closed on the wire.
                coordinates: [ring.map { [$0.longitude, $0.latitude] }]
            ),
            enclosingCircle: GeofenceApiEnclosingCircle(
                latitude: covering.latitude, longitude: covering.longitude, baseRadiusM: coveringRadius
            ),
            externalId: nil, transitionTypes: nil, lastUpdated: nil, geosetIds: nil, metadata: nil
        )
    }

    @Test
    func niagaraRing_expectAcceptedByApiValidation() {
        let domain = Self.apiRegion(coveringRadius: Self.covering.radius).toDomain()
        #expect(domain != nil)
        #expect(domain?.vertices?.count == 7)
        #expect(domain?.polygonRegion != nil)
    }

    /// The coverage slack is a flat metre and does not scale, so a circle sized on the wrong earth
    /// model no longer squeaks through: it fails coverage and the region is dropped outright.
    @Test
    func niagaraRing_expectSphericalRadiusRejected() {
        #expect(Self.apiRegion(coveringRadius: Self.sphericalCoveringRadius).toDomain() == nil)
    }

    /// Well inside the town: the verdict must be decisive at any realistic accuracy.
    @Test
    func niagaraRing_expectInteriorPointDecisivelyInside() {
        let region = PolygonRegion(vertices: Self.ring)
        let inland = LocationData(latitude: 43.2050, longitude: -79.1050)
        let signed = region?.signedEdgeDistance(to: inland) ?? 0
        #expect(region?.contains(inland) == true)
        #expect(signed > 0)
        // Decisive past any realistic fix accuracy, so the membership layer can act on it.
        #expect(signed > 65)
    }

    /// The reflex notch: inside the covering circle, outside the town. A convex hull would
    /// wrongly call this inside, which is the whole reason the ring cannot be convexified.
    @Test
    func niagaraRing_expectNotchPointOutside() {
        let region = PolygonRegion(vertices: Self.ring)
        let notch = LocationData(latitude: 43.2350, longitude: -79.0300)
        let coveringCentre = LocationData(latitude: Self.covering.latitude, longitude: Self.covering.longitude)
        let distanceFromCentre = notch.distanceTo(coveringCentre)

        #expect(distanceFromCentre < Self.covering.radius)
        #expect(region?.contains(notch) == false)
        #expect((region?.signedEdgeDistance(to: notch) ?? 0) < 0)
    }
}

private extension LocationData {
    func distanceTo(_ other: LocationData) -> Double {
        let r = 6371000.0
        let lat0 = (latitude + other.latitude) / 2 * .pi / 180
        let dx = r * (longitude - other.longitude) * .pi / 180 * cos(lat0)
        let dy = r * (latitude - other.latitude) * .pi / 180
        return (dx * dx + dy * dy).squareRoot()
    }
}
