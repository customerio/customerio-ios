import CioInternalCommon
import Foundation

private let geofenceTag = "Geofence"

// MARK: - Polygon membership

//
// What the SDK concluded about a polygon, as opposed to what the OS handed it: the OS only ever
// reports the covering circle, so every record here describes a verdict this SDK reached itself.
//
// These still emit prose only. Bringing them onto the `geofenceTail` convention the rest of the
// geofence records now use, and giving `GeofenceLogTail` polygon coverage, is its own ticket —
// doing it inside the main merge would have mixed a rewrite into a conflict resolution.

extension Logger {
    func geofencePolygonTransition(identifier: String, transition: GeofenceTransition, confirmedByFix: Bool) {
        let basis = confirmedByFix ? "a gated fix" : "the covering-circle exit"
        info("Polygon \(transition.rawValue) for region \(identifier), confirmed by \(basis)", geofenceTag)
    }

    /// A whole-set pass declined because one is already running. Logged so a foreground that
    /// produced no verdicts is distinguishable from one that never ran.
    func geofencePolygonPassSkipped(reason: String) {
        debug("Skipped polygon evaluation pass: \(reason)", geofenceTag)
    }

    func geofencePolygonEvaluationRequested(identifier: String, reason: String) {
        debug("Re-evaluating polygon membership for region \(identifier) (\(reason))", geofenceTag)
    }

    func geofencePolygonExceedsMonitoringLimit(identifier: String, radius: Double, limit: Double) {
        error("Polygon \(identifier) dropped: covering circle \(Int(radius)) m exceeds the OS monitoring limit \(Int(limit)) m, and a clamped circle would no longer contain the polygon", geofenceTag, nil)
    }

    func geofencePolygonWakePass(radius: Double, polygonCount: Int) {
        debug("Polygon wake pass: re-armed at \(Int(radius)) m, re-evaluating \(polygonCount) polygon(s)", geofenceTag)
    }

    /// Logged on every decisive evaluation, delivered or not: without it the commonest outcome —
    /// decisively outside, belief unchanged — writes nothing, and a correct silence is
    /// indistinguishable from an evaluator that never ran.
    func geofencePolygonVerdict(identifier: String, membership: PolygonMembership, signedEdgeDistance: Double, horizontalAccuracy: Double, fixAge: TimeInterval) {
        debug("Polygon membership \(membership) for region \(identifier): edge \(Int(signedEdgeDistance)) m, accuracy \(Int(horizontalAccuracy)) m, fix age \(String(format: "%.1f", fixAge))s", geofenceTag)
    }

    func geofencePolygonNotDelivered(identifier: String, outcome: String) {
        debug("Polygon verdict for region \(identifier) delivered nothing: \(outcome)", geofenceTag)
    }

    /// Which radius the movement trigger was armed with and why. Pairs with the fix-age line the
    /// resolver logs just before it: together they say whether a re-arm was warranted.
    func geofenceWakeRadiusChosen(radius: Double, anchorIsLiveFix: Bool) {
        let basis = anchorIsLiveFix ? "a held fix" : "a stored anchor"
        debug("Movement trigger sized to \(Int(radius)) m from \(basis)", geofenceTag)
    }

    func geofencePolygonUndecided(identifier: String, reason: String) {
        debug("Polygon membership undecided for region \(identifier): \(reason)", geofenceTag)
    }
}
