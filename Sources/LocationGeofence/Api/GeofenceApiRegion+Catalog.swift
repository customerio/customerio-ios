import CioInternalCommon
import Foundation

/// The shape the catalog reports, one branch per outcome of the mapper's own `shape` switch.
/// A closed set, so `sh` stays groupable even when the server sends something unrecognized —
/// the token it actually sent is already on `registration.rejected`.
enum GeofenceCatalogShape: String, CaseIterable {
    case circle
    case polygon
    /// Polygon fields with no discriminator. Dropped by the mapper as `undescribedShape`.
    case undescribed
    /// A shape the server named that this version cannot monitor.
    case unknown
}

/// What the fence catalog records, resolved per shape so a polygon is placeable.
extension GeofenceApiRegion {
    /// Normalized exactly as `toDomain` normalizes it (trimmed, lowercased, blank treated as
    /// absent), so `sh` names the shape the SDK actually monitored.
    private var normalizedShape: String? {
        let named = shape?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return named?.isEmpty == true ? nil : named
    }

    var catalogShape: GeofenceCatalogShape {
        switch normalizedShape {
        case nil: return carriesPolygonFields ? .undescribed : .circle
        case "circle": return .circle
        case "polygon": return .polygon
        default: return .unknown
        }
    }

    /// The monitored circle. Which fields win follows the shape, not their mere presence: an
    /// explicit `shape: "circle"` carrying stray geometry is monitored by its flat fields, and a
    /// `shape: "polygon"` carrying flat fields is monitored by its enclosing circle. The other
    /// source stays as a fallback so a half-populated payload is still placeable.
    var catalogCenter: LocationData? {
        let flat = latitude.flatMap { lat in longitude.map { LocationData(latitude: lat, longitude: $0) } }
        let enclosing = enclosingCircle.map { LocationData(latitude: $0.latitude, longitude: $0.longitude) }
        return prefersEnclosingCircle ? enclosing ?? flat : flat ?? enclosing
    }

    var catalogRadius: Double? {
        prefersEnclosingCircle ? enclosingCircle?.baseRadiusM ?? radius : radius ?? enclosingCircle?.baseRadiusM
    }

    /// Both shapes the mapper resolves through `resolvedPolygon()`, which reads the enclosing circle.
    private var prefersEnclosingCircle: Bool {
        catalogShape == .polygon || catalogShape == .undescribed
    }

    /// Outer ring as `lat_lon` pairs (the SDK's order, not GeoJSON's) in CANONICAL form:
    /// consecutive duplicates collapsed and the closing vertex dropped, matching what membership
    /// uses and what Android's `nv` counts. The wire ring would count one extra vertex per closed
    /// GeoJSON ring.
    ///
    /// Placement and eyeballing only, never a membership input: the field truncates. `nv` is the
    /// authoritative vertex count.
    ///
    /// `ring` must stay in `GeofenceLog.composedKeys`. The `_` joiner survives `list`, which
    /// sanitizes every element and would rewrite `:` or `,` to `_` anyway.
    var catalogRing: [String]? {
        guard let ring = geometry?.coordinates.first, !ring.isEmpty else { return nil }
        // The geometry kernel's own list when the region resolves, so the catalog can never report
        // a different ring from the one membership is computed against — including at the
        // antimeridian, where the kernel tolerates longitude wrap and the fallback below does not.
        if case .success(let geofence) = toDomain(), let vertices = geofence.vertices {
            return vertices.map { "\(Self.catalogCoordinate($0.latitude, max: 90))_\(Self.catalogCoordinate($0.longitude, max: 180))" }
        }
        // Reached only for a ring the kernel REJECTED, which is the case worth recording and the
        // one it cannot answer. Bad positions are kept as `bad`: `%.5f` turns 1e300 into 309
        // digits, and dropping them would leave `nv` counting vertices the ring does not show.
        return Self.canonicalised(ring).map { position in
            guard position.count >= 2 else { return "bad_bad" }
            return "\(Self.catalogCoordinate(position[1], max: 90))_\(Self.catalogCoordinate(position[0], max: 180))"
        }
    }

    /// The same two steps as `PolygonRegion.init(vertices:)` (collapse consecutive duplicates, drop
    /// a closing vertex) without its validity rejection: a ring the SDK refuses is the one worth
    /// recording.
    ///
    /// Compares positions, not rendered pairs, so two different unreadable positions stay two.
    /// Exact equality, unlike the kernel's wrap-tolerant `samePosition`, so a ring closing at +180
    /// that opened at -180 keeps its closing vertex here. Safe only because an accepted fence uses
    /// the kernel's list above and never reaches this.
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
