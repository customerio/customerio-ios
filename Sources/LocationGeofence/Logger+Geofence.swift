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
    /// Not "the workspace has no fences": every region was unreadable, so the response is treated
    /// as a fetch failure and the cache survives. The tail is what tells those two apart on replay.
    func geofenceAllRegionsDropped(count: Int) {
        error(
            "All \(count) region(s) in the response were unusable — treating as a fetch failure so the cache survives"
                + geofenceTail("api.fetch.unreadable", .input, [
                    ("ok", GeofenceLog.bool(false)),
                    ("n", GeofenceLog.int(count)),
                    ("why", "all_regions_unusable")
                ]),
            geofenceTag,
            nil
        )
    }

    // MARK: - Event tracking

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

    /// The crossing was given up because the pending queue could not be READ, so nothing was
    /// written and nothing failed to write. Deliberately not `storage.write.failed`: that record
    /// is `io=out` and says a write was attempted, and reporting a refusal as a failed write is
    /// the collapse the queue's own read/write split exists to prevent.
    ///
    /// Says no write was ATTEMPTED rather than that the queue was left intact: the same refusal
    /// arises when the file's location cannot be resolved, where there is no queue to leave.
    ///
    /// Logged at `error` while the sibling anonymous drop logs at `debug` — one is an anomaly, the
    /// other routine — so `transition.dropped` spans two levels. Anything filtering by level
    /// before parsing the tail sees only part of the family.
    func geofenceTransitionDroppedQueueUnreadable(geofenceId: String, transition: GeofenceTransition) {
        error(
            "Dropped \(transition.rawValue) for geofence \(geofenceId): the pending queue could not be read, so no write was attempted; cooldown released so the next crossing can retry"
                + geofenceTail("transition.dropped", .output, [
                    ("id", geofenceId),
                    ("t", transition.rawValue),
                    ("why", "queue_unreadable")
                ]),
            geofenceTag,
            nil
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
    func geofenceApiFetchResult(
        returnedCount: Int,
        elapsed: TimeInterval?,
        regions: [GeofenceApiRegion] = []
    ) {
        debug(
            "Fetched \(returnedCount) nearby geofence(s) from the server"
                + geofenceTail("api.fetch.result", .input, [
                    ("ok", GeofenceLog.bool(true)),
                    ("n", GeofenceLog.int(returnedCount)),
                    ("ms", GeofenceLog.num(elapsed.map { $0 * 1000 }, 0))
                ]),
            geofenceTag
        )
        geofenceFenceCatalog(regions)
    }

    /// One record per fetched fence, describing the circle the server sent.
    ///
    /// Without it a capture names fences only by opaque id: a replay cannot place them, and nobody
    /// reading the log can tell which geoset a crossing belonged to. Re-fetching the geometry from
    /// the workspace later is not equivalent — fences move, so a drive replayed months on would
    /// silently run against today's circles, and a capture from a customer has no workspace to ask.
    ///
    /// Gated whole rather than gated-tail: these records carry no prose worth emitting on their
    /// own, so with diagnostics off they must not exist at all.
    private func geofenceFenceCatalog(_ regions: [GeofenceApiRegion]) {
        guard !regions.isEmpty, GeofenceDiagnostics.isEnabled else { return }
        for region in regions {
            debug(
                "Geofence '\(region.id)' catalogued"
                    + geofenceTail("fence.cataloged", .input, [
                        ("id", region.id),
                        // Sanitized like any other value: a workspace-authored name can contain
                        // spaces, commas and `=`, all of which would break the parser's split.
                        ("name", region.name),
                        ("gs", GeofenceLog.list(region.geosetIds ?? [])),
                        ("sh", region.catalogShape.rawValue),
                        // A polygon has no lat/lon/radius on the wire; these fall back to its
                        // enclosing circle, which is the circle the OS monitors.
                        ("lat", GeofenceLog.num(region.catalogCenter?.latitude, 5)),
                        ("lon", GeofenceLog.num(region.catalogCenter?.longitude, 5)),
                        ("rad", GeofenceLog.num(region.catalogRadius, 0)),
                        // `nv` is authoritative: `ring` truncates, so it is for placement only and
                        // never a membership input.
                        ("nv", GeofenceLog.int(region.catalogRing?.count)),
                        ("ring", GeofenceLog.list(region.catalogRing ?? [], limit: 64)),
                        ("tt", GeofenceLog.list(region.transitionTypes ?? []))
                    ]),
                geofenceTag
            )
        }
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

    /// The event survived the contradiction gate and the monitor's dedup baseline and is being
    /// handed to the consumer.
    ///
    /// Not a duplicate of `os.callback.received`, which fires earlier for EVERY delivered event:
    /// the difference between the two is what the gate and the dedup discarded. For a polygon the
    /// `polygon.*` records cover the same span, but for a circle fence nothing else does — the
    /// next record is `transition.accepted`, after the cooldown, so without this a crossing killed
    /// at the monitor looks like one the OS never delivered.
    func geofenceCallbackDispatched(identifier: String, transition: GeofenceTransition) {
        debug(
            "OS delivered \(transition.rawValue) for region \(identifier)"
                + geofenceTail("os.callback.dispatched", .output, [
                    ("id", identifier),
                    ("t", transition.rawValue)
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
