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

    /// A whole-set pass ran. The counterpart to `polygon.pass.skipped`, without which a pass that
    /// produced no verdicts is indistinguishable from one that never started — and `n=0` says the
    /// pass ran against nothing registered, which used to return in silence.
    ///
    /// Pass-level rather than one record per polygon: a long stationary capture is read by asking
    /// "did anything evaluate while I stood here", and N lines per pass buries that.
    /// `heldFix` records what became of a fix the caller supplied: reused, too old to stand in
    /// for a request, or replaced by a newer one this resolver already held. The difference between a re-evaluation that decides and one that records
    /// `no_usable_fix` for every polygon.
    func geofencePolygonPassStarted(
        reason: PolygonEvaluationReason,
        count: Int,
        pass: Int,
        heldFix: PolygonMembershipResolver.HeldFixUse = .none
    ) {
        debug(
            "Evaluating \(count) polygon(s) (\(reason.prose))"
                + geofenceTail("polygon.pass.started", .output, [
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
    /// `edge` is signed: **positive is inside**, the polygon convention set by
    /// `PolygonRegion.signedEdgeDistance` and fixed by the cross-SDK geometry fixtures. The circle
    /// records (`contradiction.allowed`) use the same key with the opposite sign, so a parser must
    /// read `edge` against the record's `ev`. `acc` is the ambiguity margin, not a quality score:
    /// a verdict holds while `|edge|` exceeds it. There is also a per-fence ceiling, and it gates
    /// verdicts of INSIDE only — a fix at or beyond `PolygonRegion.scale` decides nothing and is
    /// logged `accuracy_too_low`. A device clear of the ring by more than its own accuracy is
    /// outside however thin the venue is, so a departure is settled before the ceiling is read.
    /// A capture can still show `accuracy_too_low` beside a NEGATIVE edge: an outside-reading fix
    /// that is not clear by its own accuracy decides nothing either way, and once accuracy passes
    /// the venue scale that is the reason it carries instead of `within_accuracy`. No departure
    /// was blocked by the ceiling there.
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
                + geofenceTail("polygon.verdict", .output, [
                    ("id", identifier),
                    ("m", "\(membership)"),
                    ("edge", GeofenceLog.num(signedEdgeDistance, 0)),
                    ("acc", GeofenceLog.num(horizontalAccuracy)),
                    ("age", GeofenceLog.num(fixAge)),
                    // Ties this verdict to its `polygon.pass.started` row. A movement wake does
                    // not yield to an in-flight foreground pass, so two passes can interleave
                    // their verdicts and the pass-level record alone cannot attribute them.
                    ("pass", String(verdict.pass)),
                    // `cor` stays the shared cross-SDK boolean: true only when a second fix
                    // agreed. Widening it to reason tokens would silently break Android's pinned
                    // contract and every consumer reading it.
                    ("cor", verdict.corroboration.confirmed ? "true" : "false"),
                    // iOS-only and additive, absent unless it applies: WHY a marginal arrival
                    // committed without confirmation. Without it an unconfirmed arrival is
                    // indistinguishable in a capture from a decisive one, which is the whole
                    // difference this change introduced.
                    //
                    // Reuses `PolygonUndecidedReason` tokens on a record that DID decide, so read
                    // every one of them as being about the SECOND fix: `corwhy=no_usable_fix`
                    // means no usable second fix was obtained, not that the judged fix was bad.
                    ("corwhy", verdict.corroboration.unconfirmedReason)
                ]),
            geofenceTag
        )
    }

    func geofencePolygonNotDelivered(identifier: String, reason: PolygonUndeliveredReason) {
        debug(
            "Polygon verdict for region \(identifier) delivered nothing: \(reason.logToken)"
                + geofenceTail("polygon.undelivered", .output, [
                    ("id", identifier),
                    ("why", reason.logToken)
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
    ///
    /// `pass` has no default on purpose. A record that decided nothing is exactly the one a reader
    /// needs to tie to its pass, and the verdict line has carried `pass` while this one did not —
    /// so a pass announcing `n=4` and logging three verdicts read as a dropped polygon rather than
    /// an undecided one. `none` is written out for the sites that genuinely run outside any pass,
    /// so an absent attribution never has to be guessed at.
    func geofencePolygonUndecided(
        identifier: String,
        reason: PolygonUndecidedReason,
        signedEdgeDistance: Double? = nil,
        horizontalAccuracy: Double? = nil,
        pass: Int?
    ) {
        debug(
            "Polygon membership undecided for region \(identifier): \(reason.prose)"
                + geofenceTail("polygon.undecided", .output, [
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
