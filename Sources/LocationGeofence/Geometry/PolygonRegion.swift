import CioInternalCommon
import CoreLocation
import Foundation

/// Evaluated on an equirectangular projection around the vertex centroid. Android projects
/// differently, so the two SDKs can differ slightly on large rings.
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

    /// IUGG mean Earth radius; Android uses the same value.
    private static let earthRadiusMeters = 6371000.0
    private static let degreesToRadians = Double.pi / 180

    /// O(n), as it runs per evaluation; the O(n²) checks live in `init(validating:)`. The range
    /// check matters: past ~3.2e18 subtracting 360 no longer changes a `Double`, so the unwrap hangs.
    init?(vertices: [LocationData]) {
        var open: [LocationData] = []
        open.reserveCapacity(vertices.count)
        for vertex in vertices {
            // Validity first: `samePosition` unwraps (360 lands on 0), so an invalid position could
            // be collapsed away instead of rejecting the ring.
            guard CLLocationCoordinate2DIsValid(
                CLLocationCoordinate2D(latitude: vertex.latitude, longitude: vertex.longitude)
            ) else { return nil }
            if let last = open.last, Self.samePosition(vertex, last) { continue }
            open.append(vertex)
        }
        if let first = open.first, let last = open.last, open.count > 1, Self.samePosition(first, last) {
            open.removeLast()
        }
        guard open.count >= 3 else { return nil }

        // Unwrap before averaging, or an antimeridian ring averages to Greenwich.
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

    /// +180 and -180 are one meridian; compared raw, such a closing vertex reads as a
    /// self-intersection. Only sound for in-range positions: not a general wrapping equality.
    private static func samePosition(_ a: LocationData, _ b: LocationData) -> Bool {
        a.latitude == b.latitude && unwrapLongitude(a.longitude, near: b.longitude) == b.longitude
    }

    /// The only writer of `Geofence.vertices`. O(n²), so it runs once per sync at the API boundary.
    init?(validating vertices: [LocationData]) {
        self.init(vertices: vertices)
        guard Self.enclosesArea(projected), !Self.selfIntersects(projected) else { return nil }
    }

    /// Below this a ring can never contain anything, yet would hold an OS monitoring slot.
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

    /// Touching counts as crossing, matching Android: even-odd ray casting reads both lobes of a
    /// bow-tie as inside.
    private static func selfIntersects(_ ring: [Point]) -> Bool {
        let n = ring.count
        guard n >= 4 else { return false }
        for i in 0 ..< n {
            let a1 = ring[i], a2 = ring[(i + 1) % n]
            // i+2 skips the neighbour; the i == 0 guard skips the closing edge, which shares a vertex.
            for j in stride(from: i + 2, to: n, by: 1) where !(i == 0 && j == n - 1) {
                let b1 = ring[j], b2 = ring[(j + 1) % n]
                if Self.segmentsMeet(a1, a2, b1, b2) { return true }
            }
        }
        return false
    }

    /// Exact zero with room for float error (m²), not a tolerance.
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

    /// Bounding-box test; valid only once the three are known to be collinear.
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

    /// Meters to the nearest edge: **positive inside, negative outside**. Shared with Android and
    /// logged as `edge`, so don't flip it.
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

    /// Venue depth in metres, `2 × area / perimeter`. Errs HIGH against the inradius, the safe
    /// direction: it widens the accuracy accepted.
    var scale: Double {
        var twiceArea = 0.0
        var perimeter = 0.0
        for i in 0 ..< projected.count {
            let a = projected[i]
            let b = projected[(i + 1) % projected.count]
            twiceArea += a.x * b.y - b.x * a.y
            perimeter += hypot(b.x - a.x, b.y - a.y)
        }
        guard perimeter > 0 else { return 0 }
        return abs(twiceArea) / perimeter
    }

    private static func unwrapLongitudes(_ ring: [LocationData]) -> [LocationData] {
        guard let reference = ring.first?.longitude else { return ring }
        return ring.map {
            LocationData(latitude: $0.latitude, longitude: unwrapLongitude($0.longitude, near: reference))
        }
    }

    /// The guard keeps the loop bounded here, not only in callers: far enough out of range,
    /// subtracting 360 stops changing the value.
    private static func unwrapLongitude(_ longitude: Double, near reference: Double) -> Double {
        guard longitude.isFinite, abs(longitude) <= 360, reference.isFinite else { return longitude }
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

    /// Half-open rule, so a crossing shared by two edges counts once.
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
