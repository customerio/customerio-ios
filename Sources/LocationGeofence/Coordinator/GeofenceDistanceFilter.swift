import CioInternalCommon
import Foundation

/// Picks the `limit` regions closest to a given location, used by the sync coordinator
/// to cap business-geofence registrations at the OS-allowed count (iOS allows 20 total
/// monitored regions; one slot is reserved for the movement-trigger geofence).
struct GeofenceDistanceFilter: Sendable {
    /// Ties broken by ascending `id` for deterministic ordering. Returns empty when `limit <= 0`.
    func nearest(_ regions: [Geofence], to location: LocationData, limit: Int) -> [Geofence] {
        guard limit > 0, !regions.isEmpty else { return [] }
        return regions
            .map { ($0, $0.distanceTo(location)) }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0.id < rhs.0.id
            }
            .prefix(limit)
            .map(\.0)
    }
}
