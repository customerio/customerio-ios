import Foundation

/// Why a polygon evaluation reached no verdict, as a stable token.
///
/// Same prose/token split as `GeofenceSyncSkipReason` and `GeofenceRegionDropReason`: the sentence
/// is for a human reading the log, the token is what a script keys off. Free strings at the call
/// sites meant a reworded sentence silently changed the token — and one of them interpolated two
/// measurements, so no two records shared a `why` at all.
enum PolygonUndecidedReason: String {
    case noUsableFix = "no_usable_fix"
    case userChanged = "user_changed"
    case ringUnbuildable = "ring_unbuildable"
    case unregistered
    case circleExpired = "circle_expired"
    /// The fix cannot separate inside from outside: `|edge|` is within its accuracy. The two
    /// measurements ride as their own keys rather than in the token.
    case withinAccuracy = "within_accuracy"

    var prose: String {
        switch self {
        case .noUsableFix: return "no usable fix"
        case .userChanged: return "the identified user changed while resolving"
        case .ringUnbuildable: return "the stored ring no longer builds"
        case .unregistered: return "no longer a registered polygon"
        case .circleExpired: return "the circle the event was raised against is gone"
        case .withinAccuracy: return "edge distance within the fix's accuracy"
        }
    }
}

/// Why a whole-set pass did not run.
enum PolygonPassSkipReason: String {
    case passInFlight = "pass_in_flight"

    var prose: String {
        switch self {
        case .passInFlight: return "a pass is already running"
        }
    }
}

/// What prompted a re-evaluation.
enum PolygonEvaluationReason: String {
    case newPolygon = "new_polygon"
    case newPolygonForcedRequestFailed = "new_polygon_forced_request_failed"
    case movement
    case foreground

    var prose: String {
        switch self {
        case .newPolygon: return "newly registered"
        case .newPolygonForcedRequestFailed: return "newly registered, forced request failed"
        case .movement: return "movement"
        case .foreground: return "foreground"
        }
    }
}

extension PolygonMembershipOutcome {
    /// snake_case like every other `why` in the module; the synthesized case name is camelCase.
    var logToken: String {
        switch self {
        case .deliver: return "deliver"
        case .suppressedNoChange: return "no_change"
        case .suppressedNewerDecision: return "newer_decision"
        case .suppressedInitialOutside: return "initial_outside"
        case .suppressedUnmonitored: return "unmonitored"
        case .suppressedGeometryChanged: return "geometry_changed"
        }
    }
}
