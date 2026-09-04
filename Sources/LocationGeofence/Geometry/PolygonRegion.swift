import CioInternalCommon
import Foundation

/// Planar geometry for a polygon geofence, evaluated on a local equirectangular projection
/// around the polygon's vertex centroid.
///
/// Projection: `x = R·Δlon·cos(lat₀)`, `y = R·Δlat` (radians, R = 6371000 m). Android implements
/// the same contract independently rather than sharing this code; the two agree to ~0.0005 m on
/// the shared fixtures (≤1 km) and diverge further out — up to ~1.2 m at lat 31°, ~3.5 m at 60°.
///
/// The ray cast is half-open, so the boundary is not symmetric: a point on the west or south edge
/// (and the south-west vertex) reads as INSIDE, one on the east or north edge as outside. Delivery
/// never acts within the accuracy-gate floor, so the asymmetry is unobservable in practice.
struct PolygonRegion {
    private struct Point {
        let x: Double
        let y: Double
    }

    let vertices: [LocationData]
    private let projected: [Point]
    private let referenceLatitudeRadians: Double
    private let referenceLongitudeRadians: Double
    private let cosReferenceLatitude: Double

    /// IUGG mean Earth radius, the `R` of the projection above. CoreLocation exposes no equivalent
    /// constant — it offers geodesic distances (`CLLocation.distance`) but no way to project, which
    /// point-in-polygon needs — and the value is part of the projection contract shared with
    /// Android, so changing it would desynchronize the cross-SDK fixtures.
    private static let earthRadiusMeters = 6371000.0
    private static let degreesToRadians = Double.pi / 180

    /// Fails on fewer than 3 distinct vertices. A closed ring (last vertex repeating the
    /// first) is accepted and unclosed — servers commonly send GeoJSON-style closed rings.
    ///
    /// Consecutively repeated positions are collapsed, so `vertices` is the canonical unique ring.
    /// A repeat describes a zero-length edge, which contributes nothing to either containment or
    /// edge distance; collapsing it keeps the count comparable to the server's own cap, which is
    /// stated in unique vertices.
    init?(vertices: [LocationData]) {
        var open: [LocationData] = []
        open.reserveCapacity(vertices.count)
        for vertex in vertices where vertex != open.last {
            open.append(vertex)
        }
        if let first = open.first, let last = open.last, open.count > 1, first == last {
            open.removeLast()
        }
        guard open.count >= 3 else { return nil }
        self.vertices = open

        let lat0 = open.map(\.latitude).reduce(0, +) / Double(open.count)
        let lon0 = open.map(\.longitude).reduce(0, +) / Double(open.count)
        let latitudeRadians = lat0 * Self.degreesToRadians
        let longitudeRadians = lon0 * Self.degreesToRadians
        let cosLatitude = cos(latitudeRadians)
        self.referenceLatitudeRadians = latitudeRadians
        self.referenceLongitudeRadians = longitudeRadians
        self.cosReferenceLatitude = cosLatitude
        self.projected = open.map {
            Self.project(
                $0,
                referenceLatitudeRadians: latitudeRadians,
                referenceLongitudeRadians: longitudeRadians,
                cosReferenceLatitude: cosLatitude
            )
        }
    }

    func contains(_ location: LocationData) -> Bool {
        isInside(project(location))
    }

    /// Meters to the nearest polygon edge: **positive inside, negative outside**.
    ///
    /// The circle path does not mirror this: `Geofence.edgeDistanceTo` is
    /// `max(0, distanceTo - radius)`, clamped to 0 inside and never negative. Ranking a polygon
    /// alongside circles therefore needs `max(0, -signedEdgeDistance)`, not a plain negation.
    /// The sign convention here is fixed by the cross-SDK geometry fixtures and cannot be flipped
    /// unilaterally.
    func signedEdgeDistance(to location: LocationData) -> Double {
        let p = project(location)
        var minDistance = Double.greatestFiniteMagnitude
        for i in 0 ..< projected.count {
            let a = projected[i]
            let b = projected[(i + 1) % projected.count]
            minDistance = min(minDistance, Self.distanceToSegment(p, a, b))
        }
        return isInside(p) ? minDistance : -minDistance
    }

    private func project(_ location: LocationData) -> Point {
        Self.project(
            location,
            referenceLatitudeRadians: referenceLatitudeRadians,
            referenceLongitudeRadians: referenceLongitudeRadians,
            cosReferenceLatitude: cosReferenceLatitude
        )
    }

    /// `static` so the initializer can project the ring before `self` is fully formed, and so the
    /// formula lives in exactly one place.
    private static func project(
        _ location: LocationData,
        referenceLatitudeRadians: Double,
        referenceLongitudeRadians: Double,
        cosReferenceLatitude: Double
    ) -> Point {
        Point(
            x: earthRadiusMeters * (location.longitude * degreesToRadians - referenceLongitudeRadians) * cosReferenceLatitude,
            y: earthRadiusMeters * (location.latitude * degreesToRadians - referenceLatitudeRadians)
        )
    }

    /// Ray cast with the half-open rule, so a crossing shared by two edges counts once.
    private func isInside(_ p: Point) -> Bool {
        var inside = false
        for i in 0 ..< projected.count {
            let a = projected[i]
            let b = projected[(i + 1) % projected.count]
            if (a.y > p.y) != (b.y > p.y) {
                let xCross = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < xCross {
                    inside.toggle()
                }
            }
        }
        return inside
    }

    private static func distanceToSegment(_ p: Point, _ a: Point, _ b: Point) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return ((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y)).squareRoot()
        }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        let cx = a.x + t * dx
        let cy = a.y + t * dy
        return ((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy)).squareRoot()
    }
}
