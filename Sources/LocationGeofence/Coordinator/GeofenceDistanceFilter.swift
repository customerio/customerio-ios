import CioInternalCommon
import Foundation

/// Picks the `limit` regions closest to a given location, used by the sync coordinator
/// to cap business-geofence registrations at the OS-allowed count (iOS allows 20 total
/// monitored regions; one slot is reserved for the movement-trigger geofence).
struct GeofenceDistanceFilter: Sendable {
    /// Ties broken by ascending `id` for deterministic ordering. Distances are rounded to whole
    /// meters before comparison: `CLLocation.distance` can return sub-meter-varying values for
    /// identical inputs, which would otherwise defeat the id tiebreak and make the order of
    /// equidistant regions nondeterministic. Regions farther than `maxDistance` are excluded
    /// (`GeofenceConstants.noMonitoringDistanceCap` for no cap). Returns empty when `limit <= 0`.
    func nearest(_ regions: [Geofence], to location: LocationData, limit: Int, maxDistance: Double) -> [Geofence] {
        guard limit > 0, !regions.isEmpty else { return [] }
        return regions
            .map { ($0, $0.distanceTo(location).rounded()) }
            .filter { $0.1 <= maxDistance }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0.id < rhs.0.id
            }
            .prefix(limit)
            .map(\.0)
    }
}
