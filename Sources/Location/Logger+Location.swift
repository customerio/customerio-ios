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

    func trackingDisabledIgnoringRequestLocationUpdate() {
        debug(
            "Location tracking is disabled, ignoring requestLocationUpdate call",
            locationTag
        )
    }

    func locationPermissionNotGrantedIgnoringRequest() {
        debug(
            "Location permission not granted, ignoring location request",
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

    func locationRequestCancelled() {
        debug(
            "Location request was cancelled; not posting update",
            locationTag
        )
    }

    func locationRequestFailed(_ err: Error) {
        error(
            "Location request failed",
            locationTag,
            err
        )
    }

    func locationRequestAlreadyInFlightIgnoringCall() {
        debug(
            "Location request already in flight; ignoring duplicate requestLocationOnce call",
            locationTag
        )
    }
}
