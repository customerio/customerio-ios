import CioInternalCommon
import CoreLocation
import Foundation

extension Geofence {
    /// Meters from the center, not the boundary.
    func distanceTo(latitude: Double, longitude: Double) -> CLLocationDistance {
        let center = CLLocation(latitude: self.latitude, longitude: self.longitude)
        let target = CLLocation(latitude: latitude, longitude: longitude)
        return center.distance(from: target)
    }

    func distanceTo(_ location: LocationData) -> CLLocationDistance {
        distanceTo(latitude: location.latitude, longitude: location.longitude)
    }

    /// Meters from the boundary (a polygon's ring, not its covering circle), `0` anywhere inside.
    /// Not a containment test.
    func edgeDistanceTo(_ location: LocationData) -> CLLocationDistance {
        if let polygon = polygonRegion { return max(0, -polygon.signedEdgeDistance(to: location)) }
        return max(0, distanceTo(location) - radius)
    }
}
