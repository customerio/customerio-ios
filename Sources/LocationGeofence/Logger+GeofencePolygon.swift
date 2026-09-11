import CioInternalCommon
import Foundation

private let geofenceTag = "Geofence"

// MARK: - Polygon membership

//
// What the SDK concluded about a polygon, as opposed to what the OS handed it. The OS only ever
// reports the covering circle, so every record here describes a verdict this SDK reached itself —
// which is why `polygon.verdict` is emitted even when nothing is delivered: decisively-outside is
// the commonest outcome and writes nothing else, so a correct silence and a dead evaluator look
// identical without it.
//
// iOS-only. Android's polygon runtime is gated off, so there is nothing on that side to match yet.

extension Logger {
    func geofencePolygonTransition(identifier: String, transition: GeofenceTransition, confirmedByFix: Bool) {
        let basis = confirmedByFix ? "a gated fix" : "the covering-circle exit"
        info(
            "Polygon \(transition.rawValue) for region \(identifier), confirmed by \(basis)"
                + geofenceTail("polygon.transition", .output, [
                    ("id", identifier),
                    ("t", transition.rawValue),
                    ("by", confirmedByFix ? "fix" : "circle_exit")
                ]),
            geofenceTag
        )
    }

    /// A whole-set pass declined because one is already running. Logged so a foreground that
    /// produced no verdicts is distinguishable from one that never ran.
    func geofencePolygonPassSkipped(reason: PolygonPassSkipReason) {
        debug(
            "Skipped polygon evaluation pass: \(reason.prose)"
                + geofenceTail("polygon.pass.skipped", .output, [("why", reason.rawValue)]),
            geofenceTag
        )
    }

    func geofencePolygonEvaluationRequested(identifier: String, reason: PolygonEvaluationReason) {
        debug(
            "Re-evaluating polygon membership for region \(identifier) (\(reason.prose))"
                + geofenceTail("polygon.evaluation.requested", .output, [
                    ("id", identifier),
                    ("why", reason.rawValue)
                ]),
            geofenceTag
        )
    }

    func geofencePolygonExceedsMonitoringLimit(identifier: String, radius: Double, limit: Double) {
        error(
            "Polygon \(identifier) dropped: covering circle \(Int(radius)) m exceeds the OS monitoring limit \(Int(limit)) m, and a clamped circle would no longer contain the polygon"
                + geofenceTail("registration.rejected", .output, [
                    ("id", identifier),
                    ("why", "over_os_limit"),
                    ("rad", GeofenceLog.num(radius, 0)),
                    ("lim", GeofenceLog.num(limit, 0))
                ]),
            geofenceTag,
            nil
        )
    }

    func geofencePolygonWakePass(radius: Double, polygonCount: Int) {
        debug(
            "Polygon wake pass: re-armed at \(Int(radius)) m, re-evaluating \(polygonCount) polygon(s)"
                + geofenceTail("polygon.wake.pass", .output, [
                    ("rad", GeofenceLog.num(radius, 0)),
                    ("n", GeofenceLog.int(polygonCount))
                ]),
            geofenceTag
        )
    }

    /// Logged on every decisive evaluation, delivered or not: without it the commonest outcome —
    /// decisively outside, belief unchanged — writes nothing, and a correct silence is
    /// indistinguishable from an evaluator that never ran.
    ///
    /// `edge` is signed: negative is inside. `acc` is the ambiguity margin, not a quality score —
    /// iOS has no accuracy ceiling, so a verdict holds only while `|edge|` exceeds it.
    func geofencePolygonVerdict(identifier: String, membership: PolygonMembership, signedEdgeDistance: Double, horizontalAccuracy: Double, fixAge: TimeInterval) {
        debug(
            "Polygon membership \(membership) for region \(identifier): edge \(Int(signedEdgeDistance)) m, accuracy \(Int(horizontalAccuracy)) m, fix age \(String(format: "%.1f", fixAge))s"
                + geofenceTail("polygon.verdict", .output, [
                    ("id", identifier),
                    ("m", "\(membership)"),
                    ("edge", GeofenceLog.num(signedEdgeDistance, 0)),
                    ("acc", GeofenceLog.num(horizontalAccuracy)),
                    ("age", GeofenceLog.num(fixAge))
                ]),
            geofenceTag
        )
    }

    func geofencePolygonNotDelivered(identifier: String, outcome: PolygonMembershipOutcome) {
        debug(
            "Polygon verdict for region \(identifier) delivered nothing: \(outcome.logToken)"
                + geofenceTail("polygon.undelivered", .output, [
                    ("id", identifier),
                    ("why", outcome.logToken)
                ]),
            geofenceTag
        )
    }

    /// Which radius the movement trigger was armed with and why. Pairs with the fix-age line the
    /// resolver logs just before it: together they say whether a re-arm was warranted.
    func geofenceWakeRadiusChosen(radius: Double, anchorIsLiveFix: Bool) {
        let basis = anchorIsLiveFix ? "a held fix" : "a stored anchor"
        debug(
            "Movement trigger sized to \(Int(radius)) m from \(basis)"
                + geofenceTail("movement.radius.chosen", .output, [
                    ("rad", GeofenceLog.num(radius, 0)),
                    ("from", anchorIsLiveFix ? "fix" : "stored_anchor")
                ]),
            geofenceTag
        )
    }

    /// `edge` and `acc` ride as their own keys rather than inside `why`: putting the two
    /// measurements in the token gave every record a unique one, which is no token at all.
    func geofencePolygonUndecided(
        identifier: String,
        reason: PolygonUndecidedReason,
        signedEdgeDistance: Double? = nil,
        horizontalAccuracy: Double? = nil
    ) {
        debug(
            "Polygon membership undecided for region \(identifier): \(reason.prose)"
                + geofenceTail("polygon.undecided", .output, [
                    ("id", identifier),
                    ("why", reason.rawValue),
                    ("edge", GeofenceLog.num(signedEdgeDistance, 0)),
                    ("acc", GeofenceLog.num(horizontalAccuracy))
                ]),
            geofenceTag
        )
    }
}
