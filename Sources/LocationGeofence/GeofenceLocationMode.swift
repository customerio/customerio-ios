import Foundation

/// Controls how the geofence module acquires the device location it needs to sync nearby geofences,
/// or disables geofencing entirely.
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

    /// Geofencing is disabled: the SDK registers no geofences, acquires no location, and fires no
    /// transitions. The local off switch for when the module is always linked (e.g. wrapper SDKs)
    /// but the app wants to opt out. Applied at initialization — any monitoring left by a prior
    /// session is torn down, so a build that ships `.off` disables itself on the next launch that
    /// initializes the SDK. In wrapper SDKs that is the next foreground launch; a background wake
    /// before then can still deliver transitions from the previous session's registrations.
    /// Transitions captured before the switch are still delivered; only future ones stop.
    case off
}
