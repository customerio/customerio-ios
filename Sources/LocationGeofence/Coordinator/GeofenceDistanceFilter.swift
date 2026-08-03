import CioInternalCommon
import Foundation

/// Picks the `limit` regions closest to a given location, used by the sync coordinator
/// to cap business-geofence registrations at the OS-allowed count (iOS allows 20 total
/// monitored regions; one slot is reserved for the movement-trigger geofence).
struct GeofenceDistanceFilter: Sendable {
    /// Ranks and caps by distance to each region's *boundary* (`edgeDistanceTo`), so a region the
    /// device is inside ranks first among the candidates and survives both the limit and the
    /// distance cap.
    ///
    /// Only among the candidates: the backend applies its own limit first, ordered by distance to
    /// each region's center, so in a dense workspace a large region containing the device can be
    /// cut before it ever reaches this sort. Aligning that server-side ordering with boundary
    /// distance is a separate change.
    ///
    /// Ties broken by ascending `id` for deterministic ordering. Distances are rounded to whole
    /// meters before comparison: `CLLocation.distance` can return sub-meter-varying values for
    /// identical inputs, which would otherwise defeat the id tiebreak and make the order of
    /// equidistant regions nondeterministic. Regions whose boundary is farther than `maxDistance`
    /// are excluded (`GeofenceConstants.noMonitoringDistanceCap` for no cap). Returns empty when
    /// `limit <= 0`.
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
