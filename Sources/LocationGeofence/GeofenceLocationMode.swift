import Foundation

/// How the geofence module acquires location. Location acquired for geofencing is used only for
/// geofencing: never cached, sent as a `CIO Location Update` event or added to identify context.
public enum GeofenceLocationMode {
    /// The SDK acquires a fix when geofencing needs one and location tracking has none. Default.
    case automatic

    /// The SDK never acquires location itself; call `CustomerIO.geofence.refreshFromCurrentLocation()`.
    /// Transitions still fire once geofences are registered.
    case manual
}
