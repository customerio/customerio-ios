import CoreLocation
import Foundation

/// Anchor persistence for ``RegionRadiusProbe``.
///
/// The anchor has to outlive the process: region monitoring survives process death, and a
/// relaunched probe that cannot recover where it armed would re-anchor the rings on the wake's
/// own position and measure a fresh set of circles nobody ever walked out of.
extension RegionRadiusProbe {
    private static let anchorLatitudeKey = "cio_region_radius_probe_lat"
    private static let anchorLongitudeKey = "cio_region_radius_probe_lon"
    private static let anchorArmedAtKey = "cio_region_radius_probe_at"

    // MARK: - Anchor persistence

    static func storedAnchor() -> (coordinate: CLLocationCoordinate2D, armedAt: Date)? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: anchorLatitudeKey) != nil,
              defaults.object(forKey: anchorLongitudeKey) != nil
        else { return nil }
        let coordinate = CLLocationCoordinate2D(
            latitude: defaults.double(forKey: anchorLatitudeKey),
            longitude: defaults.double(forKey: anchorLongitudeKey)
        )
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        return (coordinate, Date(timeIntervalSince1970: defaults.double(forKey: anchorArmedAtKey)))
    }

    static func storeAnchor(coordinate: CLLocationCoordinate2D, armedAt: Date) {
        let defaults = UserDefaults.standard
        defaults.set(coordinate.latitude, forKey: anchorLatitudeKey)
        defaults.set(coordinate.longitude, forKey: anchorLongitudeKey)
        defaults.set(armedAt.timeIntervalSince1970, forKey: anchorArmedAtKey)
    }

    static func clearStoredAnchor() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: anchorLatitudeKey)
        defaults.removeObject(forKey: anchorLongitudeKey)
        defaults.removeObject(forKey: anchorArmedAtKey)
    }
}
