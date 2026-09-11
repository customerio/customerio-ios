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

    /// Outer ring as `lat_lon` pairs — the SDK's order, not GeoJSON's reversed one.
    ///
    /// Placement and eyeballing only, never a membership input: the field truncates, and a partial
    /// ring is still a valid-looking polygon. `nv` is the authoritative vertex count.
    ///
    /// Must stay in `GeofenceLog.composedKeys`. `_` is not a style choice — `list` sanitizes every
    /// element before joining, so it is the only intra-pair character that survives the pipeline.
    var catalogRing: [String]? {
        guard let ring = geometry?.coordinates.first, !ring.isEmpty else { return nil }
        return ring.compactMap { position in
            guard position.count >= 2 else { return nil }
            // Rendered before `usableRegion` drops invalid coordinates, so a malformed payload can
            // reach this. `%.5f` turns 1e300 into 309 digits, and a ring of those is tens of KB in
            // one line — that the server sent garbage is the useful record, not the garbage.
            return "\(Self.catalogCoordinate(position[1], max: 90))_\(Self.catalogCoordinate(position[0], max: 180))"
        }
    }

    private static func catalogCoordinate(_ value: Double, max: Double) -> String {
        guard value.isFinite, abs(value) <= max else { return "bad" }
        return String(format: "%.5f", value)
    }
}
