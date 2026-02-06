import CioInternalCommon
import Foundation

private let locationTag = "Location"

extension Logger {
    // MARK: - Initialization

    /// Logs that the Location module is not initialized and setLastKnownLocation was called.
    func moduleNotInitialized() {
        error(
            "Location module is not initialized. Call CustomerIO.initializeLocation(withConfig:) first.",
            locationTag,
            nil
        )
    }

    /// Logs that the Location module was already initialized and reconfiguration is not supported.
    func reconfigurationNotSupported() {
        error(
            "Location module is already initialized. Reconfiguration is not supported.",
            locationTag,
            nil
        )
    }

    // MARK: - setLastKnownLocation

    /// Logs that location tracking is disabled and setLastKnownLocation was ignored.
    func trackingDisabledIgnoringSetLastKnownLocation() {
        debug(
            "Location tracking is disabled, ignoring setLastKnownLocation call",
            locationTag
        )
    }

    /// Logs that invalid coordinates were provided to setLastKnownLocation.
    func invalidCoordinates() {
        error(
            "Invalid location coordinates provided to setLastKnownLocation",
            locationTag,
            nil
        )
    }

    /// Logs that a location is being tracked with the given coordinates.
    func trackingLocation(latitude: Double, longitude: Double) {
        debug(
            "Tracking location: lat=\(latitude), lon=\(longitude)",
            locationTag
        )
    }
}
