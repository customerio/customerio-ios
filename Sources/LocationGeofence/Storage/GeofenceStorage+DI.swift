import CioInternalCommon
import Foundation

// The shared `GeofenceStorage` and the graph accessor `AutoDependencyInjection` generates against
// the `InjectCustomShared` annotation on the actor. In their own file only because
// `GeofenceStorage.swift` sits at the module's 400-line `file_length` limit.

extension DIGraphShared {
    var customGeofenceStorage: GeofenceStorage {
        GeofenceStorage.shared
    }
}

extension GeofenceStorage {
    static let shared = GeofenceStorage()
}
