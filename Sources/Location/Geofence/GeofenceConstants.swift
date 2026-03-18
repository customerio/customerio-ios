import Foundation

/// Constants used throughout the geofencing implementation.
public enum GeofenceConstants {
    // MARK: - Event Names

    /// Event sent when user enters a geofence region
    public static let EVENT_GEOFENCE_ENTERED = "Geofence Entered"

    /// Event sent when user exits a geofence region
    public static let EVENT_GEOFENCE_EXITED = "Geofence Exited"

    /// Event sent when user dwells in a geofence region
    public static let EVENT_GEOFENCE_DWELLED = "Geofence Dwelled"

    // MARK: - Defaults

    /// Default radius in meters for geofence regions
    public static let DEFAULT_RADIUS_METERS: Double = 100.0

    /// Default dwell time in milliseconds (10 minutes)
    public static let DEFAULT_DWELL_TIME_MS: Int64 = 10 * 60 * 1000

    /// Maximum number of geofences supported by iOS
    public static let MAX_GEOFENCES: Int = 20

    // MARK: - Storage Keys

    /// UserDefaults key for storing geofence regions
    static let STORAGE_KEY = "io.customer.sdk.geofences"
}
