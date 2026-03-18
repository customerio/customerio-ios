import Foundation

/// Public interface for geofencing operations.
///
/// Geofencing is available only when location tracking is enabled.
/// The SDK requires location permissions but does not request them - the app handles permission requests.
///
/// **Example:**
/// ```swift
/// // Create geofence regions
/// let regions = [
///     try GeofenceRegion(
///         id: "store_123",
///         latitude: 37.7749,
///         longitude: -122.4194,
///         radius: 500.0,
///         name: "Downtown Store"
///     )
/// ]
///
/// // Add geofences
/// CustomerIO.location.geofenceServices.addGeofences(regions: regions)
///
/// // Get active geofences
/// let active = CustomerIO.location.geofenceServices.getActiveGeofences()
///
/// // Remove specific geofences
/// CustomerIO.location.geofenceServices.removeGeofences(ids: ["store_123"])
///
/// // Remove all geofences
/// CustomerIO.location.geofenceServices.removeAllGeofences()
/// ```
public protocol GeofenceServices: AnyObject {
    /// Adds geofence regions to monitor.
    ///
    /// - If a geofence with the same ID already exists, it will be updated.
    /// - If a different geofence has the same lat/long, a warning is logged and the duplicate is skipped.
    /// - iOS supports a maximum of 20 geofences. If this limit is exceeded, the oldest geofences are removed.
    ///
    /// - Parameter regions: The geofence regions to add
    func addGeofences(regions: [GeofenceRegion])

    /// Removes geofences with the specified IDs.
    ///
    /// - Parameter ids: The IDs of geofences to remove
    func removeGeofences(ids: [String])

    /// Removes all active geofences.
    func removeAllGeofences()

    /// Returns all currently active geofence regions.
    ///
    /// - Returns: Array of active geofence regions
    func getActiveGeofences() -> [GeofenceRegion]
}
