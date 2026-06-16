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
}
