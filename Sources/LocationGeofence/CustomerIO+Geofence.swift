@_spi(Geofence) import CioLocation
import CioInternalCommon
import Foundation

/// Public API for the Geofence module, exposed through `CustomerIO.geofence`.
public protocol GeofenceServices {
    /// Requests a one-shot location fix and refreshes the nearby geofence set from it, **without**
    /// emitting a `CIO Location Update` analytics event (unlike `CustomerIO.location.requestLocationUpdate()`)
    /// and without caching the fix.
    ///
    /// Call this after the host app has been granted location permission — the SDK never requests
    /// permission itself. It is the primary way to drive geofencing when the module is configured
    /// with `GeofenceLocationMode.manual`; with the default `.automatic` the SDK acquires location
    /// on its own and this is only needed to force an immediate refresh.
    ///
    /// In `.manual`, call this once a user has been identified — a refresh requested before any
    /// identify is not retried automatically.
    func refreshFromCurrentLocation()
}

/// Extension to expose the Geofence module through CustomerIO.
public extension CustomerIO {
    /// Access the Geofence module. Register it via `SDKConfigBuilder.addModule(GeofenceModule())`
    /// (alongside `LocationModule`) before `CustomerIO.initialize(withConfig:)`.
    static var geofence: GeofenceServices {
        GeofenceServicesImplementation()
    }
}

struct GeofenceServicesImplementation: GeofenceServices {
    func refreshFromCurrentLocation() {
        // Arm first so the returning fix drives a sync even without a prior no-location skip,
        // then request a silent (no-analytics) fix. Safe when the Location module isn't
        // registered — `CustomerIO.location` returns a no-op that only logs.
        GeofenceModuleState.shared.onRefreshRequested()
        CustomerIO.location.requestLocationUpdateSilently()
    }
}
