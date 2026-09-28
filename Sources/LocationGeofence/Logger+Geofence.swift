import CioInternalCommon
import CoreLocation
import Foundation

private let geofenceTag = "Geofence"

/// Why a sync did not run. `prose` is for humans; the raw value is the stable `why=` token.
enum GeofenceSyncSkipReason: String, CaseIterable {
    case refreshInProgress = "refresh_in_progress"
    case noIdentifiedUser = "no_identified_user"
    case noLastSyncAnchor = "no_last_sync_anchor"
    case restoreInProgress = "restore_in_progress"
    case userChangedDuringBootstrap = "user_changed_during_bootstrap"
    case movementOvertaken = "movement_overtaken"

    var prose: String {
        switch self {
        case .refreshInProgress: return "refresh already in progress"
        case .noIdentifiedUser: return "no identified user"
        case .noLastSyncAnchor: return "no last-sync anchor to restore from"
        case .restoreInProgress: return "restore already in progress"
        case .userChangedDuringBootstrap: return "identified user changed during bootstrap"
        case .movementOvertaken: return "a newer movement already re-centred the trigger"
        }
    }
}

/// How the SDK came to be running. Separates "never running" from "ran and chose not to act".
enum GeofenceLaunchReason: String, CaseIterable {
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
                + geofenceTail("transition.suppressed", .observation, [
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
                + geofenceTail("transition.dropped", .observation, [
                    ("id", geofenceId),
                    ("t", transition.rawValue),
                    ("why", "no_identified_user")
                ]),
            geofenceTag
        )
    }

    /// The pending queue could not be READ, so no write was attempted. Not `storage.write.failed`,
    /// which says a write was tried. The same refusal covers an unresolvable file location.
    ///
    /// Logged at `error` while the anonymous drop logs at `debug`, so `transition.dropped` spans
    /// two levels; a level filter sees only part of the family.
    func geofenceTransitionDroppedQueueUnreadable(geofenceId: String, transition: GeofenceTransition) {
        error(
            "Dropped \(transition.rawValue) for geofence \(geofenceId): the pending queue could not be read, so no write was attempted; cooldown released so the next crossing can retry"
                + geofenceTail("transition.dropped", .observation, [
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
                + geofenceTail("storage.write.failed", .observation, [
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
                + geofenceTail("sync.skipped", .observation, [("why", reason.rawValue)]),
            geofenceTag
        )
    }

    func geofenceSyncSkippedFresh() {
        debug(
            "Sync skipped: last server fetch is within freshness window"
                + geofenceTail("sync.skipped", .observation, [("why", "within_freshness_window")]),
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

    /// An **input**: replay feeds the response back rather than re-issuing the request.
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

    /// One record per fetched fence, with its geometry, so a replay can place fences as they were
    /// at capture time (fences move, and a customer capture has no workspace to re-fetch from).
    ///
    /// Gated whole: the prose alone is worthless.
    private func geofenceFenceCatalog(_ regions: [GeofenceApiRegion]) {
        guard !regions.isEmpty, GeofenceDiagnostics.isEnabled else { return }
        for region in regions {
            debug(
                "Geofence '\(region.id)' catalogued"
                    + geofenceTail("fence.cataloged", .input, [
                        ("id", region.id),
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

    /// The prose reports what was *requested* (its else-branch states a config fact); the tail
    /// reports what the OS *accepted*. A difference between them is the signal.
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
                + geofenceTail("sync.completed", .observation, [
                    ("n", GeofenceLog.int(acceptedCount)),
                    ("mvmt", GeofenceLog.bool(movementTriggerAccepted)),
                    ("ms", GeofenceLog.num(elapsed.map { $0 * 1000 }, 0))
                ]),
            geofenceTag
        )
    }

    /// The change; `registration.applied` reports the resulting set.
    func geofenceRegistrationDiff(added: Int, removed: Int, unchanged: Int) {
        debug(
            "OS registration diff: +\(added) / -\(removed); \(unchanged) left registered untouched"
                + geofenceTail("registration.diff", .observation, [
                    ("nadd", GeofenceLog.int(added)),
                    ("nrem", GeofenceLog.int(removed)),
                    ("nkeep", GeofenceLog.int(unchanged))
                ]),
            geofenceTag
        )
    }

    /// The top-N selection, so a geofence that ranked out is distinguishable from one that was
    /// registered and never fired. The lists are autoclosures: building them costs a distance per
    /// region on a background wake path, wasted unless the tail is on.
    func geofenceRankEvaluated(
        candidates: Int,
        selectedCount: Int,
        selected: @autoclosure () -> [String],
        evicted: @autoclosure () -> [String],
        edgeDistances: @autoclosure () -> [String: Double]
    ) {
        debug(
            "Ranked \(candidates) candidate(s), selected \(selectedCount)"
                + geofenceTail("rank.evaluated", .observation, {
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

    /// The event survived the contradiction gate and the dedup baseline and is being handed to the
    /// consumer. `os.callback.received` fires for EVERY delivered event; the difference between the
    /// two is what the monitor discarded.
    func geofenceCallbackDispatched(identifier: String, transition: GeofenceTransition) {
        debug(
            "OS delivered \(transition.rawValue) for region \(identifier)"
                + geofenceTail("os.callback.dispatched", .observation, [
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
                + geofenceTail("sync.superseded", .observation, [("why", "user_changed")]),
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

    /// Same `ev` as `geofenceResetCompleted`: a reset that deliberately did not clear.
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
                + geofenceTail("movement.rearmed", .observation, [("why", "first_run")]),
            geofenceTag
        )
    }

    /// Which OS-persisted conditions this process claimed on launch. An observation, not the final
    /// set: on CLMonitor the re-arm skips conditions whose geometry changed, and its
    /// `registration.applied` is authoritative.
    func geofenceRegionsAdopted(identifiers: [String]) {
        debug(
            "Adopted \(identifiers.count) OS-persisted region(s) on launch; re-arming in place"
                + geofenceTail("registration.adopted", .observation, [
                    ("n", GeofenceLog.int(identifiers.count)),
                    ("ids", GeofenceLog.list(identifiers.sorted()))
                ]),
            geofenceTag
        )
    }

    func geofenceForegroundRearm(count: Int) {
        info(
            "Foreground entry after long suspension: re-armed \(count) condition(s) in place"
                + geofenceTail("registration.rearmed", .observation, [
                    ("n", GeofenceLog.int(count)),
                    ("why", "foreground_after_suspension")
                ]),
            geofenceTag
        )
    }
}
