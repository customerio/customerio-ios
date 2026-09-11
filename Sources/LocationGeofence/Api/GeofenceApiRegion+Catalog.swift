import CioInternalCommon
import Foundation

/// The shape the catalog reports, one branch per outcome of the mapper's own `shape` switch.
/// A closed set, so `sh` stays groupable even when the server sends something unrecognized —
/// the token it actually sent is already on `registration.rejected`.
enum GeofenceCatalogShape: String {
    case circle
    case polygon
    /// Polygon fields with no discriminator. Dropped by the mapper as `undescribedShape`.
    case undescribed
    /// A shape the server named that this version cannot monitor.
    case unknown
}

/// What the fence catalog records, resolved per shape so a polygon is placeable.
extension GeofenceApiRegion {
    /// Normalized exactly as `toDomain` normalizes it — trimmed, lowercased, blank treated as
    /// absent — because a capture is only interpretable if `sh` names the shape the SDK actually
    /// monitored. `carriesPolygonFields` alone disagreed on mixed payloads.
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

    /// The same two steps `PolygonRegion.init(vertices:)` applies — collapse consecutive
    /// duplicates, drop a closing vertex — but deliberately without its validity rejection: a ring
    /// the SDK will not monitor is exactly the one worth recording.
    ///
    /// Compares the positions rather than the rendered pairs, so two different unreadable
    /// positions stay two. Its exact equality DOES disagree with the kernel's wrap-tolerant
    /// `samePosition` — a ring closing at +180 that opened at -180 keeps its closing vertex here
    /// and loses it there. That is safe only because an accepted fence takes the kernel's list
    /// above and never reaches this function; it is not a property of the comparison.
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
