import CioInternalCommon
import Foundation

/// Sizes the movement trigger so it doubles as the wake source for polygon membership: crossing a
/// polygon boundary produces no OS event, so something has to wake us to re-evaluate.
enum PolygonWakeRadius {
    /// Sized to the nearest polygon boundary, wherever the device stands relative to the covering
    /// circles. Falls back to the configured refresh radius, so a device with no polygon boundary
    /// closer than that behaves exactly as before.
    ///
    /// Deliberately NOT restricted to circles the device is already inside. A covering-circle enter
    /// does not re-arm the trigger, so a device that entered a circle while still inside a wide
    /// trigger would carry that wide trigger across the polygon boundary: no OS event, no wake, and
    /// on the way out an exit over an unchanged `outside` belief — the whole visit silent rather
    /// than late. Sizing to the boundary from outside makes the trigger tighten as the device
    /// approaches, so the wake arrives before the crossing.
    static func radius(
        at location: LocationData,
        registeredPolygons: [Geofence],
        config: GeofenceConfig
    ) -> Double {
        let nearestBoundary = registeredPolygons
            .compactMap { boundaryDistance(from: location, to: $0) }
            .min()
        guard let nearestBoundary else { return config.localRefreshTriggerRadius }
        return max(
            GeofenceConstants.polygonWakeMinRadius,
            min(config.localRefreshTriggerRadius, nearestBoundary)
        )
    }

    /// `nil` when `geofence` is not a polygon. Unsigned: the distance to the boundary is what the
    /// trigger is sized against whether the device is inside the ring or outside it.
    private static func boundaryDistance(from location: LocationData, to geofence: Geofence) -> Double? {
        guard let polygon = geofence.polygonRegion else { return nil }
        return abs(polygon.signedEdgeDistance(to: location))
    }
}
