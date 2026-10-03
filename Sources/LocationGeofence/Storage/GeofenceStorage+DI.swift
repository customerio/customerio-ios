import CioInternalCommon
import Foundation

extension DIGraphShared {
    var customGeofenceStorage: GeofenceStorage {
        GeofenceStorage.shared
    }
}

extension GeofenceStorage {
    static let shared = GeofenceStorage()
}
