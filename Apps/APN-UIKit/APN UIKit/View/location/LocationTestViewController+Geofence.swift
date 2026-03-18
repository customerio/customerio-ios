import CioInternalCommon
import CioLocation
import UIKit

// MARK: - Geofencing Actions

extension LocationTestViewController {
    func addSampleGeofences() {
        do {
            let presets: [PresetLocation] = [
                PresetLocation(name: "Anarkali Bazaar", latitude: 31.569920255631676, longitude: 74.3124273864531, type: "Market"),
                PresetLocation(name: "Dolmen Mall", latitude: 31.46794689582185, longitude: 74.43590552575039, type: "Mall"),
                PresetLocation(name: "JW Marriott Hotel Riyadh", latitude: 25.06613635596822, longitude: 46.6764801938949, type: "Hotel"),
                PresetLocation(name: "Kareem Block Market", latitude: 31.504004050496576, longitude: 74.28084262389915, type: "Market"),
                PresetLocation(name: "Liberty Market", latitude: 31.510354633356954, longitude: 74.3437341288528, type: "Market"),
                PresetLocation(name: "New York", latitude: 40.7128, longitude: -74.0060, type: "City"),
                PresetLocation(name: "San Francisco", latitude: 37.7749, longitude: -122.4194, type: "City"),
                PresetLocation(name: "Thokar", latitude: 31.49118471585734, longitude: 74.23891870917167, type: "Station")
            ]
            let geofences = try presets.map { preset in
                let distance: Double
                if preset.name.lowercased().starts(with: "jw") {
                    distance = 5000
                } else {
                    distance = 500
                }
                return try GeofenceRegion(
                    id: "geofence_\(preset.name.lowercased().replacingOccurrences(of: " ", with: "_"))",
                    latitude: preset.latitude,
                    longitude: preset.longitude,
                    radius: distance,
                    name: preset.name,
                    customData: ["type": preset.type ?? "marker"],
                    dwellTimeMs: 10 * 60 * 1000 // 10 minutes
                )
            }

            CustomerIO.location.geofenceServices.addGeofences(regions: geofences)
            updateGeofenceCount()
            showToast(withMessage: "Added \(geofences.count) sample geofences")
        } catch {
            showToast(withMessage: "Error adding geofences: \(error.localizedDescription)")
        }
    }

    func removeAllGeofences() {
        CustomerIO.location.geofenceServices.removeAllGeofences()
        updateGeofenceCount()
        showToast(withMessage: "Removed all geofences")
    }

    func addQuickTestGeofence(latitude: Double, longitude: Double, name: String) {
        do {
            let quickTest = try GeofenceRegion(
                id: "quick_test_\(name.lowercased().replacingOccurrences(of: " ", with: "_"))",
                latitude: latitude,
                longitude: longitude,
                radius: 100.0,
                name: "\(name) Quick Test",
                customData: ["type": "quick_test"],
                dwellTimeMs: 1000 // 1 second for easy testing
            )

            CustomerIO.location.geofenceServices.addGeofences(regions: [quickTest])
            updateGeofenceCount()
        } catch {
            print("Error adding quick test geofence: \(error.localizedDescription)")
        }
    }

    func updateGeofenceCount() {
        let count = CustomerIO.location.geofenceServices.getActiveGeofences().count
        activeGeofenceCountLabel?.text = "Active geofences: \(count)"
    }
}
