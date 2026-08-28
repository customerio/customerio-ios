import CioInternalCommon
import Foundation

/// Planar geometry for a polygon geofence, evaluated on a local equirectangular projection
/// around the polygon's vertex centroid.
///
/// Projection (shared verbatim with the Android SDK; the cross-SDK fixtures assume it):
/// `x = R·Δlon·cos(lat₀)`, `y = R·Δlat` (radians, R = 6371000 m). At fence scale (≤ ~10 km)
/// the projection error is far below GPS accuracy, and both SDKs agree within the fixtures'
/// 0.5 m tolerance.
///
/// A point exactly on the boundary counts as outside (signed distance 0 with a negative sign
/// convention would be ambiguous; delivery decisions never act inside the accuracy-gate floor
/// anyway, so the tie-break is unobservable in practice).
struct PolygonRegion {
    private struct Point {
        let x: Double
        let y: Double
    }

    let vertices: [LocationData]
    private let projected: [Point]
    private let referenceLatitudeRadians: Double
    private let referenceLongitudeRadians: Double

    private static let earthRadius = 6371000.0

    /// Fails on fewer than 3 distinct vertices. A closed ring (last vertex repeating the
    /// first) is accepted and unclosed — servers commonly send GeoJSON-style closed rings.
    init?(vertices: [LocationData]) {
        var open = vertices
        if let first = open.first, let last = open.last, open.count > 1,
           first.latitude == last.latitude, first.longitude == last.longitude {
            open.removeLast()
        }
        guard open.count >= 3 else { return nil }
        self.vertices = open

        let lat0 = open.map(\.latitude).reduce(0, +) / Double(open.count)
        let lon0 = open.map(\.longitude).reduce(0, +) / Double(open.count)
        self.referenceLatitudeRadians = lat0 * .pi / 180
        self.referenceLongitudeRadians = lon0 * .pi / 180
        let cosLat0 = cos(referenceLatitudeRadians)
        self.projected = open.map { v in
            Point(
                x: Self.earthRadius * (v.longitude * .pi / 180 - lon0 * .pi / 180) * cosLat0,
                y: Self.earthRadius * (v.latitude * .pi / 180 - lat0 * .pi / 180)
            )
        }
    }

    func contains(_ location: LocationData) -> Bool {
        isInside(project(location))
    }

    /// Meters to the nearest polygon edge: **positive inside, negative outside**.
    ///
    /// Note this is the OPPOSITE sign to the circle path's edge distance
    /// (`Geofence.edgeDistanceTo`, and `BaselineHealDecision`'s `distanceFromCenter - radius`),
    /// which is negative inside. The convention here is fixed by the cross-SDK geometry fixtures
    /// shared with Android and cannot be flipped unilaterally, so every consumer must convert
    /// rather than assume.
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
        Point(
            x: Self.earthRadius * (location.longitude * .pi / 180 - referenceLongitudeRadians) * cos(referenceLatitudeRadians),
            y: Self.earthRadius * (location.latitude * .pi / 180 - referenceLatitudeRadians)
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
