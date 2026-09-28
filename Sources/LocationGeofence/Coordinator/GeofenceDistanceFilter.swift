import CioInternalCommon
import Foundation

/// Picks the `limit` regions closest to a location, capping business registrations at the OS
/// budget (20 monitored regions on iOS, one reserved for the movement trigger).
struct GeofenceDistanceFilter: Sendable {
    /// Ranks by distance to each region's *boundary* (`edgeDistanceTo`), so a region the device is
    /// inside ranks first and survives both the limit and the distance cap. The backend applies its
    /// own limit first, by distance to centre, so a large containing region can be cut before this.
    ///
    /// Ties break by ascending `id`. Distances are rounded to whole meters first: `CLLocation.distance`
    /// can vary sub-meter for identical inputs, which would defeat the tiebreak. Regions whose
    /// boundary is beyond `maxDistance` are excluded (`GeofenceConstants.noMonitoringDistanceCap` for
    /// no cap). Returns empty when `limit <= 0`.
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
