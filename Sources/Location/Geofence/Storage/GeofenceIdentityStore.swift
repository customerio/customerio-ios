import CioInternalCommon
import Foundation

/// Persists the currently-identified `userId` so the geofence direct-HTTP delivery flow can
/// read it at transition time even after an SDK relaunch.
final class GeofenceIdentityStore: @unchecked Sendable {
    private let storage: SharedKeyValueStorage

    init(storage: SharedKeyValueStorage) {
        self.storage = storage
    }

    var currentUserId: String? {
        storage.string(.geofenceUserId)
    }

    /// Empty strings are treated as a clear, not stored — guards against persisting `""`
    /// as if it were a valid identifier.
    func setUserId(_ userId: String) {
        storage.setString(userId.isEmpty ? nil : userId, forKey: .geofenceUserId)
    }

    func clearUserId() {
        storage.setString(nil, forKey: .geofenceUserId)
    }
}
