import CioInternalCommon
import Foundation

/// What the fence catalog records, resolved per shape so a polygon is placeable.
extension GeofenceApiRegion {
    var catalogShape: String { carriesPolygonFields ? "polygon" : "circle" }

    /// The monitored circle: a circle's own centre, a polygon's enclosing circle.
    var catalogCenter: LocationData? {
        if let latitude, let longitude { return LocationData(latitude: latitude, longitude: longitude) }
        return enclosingCircle.map { LocationData(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var catalogRadius: Double? { radius ?? enclosingCircle?.baseRadiusM }

    /// Outer ring as `lat_lon` pairs — the SDK's order, not GeoJSON's reversed one — and the
    /// CANONICAL ring: consecutive duplicates collapsed and the closing vertex dropped, which is
    /// what membership is computed against and what Android's `nv` counts. Counting the wire ring
    /// instead would report one extra vertex for every closed GeoJSON ring, and a consumer applying
    /// the "fewer pairs than `nv` means truncated" rule would then refuse every correct polygon
    /// from one platform.
    ///
    /// Placement and eyeballing only, never a membership input: the field truncates, and a partial
    /// ring is still a valid-looking polygon. `nv` is the authoritative vertex count.
    ///
    /// Must stay in `GeofenceLog.composedKeys`. `_` is not a style choice — `list` sanitizes every
    /// element before joining, so it is the only intra-pair character that survives the pipeline.
    var catalogRing: [String]? {
        guard let ring = geometry?.coordinates.first, !ring.isEmpty else { return nil }
        // Rendered before `usableRegion` drops invalid coordinates, so a malformed payload reaches
        // this. Every position is kept, bad ones as `bad`: `%.5f` turns 1e300 into 309 digits, and
        // dropping them instead would leave `nv` counting vertices the ring does not show.
        return Self.canonicalised(ring).map { position in
            guard position.count >= 2 else { return "bad_bad" }
            return "\(Self.catalogCoordinate(position[1], max: 90))_\(Self.catalogCoordinate(position[0], max: 180))"
        }
    }

    /// The same two steps `PolygonRegion.init(vertices:)` applies — collapse consecutive
    /// duplicates, drop a closing vertex — but deliberately without its validity rejection: a ring
    /// the SDK will not monitor is exactly the one worth recording.
    ///
    /// Compares the positions rather than the rendered pairs, so two different unreadable
    /// positions stay two. Exact equality where `PolygonRegion` allows longitude wrap, so a ring
    /// closing on +180/-180 counts one higher here; GeoJSON requires the closing position to
    /// repeat the first exactly, and such a fence records a `bad` pair anyway.
    private static func canonicalised(_ ring: [[Double]]) -> [[Double]] {
        var open: [[Double]] = []
        open.reserveCapacity(ring.count)
        for position in ring where open.last != position {
            open.append(position)
        }
        if open.count > 1, open.first == open.last { open.removeLast() }
        return open
    }

    private static func catalogCoordinate(_ value: Double, max: Double) -> String {
        guard value.isFinite, abs(value) <= max else { return "bad" }
        return String(format: "%.5f", value)
    }
}
