import CioInternalCommon
import Foundation

/// A closed set, so `sh` stays groupable; the token the server actually sent is on
/// `registration.rejected`.
enum GeofenceCatalogShape: String, CaseIterable {
    case circle
    case polygon
    /// Polygon fields with no discriminator.
    case undescribed
    /// A shape the server named that this version cannot monitor.
    case unknown
}

extension GeofenceApiRegion {
    /// Must match `toDomain`'s normalization, so `sh` names the shape the SDK actually monitored.
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

    /// Which fields win follows the shape, not their presence; the other source is only a fallback.
    var catalogCenter: LocationData? {
        let flat = latitude.flatMap { lat in longitude.map { LocationData(latitude: lat, longitude: $0) } }
        let enclosing = enclosingCircle.map { LocationData(latitude: $0.latitude, longitude: $0.longitude) }
        return prefersEnclosingCircle ? enclosing ?? flat : flat ?? enclosing
    }

    var catalogRadius: Double? {
        prefersEnclosingCircle ? enclosingCircle?.baseRadiusM ?? radius : radius ?? enclosingCircle?.baseRadiusM
    }

    /// Both shapes the mapper resolves through `resolvedPolygon()`.
    private var prefersEnclosingCircle: Bool {
        catalogShape == .polygon || catalogShape == .undescribed
    }

    /// `lat_lon` pairs (not GeoJSON order), canonical so the count matches `nv`. Never a membership
    /// input: the field truncates. `ring` must stay in `GeofenceLog.composedKeys`.
    var catalogRing: [String]? {
        guard let ring = geometry?.coordinates.first, !ring.isEmpty else { return nil }
        // The kernel's own list when the region resolves, so the catalog never reports a different
        // ring from the one membership uses (the fallback below doesn't tolerate antimeridian wrap).
        if case .success(let geofence) = toDomain(), let vertices = geofence.vertices {
            return vertices.map { "\(Self.catalogCoordinate($0.latitude, max: 90))_\(Self.catalogCoordinate($0.longitude, max: 180))" }
        }
        // Only for a REJECTED ring. Bad positions are kept as `bad`, not dropped, so `nv` still
        // matches the ring.
        return Self.canonicalised(ring).map { position in
            guard position.count >= 2 else { return "bad_bad" }
            return "\(Self.catalogCoordinate(position[1], max: 90))_\(Self.catalogCoordinate(position[0], max: 180))"
        }
    }

    /// `PolygonRegion.init(vertices:)`'s canonicalization without its rejection. Exact equality, not
    /// wrap-tolerant: safe only because an accepted fence never reaches this.
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
