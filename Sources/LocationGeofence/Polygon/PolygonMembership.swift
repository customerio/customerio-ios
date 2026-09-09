import CioInternalCommon
import Foundation

/// What the SDK believes about the device's position relative to a polygon geofence.
///
/// Tracked separately from the OS-facing dedup baseline in `MonitorRegionRecord`: the OS monitors
/// the polygon's covering circle and knows nothing about the polygon itself, so circle state and
/// polygon membership are different facts about the same geofence.
///
/// There is deliberately no `unknown` case — the absence of a record is what "not yet decided"
/// means. An undecidable fix therefore leaves an existing belief untouched instead of overwriting
/// it, which is what stops a coarse fix from erasing a known-inside state.
enum PolygonMembership: String, Codable, Sendable {
    case inside
    case outside
}

/// Per-polygon membership bookkeeping, persisted alongside the rest of the geofence state so a
/// cold wake compares against the pre-kill belief rather than starting over.
struct PolygonMembershipRecord: Codable, Equatable, Sendable {
    var membership: PolygonMembership
    /// Evidence time of the belief currently held: the timestamp of the newest fix or OS event to
    /// establish it OR confirm it, not only the one that last changed it. Lets a late evaluation
    /// defer to a newer decision, the same way `MonitorRegionRecord.lastStateChangedAt` guards the
    /// baseline heal.
    ///
    /// Do not rename without a `CodingKeys` case mapping back to the literal `"lastChangedAt"`. The
    /// synthesized keys make the property name the stored key, and a record written by an earlier
    /// build then fails the whole `GeofenceState` decode — which `loadFromDisk` swallows with
    /// `try?`, taking the cached geofences, monitor baselines, registration set and cooldowns with
    /// it on the next write.
    var lastChangedAt: Date
}

/// What `GeofenceStorage.recordPolygonMembership` decided about an evaluation.
enum PolygonMembershipOutcome: Equatable {
    /// Membership changed; the caller delivers this transition, subject to the geofence's own
    /// transition-type filter.
    case deliver(GeofenceTransition)
    case suppressedNoChange
    /// A newer decision was already recorded — the evaluation's fix predates it.
    case suppressedNewerDecision
    /// First decision for this polygon placed the device outside; there is no crossing to report.
    case suppressedInitialOutside
    /// The polygon is not in the registered set — an evaluation that raced a prune. Creating a
    /// belief here would deliver an enter for a fence the OS is no longer watching.
    case suppressedUnmonitored
}
