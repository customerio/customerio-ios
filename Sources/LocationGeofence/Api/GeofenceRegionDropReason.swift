import Foundation

enum GeofenceRegionDropReason: String, Error, CaseIterable {
    /// The one reason exempt from the all-dropped guard: the workspace moved on, so stale monitors
    /// should go.
    case unknownShape = "unrecognized shape"
    /// Malformed, so it counts as unreadable and the cache survives.
    case undescribedShape = "shape missing but polygon fields present"
    case unusableCircle = "invalid coordinates or radius"
    case unusablePolygon = "missing or undecodable polygon geometry"

    /// Stable across rewording, unlike `rawValue`.
    var logToken: String {
        switch self {
        case .unknownShape: return "unknown_shape"
        case .undescribedShape: return "undescribed_shape"
        case .unusableCircle: return "unusable_circle"
        case .unusablePolygon: return "unusable_polygon"
        }
    }
}
