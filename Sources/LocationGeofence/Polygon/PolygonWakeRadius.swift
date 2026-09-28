import CioInternalCommon
import Foundation

/// Sizes the movement trigger so it doubles as the wake source for polygon membership: crossing a
/// polygon boundary produces no OS event, so something has to wake us to re-evaluate.
enum PolygonWakeRadius {
    /// Sized to the nearest polygon boundary, capped at the configured refresh radius, which is
    /// also the answer when no polygon is registered.
    ///
    /// Deliberately NOT restricted to circles the device is already inside: sizing to the boundary
    /// from outside tightens the trigger as the device approaches, so the wake arrives before the
    /// crossing instead of depending on a covering-circle enter to re-arm it.
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
