import CioInternalCommon
import CoreLocation
import Foundation

/// Sizes the movement trigger so it doubles as the wake source for polygon membership: crossing a
/// polygon boundary produces no OS event, so something has to wake us to re-evaluate.
enum PolygonWakeRadius {
    /// Sized to the nearest boundary among polygons whose covering circle contains the device —
    /// leaving that circle is exactly where a verdict may change. Polygons elsewhere cannot be
    /// crossed before their own covering-circle enter fires. Falls back to the configured refresh
    /// radius, so a device with no polygons nearby behaves exactly as before.
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

    /// `nil` when `geofence` is not a polygon, or the device is outside its covering circle.
    private static func boundaryDistance(from location: LocationData, to geofence: Geofence) -> Double? {
        guard let polygon = geofence.polygonRegion else { return nil }
        let center = CLLocation(latitude: geofence.latitude, longitude: geofence.longitude)
        let here = CLLocation(latitude: location.latitude, longitude: location.longitude)
        guard here.distance(from: center) <= geofence.radius else { return nil }
        return abs(polygon.signedEdgeDistance(to: location))
    }
}
