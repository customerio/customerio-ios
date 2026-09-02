import CioInternalCommon
import CoreLocation
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

    /// Canonicalises and projects a ring. Fails on fewer than 3 distinct vertices, or on a position
    /// outside the valid coordinate range. A closed ring (last vertex repeating the first) is
    /// accepted and unclosed — servers commonly send GeoJSON-style closed rings.
    ///
    /// Consecutively repeated positions are collapsed, so `vertices` is the canonical unique ring.
    /// A repeat describes a zero-length edge, which contributes nothing to either containment or
    /// edge distance; collapsing it keeps the count comparable to the server's own cap, which is
    /// stated in unique vertices.
    ///
    /// The range check is a construction precondition rather than a second opinion on server
    /// policy: it is what bounds the work this initializer does. Everything downstream walks
    /// longitudes in 360° steps, and past roughly 3.2e18 subtracting 360 no longer changes a
    /// `Double` at all — a single wild value in a decodable payload would hang the process, on
    /// every rebuild from cache rather than only on the sync that received it.
    ///
    /// O(n): the degeneracy checks live in `init(validating:)`, not here, because callers rebuild a
    /// region per evaluation.
    init?(vertices: [LocationData]) {
        var open: [LocationData] = []
        open.reserveCapacity(vertices.count)
        for vertex in vertices where vertex != open.last {
            guard CLLocationCoordinate2DIsValid(
                CLLocationCoordinate2D(latitude: vertex.latitude, longitude: vertex.longitude)
            ) else { return nil }
            open.append(vertex)
        }
        if let first = open.first, let last = open.last, open.count > 1, first == last {
            open.removeLast()
        }
        guard open.count >= 3 else { return nil }

        // Unwrap before averaging: a ring spanning the antimeridian holds values near both +180
        // and -180, whose mean is Greenwich, and the fence then projects a hemisphere wide.
        let unwrapped = Self.unwrapLongitudes(open)
        let lat0 = unwrapped.map(\.latitude).reduce(0, +) / Double(unwrapped.count)
        let lon0 = unwrapped.map(\.longitude).reduce(0, +) / Double(unwrapped.count)
        let latitudeRadians = lat0 * Self.degreesToRadians
        let longitudeRadians = lon0 * Self.degreesToRadians
        let cosLatitude = cos(latitudeRadians)
        let planar = unwrapped.map {
            Self.project(
                $0,
                referenceLatitudeRadians: latitudeRadians,
                referenceLongitudeRadians: longitudeRadians,
                cosReferenceLatitude: cosLatitude
            )
        }
        self.vertices = open
        self.referenceLatitudeRadians = latitudeRadians
        self.referenceLongitudeRadians = longitudeRadians
        self.cosReferenceLatitude = cosLatitude
        self.projected = planar
    }

    /// Decode-time construction: additionally rejects rings that cannot be monitored sensibly —
    /// zero area, or self-intersecting. Separate from `init(vertices:)` because that one runs on
    /// hot paths (once per polygon per wake and per evaluation) while these checks are O(n²), so
    /// they belong at the API boundary where they run once per sync.
    init?(validating vertices: [LocationData]) {
        self.init(vertices: vertices)
        guard Self.enclosesArea(projected), !Self.selfIntersects(projected) else { return nil }
    }

    /// A ring below this is a line or a point. It can never contain anything, so it would hold an OS
    /// monitoring slot and pull the shared wake circle toward its floor while never firing.
    private static let minimumAreaSquareMeters = 1.0

    private static func enclosesArea(_ ring: [Point]) -> Bool {
        var twiceArea = 0.0
        for i in 0 ..< ring.count {
            let a = ring[i]
            let b = ring[(i + 1) % ring.count]
            twiceArea += a.x * b.y - b.x * a.y
        }
        return abs(twiceArea) / 2 >= minimumAreaSquareMeters
    }

    /// True when two non-adjacent edges cross OR touch. Even-odd ray casting reports both lobes of a
    /// bow-tie as inside, so such a ring delivers enters for ground the polygon never covered, and a
    /// pair of lobes joined at a single point is the same shape with the crossing degenerated to a
    /// vertex. Touching counts, matching Android — a ring repeating a vertex non-consecutively
    /// (a…b…a…c) survives canonicalisation on both SDKs and must then be dropped on both.
    private static func selfIntersects(_ ring: [Point]) -> Bool {
        let n = ring.count
        guard n >= 4 else { return false }
        for i in 0 ..< n {
            let a1 = ring[i], a2 = ring[(i + 1) % n]
            // j starts at i+2 to skip the shared-vertex neighbour; the i == 0 guard skips the
            // closing edge, which shares a vertex with the first.
            for j in stride(from: i + 2, to: n, by: 1) where !(i == 0 && j == n - 1) {
                let b1 = ring[j], b2 = ring[(j + 1) % n]
                if Self.segmentsMeet(a1, a2, b1, b2) { return true }
            }
        }
        return false
    }

    /// Orientations below this are treated as collinear. Projected coordinates are metres, so the
    /// cross product is m²: this is exact-zero with room for float error, not a tolerance.
    private static let orientationEpsilon = 1e-9

    private static func segmentsMeet(_ p1: Point, _ p2: Point, _ p3: Point, _ p4: Point) -> Bool {
        let o1 = orientation(p1, p2, p3)
        let o2 = orientation(p1, p2, p4)
        let o3 = orientation(p3, p4, p1)
        let o4 = orientation(p3, p4, p2)
        if o1 * o2 < 0, o3 * o4 < 0 { return true }
        if abs(o1) <= orientationEpsilon, within(p1, p3, p2) { return true }
        if abs(o2) <= orientationEpsilon, within(p1, p4, p2) { return true }
        if abs(o3) <= orientationEpsilon, within(p3, p1, p4) { return true }
        if abs(o4) <= orientationEpsilon, within(p3, p2, p4) { return true }
        return false
    }

    /// Whether `point` lies in the bounding box of the `a`–`b` segment, used only once the three are
    /// known to be collinear.
    private static func within(_ a: Point, _ point: Point, _ b: Point) -> Bool {
        point.x >= min(a.x, b.x) && point.x <= max(a.x, b.x)
            && point.y >= min(a.y, b.y) && point.y <= max(a.y, b.y)
    }

    private static func orientation(_ a: Point, _ b: Point, _ c: Point) -> Double {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
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

    /// Shifts longitudes into the ±180° window around the first vertex so a ring crossing the
    /// antimeridian is continuous. Part of the projection contract shared with Android.
    private static func unwrapLongitudes(_ ring: [LocationData]) -> [LocationData] {
        guard let reference = ring.first?.longitude else { return ring }
        return ring.map {
            LocationData(latitude: $0.latitude, longitude: unwrapLongitude($0.longitude, near: reference))
        }
    }

    private static func unwrapLongitude(_ longitude: Double, near reference: Double) -> Double {
        var value = longitude
        while value - reference > 180 {
            value -= 360
        }
        while value - reference < -180 {
            value += 360
        }
        return value
    }

    private func project(_ location: LocationData) -> Point {
        // Onto the ring's line: a fix at -179.99 belongs beside a ring unwrapped to +180.01.
        let aligned = LocationData(
            latitude: location.latitude,
            longitude: Self.unwrapLongitude(location.longitude, near: referenceLongitudeRadians * 180 / .pi)
        )
        return Self.project(
            aligned,
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
