import CioDataPipelines
import CioInternalCommon
import CioLocation
import CoreLocation
import UIKit

// MARK: - Location Permissions and Updates

extension LocationTestViewController {
    func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    // MARK: - Background-location upgrade

    func refreshGrantBackgroundLocationUI() {
        guard grantBackgroundLocationButton != nil else { return }
        let status = currentAuthorizationStatus()
        switch status {
        case .notDetermined:
            grantBackgroundLocationButton.setTitle("Grant location access", for: .normal)
            grantBackgroundLocationButton.isEnabled = true
            grantBackgroundLocationButton.alpha = 1.0
            grantBackgroundStatusLabel.text = "Current: Not determined. Tap to grant 'When In Use' first."
        case .authorizedWhenInUse:
            grantBackgroundLocationButton.setTitle("Upgrade to 'Always'", for: .normal)
            grantBackgroundLocationButton.isEnabled = true
            grantBackgroundLocationButton.alpha = 1.0
            grantBackgroundStatusLabel.text = "Current: When In Use. Background geofence delivery requires 'Always'."
        case .authorizedAlways:
            grantBackgroundLocationButton.setTitle("Always — granted", for: .normal)
            grantBackgroundLocationButton.isEnabled = false
            grantBackgroundLocationButton.alpha = 0.6
            grantBackgroundStatusLabel.text = "Current: Always. Background geofence delivery is enabled."
        case .denied, .restricted:
            grantBackgroundLocationButton.setTitle("Open Settings", for: .normal)
            grantBackgroundLocationButton.isEnabled = true
            grantBackgroundLocationButton.alpha = 1.0
            grantBackgroundStatusLabel.text = "Current: Denied / Restricted. Enable location access in Settings."
        @unknown default:
            grantBackgroundLocationButton.setTitle("Grant background location", for: .normal)
            grantBackgroundStatusLabel.text = "Current: Unknown status (\(status.rawValue))."
        }
    }

    func handleGrantBackgroundLocationTap() {
        let status = currentAuthorizationStatus()
        switch status {
        case .notDetermined:
            // Foreground first; the auth-change delegate prompts for Always on success.
            userRequestedAlwaysUpgrade = true
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            presentAlwaysRationale()
        case .authorizedAlways:
            return
        case .denied, .restricted:
            openSystemSettings()
        @unknown default:
            return
        }
    }

    func presentAlwaysRationale() {
        let alert = UIAlertController(
            title: "Allow background location?",
            message: "Geofence transitions only fire while the app is backgrounded if 'Always' authorization is granted. iOS shows this prompt at most once — after that, granting Always means opening the Settings app.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { [weak self] _ in
            self?.locationManager.requestAlwaysAuthorization()
        })
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { [weak self] _ in
            self?.openSystemSettings()
        })
        present(alert, animated: true)
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func currentAuthorizationStatus() -> CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return locationManager.authorizationStatus
        } else {
            return CLLocationManager.authorizationStatus()
        }
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
