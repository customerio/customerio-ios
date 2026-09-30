import CioInternalCommon
import Foundation

/// No `unknown` case on purpose: a missing record means undecided, so an undecidable fix never
/// overwrites a belief.
enum PolygonMembership: String, Codable, Sendable {
    case inside
    case outside
}

struct PolygonMembershipRecord: Codable, Equatable, Sendable {
    var membership: PolygonMembership
    /// Newest evidence that set OR confirmed the belief. The name is the stored key: renaming it
    /// without a `CodingKeys` mapping fails the whole `GeofenceState` decode.
    var lastChangedAt: Date
}

enum PolygonMembershipOutcome: Equatable {
    /// The caller still applies the geofence's transition-type filter.
    case deliver(GeofenceTransition)
    case suppressedNoChange
    case suppressedNewerDecision
    /// First decision is outside: there is no crossing to report.
    case suppressedInitialOutside
    /// Not registered. Creating a belief would deliver an enter for a fence the OS no longer watches.
    case suppressedUnmonitored
    case suppressedGeometryChanged
}
