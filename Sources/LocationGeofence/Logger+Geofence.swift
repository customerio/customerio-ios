import CioInternalCommon
import CoreLocation
import Foundation

private let geofenceTag = "Geofence"

/// Why a sync did not run.
///
/// Carries both the prose and a stable token so the human-readable message stays byte-identical to
/// what it was before enrichment while `why=` gives a script something that will not change when
/// someone rewords the sentence.
enum GeofenceSyncSkipReason: String {
    case refreshInProgress = "refresh_in_progress"
    case noIdentifiedUser = "no_identified_user"
    case noLastSyncAnchor = "no_last_sync_anchor"
    case restoreInProgress = "restore_in_progress"
    case userChangedDuringBootstrap = "user_changed_during_bootstrap"

    var prose: String {
        switch self {
        case .refreshInProgress: return "refresh already in progress"
        case .noIdentifiedUser: return "no identified user"
        case .noLastSyncAnchor: return "no last-sync anchor to restore from"
        case .restoreInProgress: return "restore already in progress"
        case .userChangedDuringBootstrap: return "identified user changed during bootstrap"
        }
    }
}

/// How the SDK came to be running.
///
/// Nothing marks a cold background wake today, which makes it impossible to tell "the SDK was
/// never running" apart from "the SDK ran and decided not to act" when reading a drive afterwards.
enum GeofenceLaunchReason: String {
    case appStart = "app_start"
    case locationEvent = "location_event"
}

extension Logger {
    // MARK: - Event tracking

    func geofenceEventTracked(geofenceId: String, transition: GeofenceTransition) {
        debug(
            "Tracked \(transition.rawValue) event for geofence \(geofenceId)"
                + geofenceTail("transition.emitted", .output, [
                    ("id", geofenceId),
                    ("t", transition.rawValue)
                ]),
            geofenceTag
        )
    }

    func geofenceEventSuppressed(geofenceId: String, transition: GeofenceTransition, cooldownRemaining: TimeInterval? = nil) {
        debug(
            "Suppressed duplicate \(transition.rawValue) event for geofence \(geofenceId), within cooldown"
                + geofenceTail("transition.suppressed", .output, [
                    ("id", geofenceId),
                    ("t", transition.rawValue),
                    ("why", "cooldown"),
                    ("cd", GeofenceLog.num(cooldownRemaining))
                ]),
            geofenceTag
        )
    }

    func geofenceTransitionDroppedAnonymous(geofenceId: String, transition: GeofenceTransition) {
        debug(
            "Dropped \(transition.rawValue) event for geofence \(geofenceId): no identified user at transition time (geofencing is identified-only)"
                + geofenceTail("transition.dropped", .output, [
                    ("id", geofenceId),
                    ("t", transition.rawValue),
                    ("why", "no_identified_user")
                ]),
            geofenceTag
        )
    }

    func geofencePendingPersistFailed(geofenceId: String, transition: GeofenceTransition) {
        error(
            "Failed to persist \(transition.rawValue) event for geofence \(geofenceId) before send; cooldown released so the next crossing can retry"
                + geofenceTail("storage.write.failed", .output, [
                    ("id", geofenceId),
                    ("t", transition.rawValue),
                    ("ok", GeofenceLog.bool(false))
                ]),
            geofenceTag,
            nil
        )
    }

    // MARK: - Sync

    func geofenceSyncSkipped(reason: GeofenceSyncSkipReason) {
        debug(
            "Sync skipped: \(reason.prose)"
                + geofenceTail("sync.skipped", .output, [("why", reason.rawValue)]),
            geofenceTag
        )
    }

    func geofenceSyncSkippedFresh() {
        debug(
            "Sync skipped: last server fetch is within freshness window"
                + geofenceTail("sync.skipped", .output, [("why", "within_freshness_window")]),
            geofenceTag
        )
    }

    func geofenceSyncFetchFailed(error: GeofenceApiError) {
        self.error(
            "Sync fetch failed: \(error)"
                + geofenceTail("api.fetch.result", .input, [
                    ("ok", GeofenceLog.bool(false)),
                    ("why", error.diagnosticToken)
                ]),
            geofenceTag,
            nil
        )
    }

    /// Outcome of a nearby-geofence fetch. Classified as an **input**: replay feeds the response
    /// back rather than re-issuing the request.
    func geofenceApiFetchResult(returnedCount: Int, elapsed: TimeInterval?) {
        debug(
            "Fetched \(returnedCount) nearby geofence(s) from the server"
                + geofenceTail("api.fetch.result", .input, [
                    ("ok", GeofenceLog.bool(true)),
                    ("n", GeofenceLog.int(returnedCount)),
                    ("ms", GeofenceLog.num(elapsed.map { $0 * 1000 }, 0))
                ]),
            geofenceTag
        )
    }

    /// Prose reports what was *requested* and reads exactly as it did before this instrumentation
    /// — its else-branch states a config fact, so driving it from an OS outcome made it assert
    /// "max business geofences is 0" whenever the trigger was merely rejected. The tail reports
    /// what the OS *accepted*; the two differing is the thing worth seeing.
    func geofenceSyncCompleted(
        requestedCount: Int,
        movementTriggerRequested: Bool,
        acceptedCount: Int,
        movementTriggerAccepted: Bool,
        elapsed: TimeInterval? = nil
    ) {
        let trigger = movementTriggerRequested
            ? " + 1 movement trigger"
            : "; monitoring disabled (max business geofences is 0)"
        info(
            "Sync completed: registered \(requestedCount) business geofences\(trigger)"
                + geofenceTail("sync.completed", .output, [
                    ("n", GeofenceLog.int(acceptedCount)),
                    ("mvmt", GeofenceLog.bool(movementTriggerAccepted)),
                    ("ms", GeofenceLog.num(elapsed.map { $0 * 1000 }, 0))
                ]),
            geofenceTag
        )
    }

    /// The change, distinct from `registration.applied`, which reports the resulting set. Sharing
    /// one `ev` between them makes either uncountable.
    func geofenceRegistrationDiff(added: Int, removed: Int, unchanged: Int) {
        debug(
            "OS registration diff: +\(added) / -\(removed); \(unchanged) left registered untouched"
                + geofenceTail("registration.diff", .output, [
                    ("nadd", GeofenceLog.int(added)),
                    ("nrem", GeofenceLog.int(removed)),
                    ("nkeep", GeofenceLog.int(unchanged))
                ]),
            geofenceTag
        )
    }

    /// The 19-of-N selection, which happens silently today.
    ///
    /// Without this, a geofence that was never registered because it ranked 20th is
    /// indistinguishable from one that was registered and simply never fired.
    /// `selected`, `evicted` and `edgeDistances` are autoclosures: building them means a distance
    /// computation per region and a filter over every candidate, on a background wake path, and
    /// none of it is wanted unless the tail will carry it.
    func geofenceRankEvaluated(
        candidates: Int,
        selectedCount: Int,
        selected: @autoclosure () -> [String],
        evicted: @autoclosure () -> [String],
        edgeDistances: @autoclosure () -> [String: Double]
    ) {
        debug(
            "Ranked \(candidates) candidate(s), selected \(selectedCount)"
                + geofenceTail("rank.evaluated", .output, {
                    let distances = edgeDistances()
                    let ranked = selected().map { id -> String in
                        guard let edge = distances[id] else { return GeofenceLog.sanitize(id) }
                        return "\(GeofenceLog.sanitize(id)):\(Int(edge))"
                    }
                    return [
                        ("ncand", GeofenceLog.int(candidates)),
                        ("n", GeofenceLog.int(selectedCount)),
                        ("ranked", GeofenceLog.composedList(ranked)),
                        ("evicted", GeofenceLog.list(evicted()))
                    ]
                }()),
            geofenceTag
        )
    }

    // MARK: - Movement trigger

    func geofenceMovementTrigger(tier: HandleMovementTier) {
        debug(
            "Movement trigger EXIT: \(tier.rawValue)"
                + geofenceTail("movement.exit", .input, [("tier", tier.rawValue)]),
            geofenceTag
        )
    }

    /// The re-centred bubble's own geometry. Region geometry is ungated — it is workspace
    /// configuration, not user data — but this one is derived from the device's position, so it
    /// travels with the same switch as a coordinate.
    func geofenceMovementTriggerRegistered(latitude: Double, longitude: Double, radius: Double) {
        let geometry: [(String, String?)] = [
            ("rlat", GeofenceLog.num(latitude, 5)),
            ("rlon", GeofenceLog.num(longitude, 5))
        ]
        debug(
            "Movement trigger registered with radius \(Int(radius)) m"
                + geofenceTail("movement.registered", .output, geometry + [("rad", GeofenceLog.num(radius, 0))]),
            geofenceTag
        )
    }

    func geofenceMovementRearmedAfterFailedRefresh() {
        debug(
            "Movement refresh failed; re-ranking from cache to re-arm the movement trigger"
                + geofenceTail("movement.rearmed", .output, [("why", "refresh_failed")]),
            geofenceTag
        )
    }

    func geofenceMovementFixResolved(ageSeconds: TimeInterval, requested: Bool) {
        let source = requested ? "freshly requested" : "cached"
        debug(
            "Movement pass using \(source) fix, age \(String(format: "%.1f", ageSeconds))s"
                + geofenceTail("movement.fix.resolved", .input, [
                    ("age", GeofenceLog.num(ageSeconds)),
                    ("prov", requested ? "requested" : "cached")
                ]),
            geofenceTag
        )
    }

    func geofenceMovementFixStale(ageSeconds: TimeInterval?) {
        let age = ageSeconds.map { "\(String(format: "%.1f", $0))s old" } ?? "missing"
        info(
            "Cached fix is \(age); requesting a fresh fix for the movement pass"
                + geofenceTail("movement.fix.requested", .output, [
                    ("age", GeofenceLog.num(ageSeconds)),
                    ("why", ageSeconds == nil ? "no_cached_fix" : "stale_cached_fix")
                ]),
            geofenceTag
        )
    }

    func geofenceMovementFixRequestFailed(fallingBackToCached: Bool, elapsed: TimeInterval? = nil) {
        let outcome = fallingBackToCached ? "falling back to the stale cached fix" : "no cached fix to fall back to"
        info(
            "Fresh-fix request failed or timed out; \(outcome)"
                + geofenceTail("movement.fix.failed", .input, [
                    ("ok", GeofenceLog.bool(false)),
                    ("why", fallingBackToCached ? "fallback_cached" : "no_fallback"),
                    ("ms", GeofenceLog.num(elapsed.map { $0 * 1000 }, 0))
                ]),
            geofenceTag
        )
    }

    // MARK: - Baseline healing and contradiction

    func geofenceBaselineHealed(identifier: String, transition: GeofenceTransition) {
        info(
            "Synthesized \(transition.rawValue) for region \(identifier): fresh fix contradicts stored baseline (OS never delivered the crossing)"
                + geofenceTail("baseline.healed", .output, [
                    ("id", identifier),
                    ("t", transition.rawValue)
                ]),
            geofenceTag
        )
    }

    func geofenceEventRefusedByContradiction(identifier: String, transition: GeofenceTransition, distanceFromCenter: Double, radius: Double, accuracy: Double) {
        info(
            "Refused OS \(transition.rawValue) for region \(identifier): a fresh fix contradicts it (distance \(Int(distanceFromCenter)) m, radius \(Int(radius)) m, accuracy \(Int(accuracy)) m)"
                + geofenceTail("contradiction.refused", .output, [
                    ("id", identifier),
                    ("t", transition.rawValue),
                    ("dist", GeofenceLog.num(distanceFromCenter, 0)),
                    ("rad", GeofenceLog.num(radius, 0)),
                    ("edge", GeofenceLog.num(max(0, distanceFromCenter - radius), 0)),
                    ("acc", GeofenceLog.num(accuracy))
                ]),
            geofenceTag
        )
    }

    // MARK: - Module state

    func geofenceSyncSupersededByUserChange() {
        info(
            "Sync result discarded: identified user changed during fetch"
                + geofenceTail("sync.superseded", .output, [("why", "user_changed")]),
            geofenceTag
        )
    }

    func geofenceResetCompleted() {
        info(
            "Reset completed: monitoring stopped and user-scoped state cleared"
                + geofenceTail("module.reset", .output, [("ok", GeofenceLog.bool(true))]),
            geofenceTag
        )
    }

    func geofenceResetSuperseded() {
        debug(
            "Reset skipped: another user is signed in"
                + geofenceTail("module.reset", .output, [
                    ("ok", GeofenceLog.bool(false)),
                    ("why", "other_user_signed_in")
                ]),
            geofenceTag
        )
    }

    func geofenceFirstRunRearm() {
        debug(
            "First-run refresh re-armed by new location fix"
                + geofenceTail("movement.rearmed", .output, [("why", "first_run")]),
            geofenceTag
        )
    }

    func geofenceRegionsAdopted(count: Int) {
        debug(
            "Adopted \(count) OS-persisted region(s) on launch; re-armed in place"
                + geofenceTail("registration.adopted", .output, [("n", GeofenceLog.int(count))]),
            geofenceTag
        )
    }

    func geofenceForegroundRearm(count: Int) {
        info(
            "Foreground entry after long suspension: re-armed \(count) condition(s) in place"
                + geofenceTail("registration.rearmed", .output, [
                    ("n", GeofenceLog.int(count)),
                    ("why", "foreground_after_suspension")
                ]),
            geofenceTag
        )
    }
}
