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
    /// The ring cached when the belief was written. An `outside` belief proves an observed entry
    /// only against this same ring: after a replacement, "outside the old shape" says nothing about
    /// when the device came to be inside the new one. Nil on records written before the field
    /// existed: nothing says which ring they were formed against, so they prove no entry.
    var ring: [LocationData]?
    /// Newest inside evidence that proved the stay on its own: a fix whose accuracy disk lay wholly
    /// inside the ring (`PolygonVerdict.qualifiesDwell`), by an entry or a confirmation alike. A
    /// marginal arrival moves `lastChangedAt` but not this, so an EXIT is timed only from a stay
    /// that was really proven. Nil on records written before the field, which then time no EXIT.
    var lastDecisiveInsideAt: Date?
    /// Newest outside evidence, kept through later inside writes, so a departure the SDK observed
    /// is not erased by the inside pass that followed it. Nil on records written before the field,
    /// whose `lastChangedAt` stands in while the belief is still outside.
    var lastOutsideAt: Date?

    /// The newest outside evidence this record holds, from the field or, for a record written
    /// before it, from an outside belief's own stamp.
    var latestOutsideAt: Date? {
        lastOutsideAt ?? (membership == .outside ? lastChangedAt : nil)
    }
}

/// A membership write's outcome, with when the belief it found was last proven; see
/// `GeofenceStorage.recordPolygonMembershipWrite`.
struct PolygonMembershipWrite: Equatable {
    let outcome: PolygonMembershipOutcome
    var previousProvenAt: Date?
}

enum PolygonMembershipOutcome: Equatable {
    /// The caller still applies the geofence's transition-type filter.
    case deliver(GeofenceTransition)
    /// The belief moved to inside with no recent outside belief for the same ring before it: the
    /// first decision for this polygon, the first after its ring was replaced, or one whose outside
    /// proof is older than `GeofenceConstants.polygonOutsideProofMaxAge`. The caller still
    /// delivers an ENTER (enter-when-inside), but no crossing was observed, so the stay it begins
    /// has no known start and must not report `entered_at` or a visit duration.
    case discoveredInside
    case suppressedNoChange
    case suppressedNewerDecision
    /// First decision is outside: there is no crossing to report.
    case suppressedInitialOutside
    /// Not registered. Creating a belief would deliver an enter for a fence the OS no longer watches.
    case suppressedUnmonitored
    case suppressedGeometryChanged
}
