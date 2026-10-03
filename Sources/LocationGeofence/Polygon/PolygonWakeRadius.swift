import CioInternalCommon
import Foundation

/// Sizes the movement trigger to double as the polygon wake: a polygon crossing raises no OS event.
enum PolygonWakeRadius {
    /// Deliberately NOT restricted to polygons the device is inside: sizing from outside makes the
    /// wake arrive before the crossing.
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

    private static func boundaryDistance(from location: LocationData, to geofence: Geofence) -> Double? {
        guard let polygon = geofence.polygonRegion else { return nil }
        return abs(polygon.signedEdgeDistance(to: location))
    }
}
