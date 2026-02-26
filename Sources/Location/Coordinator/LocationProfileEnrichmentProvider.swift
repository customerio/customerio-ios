import CioInternalCommon
import Foundation

/// Provides last known location as profile enrichment attributes for identify.
/// Uses the same cache as the track flow (LastLocationStorage) so identify gets the same persisted location.
final class LocationProfileEnrichmentProvider: ProfileEnrichmentProvider {
    private let storage: LastLocationStorage

    init(storage: LastLocationStorage) {
        self.storage = storage
    }

    func getProfileEnrichmentAttributes() -> [String: Any]? {
        guard let location = storage.getCachedLocation() else {
            return nil
        }
        return [
            "location_latitude": location.latitude,
            "location_longitude": location.longitude
        ]
    }
}
