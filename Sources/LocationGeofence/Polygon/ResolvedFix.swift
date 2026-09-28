import CioInternalCommon
import CoreLocation
import Foundation

/// A fix already obtained and gated. A value type, not `CLLocation`, because it crosses task
/// boundaries.
struct ResolvedFix: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: CLLocationAccuracy
    let timestamp: Date

    init(latitude: Double, longitude: Double, horizontalAccuracy: CLLocationAccuracy, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }

    init(_ location: CLLocation) {
        self.init(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        )
    }

    /// Altitude and vertical accuracy are NOT carried. Keep this out of the fix-quality logs, where
    /// `alt=0` reads as a coarse cell fix.
    var location: CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: -1,
            timestamp: timestamp
        )
    }

    var locationData: LocationData {
        LocationData(latitude: latitude, longitude: longitude)
    }
}
