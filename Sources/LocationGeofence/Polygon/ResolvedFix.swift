import CioInternalCommon
import CoreLocation
import Foundation

/// A fix a pass has already obtained and gated, carried to whatever runs next so the same moment
/// is not requested twice.
///
/// A value type rather than `CLLocation` because it crosses task boundaries: `CLLocation` is a
/// reference type the compiler cannot prove immutable, and the fields below are all any consumer
/// reads.
struct ResolvedFix: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: CLLocationAccuracy
    /// When the fix was taken; decides whether a later pass may reuse it.
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

    /// Keeps accuracy and timestamp, which membership judges against.
    ///
    /// Altitude and vertical accuracy are NOT carried. Keep this out of the fix-quality logs:
    /// `alt=0` with no vertical accuracy is what drive analysis reads as a coarse cell fix.
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
