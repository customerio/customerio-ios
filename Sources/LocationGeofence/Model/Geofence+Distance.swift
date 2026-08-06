import CioInternalCommon
import CoreLocation
import Foundation

extension Geofence {
    /// Straight-line distance in meters from this geofence's center to the given coordinates.
    func distanceTo(latitude: Double, longitude: Double) -> CLLocationDistance {
        let center = CLLocation(latitude: self.latitude, longitude: self.longitude)
        let target = CLLocation(latitude: latitude, longitude: longitude)
        return center.distance(from: target)
    }

    /// Straight-line distance in meters from this geofence's center to the given location.
    func distanceTo(_ location: LocationData) -> CLLocationDistance {
        distanceTo(latitude: location.latitude, longitude: location.longitude)
    }

    /// Distance in meters from this geofence's *boundary* to the given location, `0` when the
    /// location is inside.
    ///
    /// Monitoring relevance is proximity to the boundary, not to the center: ranking on center
    /// distance evicts a large region the device currently occupies as soon as
    /// `maxBusinessGeofences` regions have nearer centers, and an unmonitored region can never
    /// report its exit.
    ///
    /// Not a containment test — this is `0` for every point inside. Use `distanceTo` against
    /// `radius` to ask whether the device is inside a region.
    func edgeDistanceTo(_ location: LocationData) -> CLLocationDistance {
        max(0, distanceTo(location) - radius)
    }
}
