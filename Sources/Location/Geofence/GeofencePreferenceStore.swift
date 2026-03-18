import Foundation

// sourcery: AutoMockable
// sourcery: AutoDependencyInjection
/// Protocol for storing and retrieving geofence regions.
protocol GeofencePreferenceStore {
    /// Saves geofence regions to persistent storage.
    ///
    /// - Parameter regions: The geofence regions to save
    func saveGeofences(_ regions: [GeofenceRegion])

    /// Retrieves all saved geofence regions from persistent storage.
    ///
    /// - Returns: Array of geofence regions, or empty array if none saved
    func loadGeofences() -> [GeofenceRegion]

    /// Clears all saved geofence regions from persistent storage.
    func clearGeofences()
}

/// Implementation of GeofencePreferenceStore using UserDefaults.
class FileGeofencePreferenceStore: GeofencePreferenceStore {
    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = GeofenceConstants.STORAGE_KEY
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func saveGeofences(_ regions: [GeofenceRegion]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(regions) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }

    func loadGeofences() -> [GeofenceRegion] {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return []
        }

        let decoder = JSONDecoder()
        return (try? decoder.decode([GeofenceRegion].self, from: data)) ?? []
    }

    func clearGeofences() {
        userDefaults.removeObject(forKey: storageKey)
    }
}
