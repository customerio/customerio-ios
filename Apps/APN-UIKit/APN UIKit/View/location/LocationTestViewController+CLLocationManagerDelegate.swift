import CioDataPipelines
import CioLocation
import CioLocationGeofence
import CoreLocation
import UIKit

// MARK: - CLLocationManagerDelegate

extension LocationTestViewController: @MainActor CLLocationManagerDelegate {
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

    /// **Customer integration pattern.** Call `CustomerIO.geofence.refreshFromCurrentLocation()`
    /// when permission lands in a granted state — it bootstraps geofence sync from the current
    /// location without emitting a `CIO Location Update` analytics event (unlike
    /// `requestLocationUpdate()`). Safe to invoke on every delegate firing.
    @available(iOS 14.0, *)
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            CustomerIO.geofence.refreshFromCurrentLocation()
        }
        handleAuthorizationChange(status)
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            CustomerIO.geofence.refreshFromCurrentLocation()
        }
        handleAuthorizationChange(status)
    }

    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        refreshGrantBackgroundLocationUI()

        if userRequestedAlwaysUpgrade {
            userRequestedAlwaysUpgrade = false
            handleAlwaysUpgradeResult(status)
            return
        }
        if userRequestedSdkLocationUpdate {
            userRequestedSdkLocationUpdate = false
            handleSdkLocationUpdateResult(status)
            return
        }
        guard userRequestedCurrentLocation else { return }
        userRequestedCurrentLocation = false
        handleCurrentLocationResult(status)
    }

    /// WhenInUse here is the precondition; the rationale and the Always prompt fire in sequence.
    private func handleAlwaysUpgradeResult(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse:
            presentAlwaysRationale()
        case .denied, .restricted:
            showLocationPermissionAlert()
        default:
            break
        }
    }

    private func handleSdkLocationUpdateResult(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            lastSetLocationLabel.text = "Requested location once (SDK)..."
            CustomerIO.location.requestLocationUpdate()
            showToast(withMessage: "SDK requested location update")
        case .denied, .restricted:
            showLocationPermissionAlert()
        default:
            break
        }
    }

    private func handleCurrentLocationResult(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            startFetchingLocation()
        case .denied, .restricted:
            showLocationPermissionAlert()
        default:
            break
        }
    }
}
