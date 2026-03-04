import CioInternalCommon
import Foundation

/// Provides last known location as profile enrichment attributes for identify.
/// Uses the same cache as the track flow (LastLocationStorage) so identify gets the same persisted location.
/// When config mode is `.off`, does not include location (returns nil).
final class LocationProfileEnrichmentProvider: ProfileEnrichmentProvider {
    private let storage: LastLocationStorage
    private let config: LocationConfig

    init(storage: LastLocationStorage, config: LocationConfig) {
        self.storage = storage
        self.config = config
    }

    func getProfileEnrichmentAttributes() -> [String: Any]? {
        guard config.mode != .off else {
            return nil
        }
        guard let location = storage.getCachedLocation() else {
            return nil
        }
        return [
            "location_latitude": location.latitude,
            "location_longitude": location.longitude
        ]
    }

    func resetContext() {
        storage.clearCache()
    }
}
