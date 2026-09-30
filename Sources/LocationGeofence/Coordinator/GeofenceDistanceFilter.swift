import CioInternalCommon
import Foundation

struct GeofenceDistanceFilter: Sendable {
    /// Ranks by distance to the boundary, so a region the device is inside ranks first. Rounded to
    /// whole meters because `CLLocation.distance` varies sub-meter, which would defeat the `id`
    /// tiebreak.
    func nearest(_ regions: [Geofence], to location: LocationData, limit: Int, maxDistance: Double) -> [Geofence] {
        guard limit > 0, !regions.isEmpty else { return [] }
        return regions
            .map { ($0, $0.edgeDistanceTo(location).rounded()) }
            .filter { $0.1 <= maxDistance }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0.id < rhs.0.id
            }
            .prefix(limit)
            .map(\.0)
    }
}
