import Foundation

/// Why a region on the wire never became a monitorable fence.
enum GeofenceRegionDropReason: String, Error {
    /// A shape the server NAMED that this version cannot monitor. The workspace moved on, so this
    /// is the one reason exempt from the all-dropped guard: stale monitors should go with it.
    case unknownShape = "unrecognized shape"
    /// No shape named, but polygon fields present — a malformed payload, so it counts as unreadable
    /// and the cache survives.
    case undescribedShape = "shape missing but polygon fields present"
    case unusableCircle = "invalid coordinates or radius"
    case unusablePolygon = "missing or undecodable polygon geometry"

    /// Stable across rewording, unlike `rawValue`, which is the human sentence. Same split
    /// `GeofenceSyncSkipReason` makes, and for the same reason: a script keying off the prose
    /// breaks the day someone improves it.
    var logToken: String {
        switch self {
        case .unknownShape: return "unknown_shape"
        case .undescribedShape: return "undescribed_shape"
        case .unusableCircle: return "unusable_circle"
        case .unusablePolygon: return "unusable_polygon"
        }
    }
}
