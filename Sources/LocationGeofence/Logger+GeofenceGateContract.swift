import Foundation

/// Diagnostic vocabulary and measurements for the contradiction gate's non-refusal outcomes.
/// Lives with the tail rather than in `Model/`, on the same rule as
/// `GeofenceMonitorEventOutcome.diagnosticReason`: these are log contracts, not domain models.

/// Why the gate had no fix to judge an in-window event against, as a stable token.
///
/// Same prose/token split as `PolygonUndecidedReason`: the sentence is for a human reading the
/// log, the token is what a script keys off. The two causes are not the same signal — one is a
/// resolver that produced nothing, the other an OS fix at a coordinate that cannot be used.
enum ContradictionGateNoFixReason: String, CaseIterable {
    case noFixAvailable = "no_fix_available"
    case invalidCoordinate = "invalid_coordinate"

    var prose: String {
        switch self {
        case .noFixAvailable: return "no fix to judge it against"
        case .invalidCoordinate: return "the only fix is at an unusable coordinate"
        }
    }
}

/// What the gate measured a gated fix against, grouped so the record can carry every measurement
/// the analysis needs without exceeding the parameter-count limit. Dropping one instead would be
/// the wrong trade: `rad` is what buckets a drive by fence size, and `age` and `acc` are the two
/// reasons a gate declines to refuse.
struct GateFixGeometry {
    let distanceFromCenter: Double
    let radius: Double
    let accuracy: Double
    let fixAge: TimeInterval

    /// Negative is inside, the circle path's convention — see the note on
    /// `geofenceContradictionAllowed`, whose `edge` key this feeds.
    var signedEdgeDistance: Double { distanceFromCenter - radius }
}
