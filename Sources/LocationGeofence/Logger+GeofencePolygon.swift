import CioInternalCommon
import Foundation

private let geofenceTag = "Geofence"

// MARK: - Polygon membership

//
// What the SDK concluded about a polygon. The OS only reports the covering circle, so every record
// here is a verdict the SDK reached itself.
//
// iOS vocabulary, not a cross-SDK contract: Android's `polygon.*` records use different keys
// (only `polygon.undecided` shares a name).

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

    /// A whole-set pass declined, e.g. because one is already running.
    func geofencePolygonPassSkipped(reason: PolygonPassSkipReason) {
        debug(
            "Skipped polygon evaluation pass: \(reason.prose)"
                + geofenceTail("polygon.pass.skipped", .observation, [("why", reason.rawValue)]),
            geofenceTag
        )
    }

    /// A whole-set pass ran; `n=0` means nothing was registered. One record per pass, not per
    /// polygon, so a long stationary capture stays readable.
    ///
    /// `heldFix` records what became of a fix the caller supplied: reused, too old, or replaced
    /// by a newer one the resolver already held.
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

    /// Logged on every decisive evaluation, delivered or not: the commonest outcome (decisively
    /// outside, belief unchanged) writes nothing else, and would look like a dead evaluator.
    ///
    /// `edge` is signed, **positive inside** (`PolygonRegion.signedEdgeDistance`, same as Android).
    /// Circle records use the opposite sign, so read `edge` against the record's `ev`. `acc` is the
    /// ambiguity margin: a verdict needs `|edge|` to exceed it.
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
                    // Ties this verdict to its `polygon.pass.started` row: two passes can
                    // interleave their verdicts.
                    ("pass", String(verdict.pass)),
                    // Shared cross-SDK boolean: true only when a second fix agreed. Keep it a
                    // boolean; Android's contract pins it.
                    ("cor", verdict.corroboration.confirmed ? "true" : "false"),
                    // iOS-only, present only when a marginal arrival committed without
                    // confirmation. The `PolygonUndecidedReason` tokens here describe the SECOND
                    // fix: `corwhy=no_usable_fix` means no usable second fix was obtained.
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

    /// Which radius the movement trigger was armed with and why. Read with the resolver's fix-age
    /// line just before it to judge whether a re-arm was warranted.
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

    /// `edge` and `acc` ride as their own keys so `why` stays a token.
    ///
    /// `pass` has no default so every call site attributes the record; sites outside any pass
    /// pass `nil`, logged as `none`.
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
