import CioInternalCommon
import Foundation

// The accessor the generated DI expects for `InjectCustomShared`. In its own file to keep
// `GeofenceStorage.swift` under SwiftLint's `file_length` limit.

extension DIGraphShared {
    var customGeofenceStorage: GeofenceStorage {
        GeofenceStorage.shared
    }
}

extension GeofenceStorage {
    static let shared = GeofenceStorage()
}
