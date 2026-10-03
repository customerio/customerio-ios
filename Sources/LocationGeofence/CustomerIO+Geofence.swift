@_spi(Geofence) import CioLocation
import CioInternalCommon
import Foundation

/// Public API for the Geofence module, exposed through `CustomerIO.geofence`.
public protocol GeofenceServices {
    /// Requests a one-shot location fix and refreshes nearby geofences from it. The fix is not
    /// cached or sent as a `CIO Location Update` event.
    ///
    /// Call after location permission is granted; the SDK never requests it. Required in
    /// `.manual` mode, and only after identify (an earlier call is not retried). In `.automatic`
    /// it just forces an immediate refresh.
    func refreshFromCurrentLocation()
}

public extension CustomerIO {
    /// Access the Geofence module. Register it via `SDKConfigBuilder.addModule(GeofenceModule())`
    /// (alongside `LocationModule`) before `CustomerIO.initialize(withConfig:)`.
    static var geofence: GeofenceServices {
        GeofenceServicesImplementation()
    }
}

struct GeofenceServicesImplementation: GeofenceServices {
    func refreshFromCurrentLocation() {
        // Arm first so the returning fix drives a sync.
        GeofenceModuleState.shared.onRefreshRequested()
        CustomerIO.location.requestLocationUpdateSilently()
    }
}
