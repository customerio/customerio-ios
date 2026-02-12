import CioInternalCommon
import Foundation

private let locationTag = "Location"

extension Logger {
    func moduleNotInitialized() {
        error(
            "Location module is not initialized. Call CustomerIO.initializeLocation(withConfig:) first.",
            locationTag,
            nil
        )
    }

    func reconfigurationNotSupported() {
        error(
            "Location module is already initialized. Reconfiguration is not supported.",
            locationTag,
            nil
        )
    }

    func trackingDisabledIgnoringSetLastKnownLocation() {
        debug(
            "Location tracking is disabled, ignoring setLastKnownLocation call",
            locationTag
        )
    }

    func invalidCoordinates() {
        error(
            "Invalid location coordinates provided to setLastKnownLocation",
            locationTag,
            nil
        )
    }

    func trackingLocation(latitude: Double, longitude: Double) {
        debug(
            "Tracking location: lat=\(latitude), lon=\(longitude)",
            locationTag
        )
    }
}
