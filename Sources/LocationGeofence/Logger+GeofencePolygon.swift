import CioInternalCommon
import Foundation

private let geofenceTag = "Geofence"

// MARK: - Polygon membership

//
// iOS vocabulary, not a cross-SDK contract: only `polygon.undecided` shares a name with Android.

extension Logger {
    func geofencePolygonTransition(identifier: String, transition: GeofenceTransition, confirmedByFix: Bool) {
        let basis = confirmedByFix ? "a gated fix" : "the covering-circle exit"
        info(
            "Polygon \(transition.rawValue) for region \(identifier), confirmed by \(basis)"
                + geofenceTail("polygon.transition", .observation, [
                    ("id", identifier),
                    ("t", transition.rawValue),
                    ("by", confirmedByFix ? "fix" : "circle_exit")
                ]),
            geofenceTag
        )
    }

    func geofencePolygonPassSkipped(reason: PolygonPassSkipReason) {
        debug(
            "Skipped polygon evaluation pass: \(reason.prose)"
                + geofenceTail("polygon.pass.skipped", .observation, [("why", reason.rawValue)]),
            geofenceTag
        )
    }

    /// `n=0` means nothing was registered.
    func geofencePolygonPassStarted(
        reason: PolygonEvaluationReason,
        count: Int,
        pass: Int,
        heldFix: PolygonMembershipResolver.HeldFixUse = .none
    ) {
        debug(
            "Evaluating \(count) polygon(s) (\(reason.prose))"
                + geofenceTail("polygon.pass.started", .observation, [
                    ("why", reason.rawValue),
                    ("n", String(count)),
                    ("pass", String(pass)),
                    ("held", heldFix.rawValue)
                ]),
            geofenceTag
        )
    }

    func geofencePolygonEvaluationRequested(identifier: String, reason: PolygonEvaluationReason) {
        debug(
            "Re-evaluating polygon membership for region \(identifier) (\(reason.prose))"
                + geofenceTail("polygon.evaluation.requested", .observation, [
                    ("id", identifier),
                    ("why", reason.rawValue)
                ]),
            geofenceTag
        )
    }

    func geofencePolygonExceedsMonitoringLimit(identifier: String, radius: Double, limit: Double) {
        error(
            "Polygon \(identifier) dropped: covering circle \(Int(radius)) m exceeds the OS monitoring limit \(Int(limit)) m, and a clamped circle would no longer contain the polygon"
                + geofenceTail("registration.rejected", .observation, [
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
                + geofenceTail("polygon.wake.pass", .observation, [
                    ("rad", GeofenceLog.num(radius, 0)),
                    ("n", GeofenceLog.int(polygonCount))
                ]),
            geofenceTag
        )
    }

    /// `edge` is **positive inside** (as Android); circle records use the opposite sign. A verdict
    /// needs `|edge|` to exceed `acc`.
    func geofencePolygonVerdict(
        identifier: String,
        verdict: PolygonVerdict,
        horizontalAccuracy: Double,
        fixAge: TimeInterval
    ) {
        let membership = verdict.membership
        let signedEdgeDistance = verdict.signedEdgeDistance
        debug(
            "Polygon membership \(membership) for region \(identifier): edge \(Int(signedEdgeDistance)) m, accuracy \(Int(horizontalAccuracy)) m, fix age \(String(format: "%.1f", fixAge))s"
                + geofenceTail("polygon.verdict", .observation, [
                    ("id", identifier),
                    ("m", "\(membership)"),
                    ("edge", GeofenceLog.num(signedEdgeDistance, 0)),
                    ("acc", GeofenceLog.num(horizontalAccuracy)),
                    ("age", GeofenceLog.num(fixAge)),
                    // Two passes can interleave their verdicts.
                    ("pass", String(verdict.pass)),
                    // True only when a second fix agreed. Keep it a boolean: Android's contract
                    // pins it.
                    ("cor", verdict.corroboration.confirmed ? "true" : "false"),
                    // Only on an unconfirmed marginal arrival. Tokens describe the SECOND fix.
                    ("corwhy", verdict.corroboration.unconfirmedReason)
                ]),
            geofenceTag
        )
    }

    func geofencePolygonNotDelivered(identifier: String, reason: PolygonUndeliveredReason) {
        debug(
            "Polygon verdict for region \(identifier) delivered nothing: \(reason.logToken)"
                + geofenceTail("polygon.undelivered", .observation, [
                    ("id", identifier),
                    ("why", reason.logToken)
                ]),
            geofenceTag
        )
    }

    func geofenceWakeRadiusChosen(radius: Double, anchorIsLiveFix: Bool) {
        let basis = anchorIsLiveFix ? "a held fix" : "a stored anchor"
        debug(
            "Movement trigger sized to \(Int(radius)) m from \(basis)"
                + geofenceTail("movement.radius.chosen", .observation, [
                    ("rad", GeofenceLog.num(radius, 0)),
                    ("from", anchorIsLiveFix ? "fix" : "stored_anchor")
                ]),
            geofenceTag
        )
    }

    /// `pass` has no default on purpose; `nil` (outside any pass) logs `none`.
    func geofencePolygonUndecided(
        identifier: String,
        reason: PolygonUndecidedReason,
        signedEdgeDistance: Double? = nil,
        horizontalAccuracy: Double? = nil,
        pass: Int?
    ) {
        debug(
            "Polygon membership undecided for region \(identifier): \(reason.prose)"
                + geofenceTail("polygon.undecided", .observation, [
                    ("id", identifier),
                    ("why", reason.rawValue),
                    ("edge", GeofenceLog.num(signedEdgeDistance, 0)),
                    ("acc", GeofenceLog.num(horizontalAccuracy)),
                    ("pass", pass.map(String.init) ?? "none")
                ]),
            geofenceTag
        )
    }
}
