import CioDataPipelines
import CioLocation
import CoreLocation
import UIKit

// MARK: - Location Permissions and Updates

extension LocationTestViewController {
    func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func setLocation(latitude: Double, longitude: Double, sourceName: String? = nil) {
        let location = CLLocation(latitude: latitude, longitude: longitude)

        CustomerIO.location.setLastKnownLocation(location)

        let sourceText = sourceName.map { " (\($0))" } ?? ""
        lastSetLocationLabel.text = "Last set: \(latitude), \(longitude)\(sourceText)"

        showToast(withMessage: "Location set successfully\(sourceText)")
    }

    func setManualLocation() {
        let latText = latitudeTextField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let lonText = longitudeTextField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        guard !latText.isEmpty, !lonText.isEmpty,
              let latitude = Double(latText),
              let longitude = Double(lonText)
        else {
            showToast(withMessage: "Please enter valid coordinates")
            return
        }

        setLocation(latitude: latitude, longitude: longitude, sourceName: "Manual")
    }

    func requestCurrentLocation() {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = locationManager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }

        switch status {
        case .notDetermined:
            userRequestedCurrentLocation = true
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startFetchingLocation()
        case .denied, .restricted:
            showLocationPermissionAlert()
        @unknown default:
            showToast(withMessage: "Unknown location permission status")
        }
    }

    func startFetchingLocation() {
        useCurrentLocationButton.isEnabled = false
        useCurrentLocationButton.setTitle("📍  Fetching...", for: UIControl.State.normal)
        useCurrentLocationButton.alpha = 0.6

        locationManager.requestLocation()
    }

    func stopFetchingLocation() {
        useCurrentLocationButton.isEnabled = true
        useCurrentLocationButton.setTitle("📍  Use Current Location", for: UIControl.State.normal)
        useCurrentLocationButton.alpha = 1.0
    }

    /// Asks for location permission if needed, then asks the SDK to request a single location update.
    func requestSdkLocationUpdateOnce() {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = locationManager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }

        switch status {
        case .notDetermined:
            userRequestedSdkLocationUpdate = true
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            lastSetLocationLabel.text = "Requesting location once (SDK)..."
            CustomerIO.location.requestLocationUpdate()
            showToast(withMessage: "SDK requested location update")
        case .denied, .restricted:
            showLocationPermissionAlert()
        @unknown default:
            showToast(withMessage: "Unknown location permission status")
        }
    }

    /// Asks the SDK to stop any in-flight location updates.
    func stopSdkLocationUpdates() {
        CustomerIO.location.stopLocationUpdates()
        lastSetLocationLabel.text = "Location updates stopped"
        showToast(withMessage: "Stopped location updates")
    }

    func showLocationPermissionAlert() {
        let alert = UIAlertController(
            title: "Location Permission Required",
            message: "Please enable location access in Settings to use this feature.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        })

        present(alert, animated: true)
    }
}
