import Foundation

/// The raw value is the stable token scripts key off; `prose` can be reworded.
enum PolygonUndecidedReason: String, CaseIterable {
    case noUsableFix = "no_usable_fix"
    case userChanged = "user_changed"
    case ringUnbuildable = "ring_unbuildable"
    case unregistered
    case circleExpired = "circle_expired"
    case withinAccuracy = "within_accuracy"
    case fixTooOld = "fix_too_old"
    case accuracyTooLow = "accuracy_too_low"
    case corroborationUnnecessary = "corroboration_unnecessary"
    case corroborationDisagreed = "corroboration_disagreed"
    case corroborationNotIndependent = "corroboration_not_independent"

    var prose: String {
        switch self {
        case .noUsableFix: return "no usable fix"
        case .userChanged: return "the identified user changed while resolving"
        case .ringUnbuildable: return "the stored ring no longer builds"
        case .unregistered: return "no longer a registered polygon"
        case .circleExpired: return "the circle the event was raised against is gone"
        case .withinAccuracy: return "edge distance within the fix's accuracy"
        case .fixTooOld: return "fix too old"
        case .accuracyTooLow: return "accuracy too low for a venue this size"
        case .corroborationUnnecessary: return "already believed inside, so no second fix was needed"
        case .corroborationDisagreed: return "the second fix read outside"
        case .corroborationNotIndependent: return "the second fix did not postdate the first"
        }
    }
}

enum PolygonPassSkipReason: String, CaseIterable {
    case passInFlight = "pass_in_flight"

    var prose: String {
        switch self {
        case .passInFlight: return "a pass is already running"
        }
    }
}

enum PolygonEvaluationReason: String, CaseIterable {
    case newPolygon = "new_polygon"
    case newPolygonForcedRequestFailed = "new_polygon_forced_request_failed"
    case movement
    case foreground
    case osTransition = "os_transition"
    case visit

    var prose: String {
        switch self {
        case .newPolygon: return "newly registered"
        case .newPolygonForcedRequestFailed: return "newly registered, forced request failed"
        case .movement: return "movement"
        case .foreground: return "foreground"
        case .osTransition: return "os circle enter"
        case .visit: return "visit"
        }
    }
}

/// Refusals after the write get their own tokens so they're never logged as `no_change` or `deliver`.
enum PolygonUndeliveredReason {
    case outcome(PolygonMembershipOutcome)
    case userChanged
    case transitionNotRegistered

    var logToken: String {
        switch self {
        case .outcome(let outcome): return outcome.logToken
        case .userChanged: return "user_changed"
        case .transitionNotRegistered: return "transition_type_not_registered"
        }
    }
}

extension PolygonMembershipOutcome {
    /// snake_case like every other `why` in the module, not the camelCase case name.
    var logToken: String {
        switch self {
        case .deliver: return "deliver"
        case .discoveredInside: return "discovered_inside"
        case .suppressedNoChange: return "no_change"
        case .suppressedNewerDecision: return "newer_decision"
        case .suppressedInitialOutside: return "initial_outside"
        case .suppressedUnmonitored: return "unmonitored"
        case .suppressedGeometryChanged: return "geometry_changed"
        }
    }
}
