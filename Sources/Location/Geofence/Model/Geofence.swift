import CioInternalCommon
import Foundation

/// A geofence region returned by the server.
struct Geofence: Codable, Equatable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
    /// Radius in meters.
    let radius: Double
    let name: String
    let transitionTypes: Set<GeofenceTransition>
    let lastUpdated: Date
}
