import Foundation

/// Controls how the geofence module acquires the device location it needs to sync nearby geofences.
///
/// Location acquired for geofencing is never sent as a `CIO Location Update` analytics event, cached,
/// or added to identify context — it is used for geofencing only.
public enum GeofenceLocationMode {
    /// The SDK automatically acquires a location fix whenever geofencing needs one and none is
    /// already available from location tracking (e.g. on identify). Default.
    case automatic

    /// The SDK never acquires location on its own. The host app drives geofencing by calling
    /// `CustomerIO.geofence.refreshFromCurrentLocation()` after granting location permission
    /// (movement transitions still work once geofences are registered).
    case manual
}
