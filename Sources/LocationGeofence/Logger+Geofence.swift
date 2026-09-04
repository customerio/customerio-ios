import CioInternalCommon
import CoreLocation
import Foundation

private let geofenceTag = "Geofence"

extension Logger {
    func geofenceInvalidRegionDropped(_ identifier: String, reason: GeofenceRegionDropReason) {
        error(
            "Geofence '\(identifier)' dropped — \(reason.rawValue), not registerable with the OS",
            geofenceTag,
            nil
        )
    }

    func geofenceAllRegionsDropped(count: Int) {
        error(
            "All \(count) region(s) in the response were unusable — treating as a fetch failure so the cache survives",
            geofenceTag,
            nil
        )
    }

    func geofenceInvalidCoordinatesForRegion(_ identifier: String) {
        error(
            "Invalid coordinates for region \(identifier), skipping",
            geofenceTag,
            nil
        )
    }

    func geofenceMonitoringFailed(region: String, error: Error) {
        self.error(
            "Monitoring failed for region \(region)",
            geofenceTag,
            error
        )
    }

    func geofenceMonitorEventStreamFailed(error: Error) {
        self.error(
            "Geofence monitor event stream ended with an error; background transitions may stop until the app is relaunched",
            geofenceTag,
            error
        )
    }

    // Logged at error level deliberately: `info`/`debug` are not persisted to the log store for
    // third-party subsystems, so a field report would not carry them.
    func geofenceMonitorStoppedMonitoringRegion(_ identifier: String) {
        error(
            "CoreLocation stopped monitoring region \(identifier); its transitions are not delivered until the next sync re-registers it",
            geofenceTag,
            nil
        )
    }

    func geofencePermissionUnavailable(currentStatus: CLAuthorizationStatus) {
        info(
            "Geofence registration skipped: location permission not granted (current status: \(currentStatus.rawValue)). The host app controls when and which permission to request.",
            geofenceTag
        )
    }

    func geofenceBackgroundDeliveryUnavailable(currentStatus: CLAuthorizationStatus) {
        info(
            "Geofence registered for foreground delivery only: WhenInUse authorization granted (current status: \(currentStatus.rawValue)). Background transitions require Always authorization.",
            geofenceTag
        )
    }

    func geofenceBackgroundDeliveryAvailable(currentStatus: CLAuthorizationStatus) {
        info(
            "Geofence background delivery active: Always authorization granted (current status: \(currentStatus.rawValue)).",
            geofenceTag
        )
    }

    // MARK: - Event Tracking

    func geofenceEventTracked(geofenceId: String, transition: GeofenceTransition) {
        debug(
            "Tracked \(transition.rawValue) event for geofence \(geofenceId)",
            geofenceTag
        )
    }

    func geofenceEventSuppressed(geofenceId: String, transition: GeofenceTransition) {
        debug(
            "Suppressed duplicate \(transition.rawValue) event for geofence \(geofenceId), within cooldown",
            geofenceTag
        )
    }

    func geofenceTransitionDroppedAnonymous(geofenceId: String, transition: GeofenceTransition) {
        debug(
            "Dropped \(transition.rawValue) event for geofence \(geofenceId): no identified user at transition time (geofencing is identified-only)",
            geofenceTag
        )
    }

    func geofencePendingPersistFailed(geofenceId: String, transition: GeofenceTransition) {
        error(
            "Failed to persist \(transition.rawValue) event for geofence \(geofenceId) before send; cooldown released so the next crossing can retry",
            geofenceTag,
            nil
        )
    }

    // MARK: - Sync

    func geofenceSyncSkipped(reason: String) {
        debug("Sync skipped: \(reason)", geofenceTag)
    }

    func geofenceSyncSkippedFresh() {
        debug("Sync skipped: last server fetch is within freshness window", geofenceTag)
    }

    func geofenceSyncFetchFailed(error: GeofenceApiError) {
        self.error("Sync fetch failed: \(error)", geofenceTag, nil)
    }

    func geofenceSyncCompleted(registeredCount: Int, movementTriggerRegistered: Bool) {
        let trigger = movementTriggerRegistered
            ? " + 1 movement trigger"
            : "; monitoring disabled (max business geofences is 0)"
        info("Sync completed: registered \(registeredCount) business geofences\(trigger)", geofenceTag)
    }

    func geofenceRegistrationDiff(added: Int, removed: Int, unchanged: Int) {
        debug("OS registration diff: +\(added) / -\(removed); \(unchanged) left registered untouched", geofenceTag)
    }

    func geofenceMovementTrigger(tier: HandleMovementTier) {
        debug("Movement trigger EXIT: \(tier.rawValue)", geofenceTag)
    }

    func geofenceMovementRearmedAfterFailedRefresh() {
        debug("Movement refresh failed; re-ranking from cache to re-arm the movement trigger", geofenceTag)
    }

    func geofenceMovementFixResolved(ageSeconds: TimeInterval, requested: Bool) {
        let source = requested ? "freshly requested" : "cached"
        debug("Movement pass using \(source) fix, age \(String(format: "%.1f", ageSeconds))s", geofenceTag)
    }

    func geofenceMovementFixStale(ageSeconds: TimeInterval?) {
        let age = ageSeconds.map { "\(String(format: "%.1f", $0))s old" } ?? "missing"
        info("Cached fix is \(age); requesting a fresh fix for the movement pass", geofenceTag)
    }

    func geofenceBaselineHealed(identifier: String, transition: GeofenceTransition) {
        info("Synthesized \(transition.rawValue) for region \(identifier): fresh fix contradicts stored baseline (OS never delivered the crossing)", geofenceTag)
    }

    /// Positive record of an OS-delivered business transition. Without it a native delivery is
    /// only identifiable by the ABSENCE of a synthesized line, which makes the OS promotion rate
    /// inferred rather than measured. Logged at the monitors' dispatch sites, where provenance is
    /// known: the resolver's entry point also receives synthesized heals, which would inflate it.
    func geofenceOsTransitionReceived(identifier: String, transition: GeofenceTransition) {
        debug("OS delivered \(transition.rawValue) for region \(identifier)", geofenceTag)
    }

    func geofencePolygonTransition(identifier: String, transition: GeofenceTransition, confirmedByFix: Bool) {
        let basis = confirmedByFix ? "a gated fix" : "the covering-circle exit"
        info("Polygon \(transition.rawValue) for region \(identifier), confirmed by \(basis)", geofenceTag)
    }

    /// A whole-set pass declined because one is already running. Logged so a foreground that
    /// produced no verdicts is distinguishable from one that never ran.
    func geofencePolygonPassSkipped(reason: String) {
        debug("Skipped polygon evaluation pass: \(reason)", geofenceTag)
    }

    func geofencePolygonUndecided(identifier: String, reason: String) {
        debug("Polygon membership undecided for region \(identifier): \(reason)", geofenceTag)
    }

    func geofenceEventRefusedByContradiction(identifier: String, transition: GeofenceTransition, distanceFromCenter: Double, radius: Double, accuracy: Double) {
        info("Refused OS \(transition.rawValue) for region \(identifier): a fresh fix contradicts it (distance \(Int(distanceFromCenter)) m, radius \(Int(radius)) m, accuracy \(Int(accuracy)) m)", geofenceTag)
    }

    func geofenceMovementFixRequestFailed(fallingBackToCached: Bool) {
        let outcome = fallingBackToCached ? "falling back to the stale cached fix" : "no cached fix to fall back to"
        info("Fresh-fix request failed or timed out; \(outcome)", geofenceTag)
    }

    func geofenceSyncSupersededByUserChange() {
        info("Sync result discarded: identified user changed during fetch", geofenceTag)
    }

    func geofenceResetCompleted() {
        info("Reset completed: monitoring stopped and user-scoped state cleared", geofenceTag)
    }

    func geofenceResetSuperseded() {
        debug("Reset skipped: another user is signed in", geofenceTag)
    }

    func geofenceFirstRunRearm() {
        debug("First-run refresh re-armed by new location fix", geofenceTag)
    }

    func geofenceRegionsAdopted(count: Int) {
        debug("Adopted \(count) OS-persisted region(s) on launch; re-armed in place", geofenceTag)
    }

    func geofenceForegroundRearm(count: Int) {
        info("Foreground entry after long suspension: re-armed \(count) condition(s) in place", geofenceTag)
    }
}
