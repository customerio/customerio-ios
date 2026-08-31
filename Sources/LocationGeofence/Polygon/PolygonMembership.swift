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
    /// When `membership` was last written. Lets a late evaluation defer to a newer decision, the
    /// same way `MonitorRegionRecord.lastStateChangedAt` guards the baseline heal.
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
}

/// The device-centered circle planted inside a polygon's covering circle so the OS wakes the SDK
/// once the device has moved far enough for the membership verdict to change.
///
/// The covering circle alone is not enough: between the polygon boundary and the circle the OS is
/// silent, and a crossing there would go unnoticed until some unrelated wake. Radius is the
/// distance to the polygon boundary (floored), so leaving the tripwire is exactly the point at
/// which the previous verdict stops being safe to trust.
struct PolygonTripwire: Codable, Equatable, Sendable {
    let center: LocationData
    let radius: Double
}
