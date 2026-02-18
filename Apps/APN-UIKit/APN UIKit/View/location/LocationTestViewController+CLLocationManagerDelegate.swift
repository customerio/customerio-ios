import CioDataPipelines
import CioLocation
import CoreLocation
import UIKit

// MARK: - CLLocationManagerDelegate

extension LocationTestViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        stopFetchingLocation()

        guard let location = locations.last else { return }

        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude

        // Do not populate manual entry fields; those are for manual input only
        let sourceName = deviceLocationSourceName(for: location)
        setLocation(latitude: latitude, longitude: longitude, sourceName: sourceName)
    }

    /// Returns a short label for the device location source.
    /// Core Location can provide location from GPS, Wi‑Fi, cell, or a combination; the public API does not expose which.
    /// We only get simulation and accessory info on iOS 15+.
    private func deviceLocationSourceName(for location: CLLocation) -> String {
        if #available(iOS 15.0, *) {
            guard let sourceInfo = location.sourceInformation else {
                return "Device"
            }
            if sourceInfo.isSimulatedBySoftware {
                return "Device (Simulated)"
            }
            if sourceInfo.isProducedByAccessory {
                return "Device (Accessory)"
            }
        }
        return "Device"
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        stopFetchingLocation()
        showToast(withMessage: "Failed to get location: \(error.localizedDescription)")
    }

    // iOS 14+ authorization change callback
    @available(iOS 14.0, *)
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handleAuthorizationChange(manager.authorizationStatus)
    }

    // iOS 13 authorization change callback
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        handleAuthorizationChange(status)
    }

    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        // Handle "Request location once (SDK)" flow: user was waiting for permission, now call SDK.
        if userRequestedSdkLocationUpdate {
            userRequestedSdkLocationUpdate = false
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                lastSetLocationLabel.text = "Requested location once (SDK)..."
                CustomerIO.location.requestLocationUpdate()
                showToast(withMessage: "SDK requested location update")
            case .denied, .restricted:
                showLocationPermissionAlert()
            case .notDetermined:
                break
            @unknown default:
                break
            }
            return
        }

        // Only start fetching when the user explicitly tapped "Use Current Location" and we were waiting for permission.
        // This avoids auto-fetching location when the screen opens and auth was already granted (e.g. returning to the app).
        guard userRequestedCurrentLocation else { return }
        userRequestedCurrentLocation = false

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            startFetchingLocation()
        case .denied, .restricted:
            showLocationPermissionAlert()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}
