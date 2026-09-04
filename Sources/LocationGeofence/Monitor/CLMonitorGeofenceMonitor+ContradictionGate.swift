import CioInternalCommon
import CoreLocation
import Foundation

/// Contradiction gate for OS-delivered transitions, split out to keep the monitor's event
/// plumbing readable (same convention as `+Registration`).
///
/// CLMonitor re-adds (registration, adopt, rearm) replay the daemon's per-identifier belief as an
/// immediate event computed WITHOUT a fresh evaluation. The belief can be stale by hours
/// (crossings observed while the app was dead), predate the install (it persists across
/// uninstalls), or default to unsatisfied for never-seen identifiers — producing false enters for
/// far fences and false-exit storms when registering while inside (both field-observed; the
/// daemon's own re-evaluation follows ~3 s later, measured).
///
/// The gate therefore vets only events landing inside a short window after our own (re)add of
/// that identifier — where belief replays live — and refuses one that a fresh fix unambiguously
/// contradicts, BEFORE the dedup baseline advances, so the daemon's re-evaluation lands as a
/// duplicate against the untouched baseline and is absorbed silently. Everything outside the
/// window flows exactly as before: a normal crossing is never delayed by a fix request, and a
/// legitimate in-window corrective (rearm/wedged-crossing recovery) agrees with the fix and
/// passes. Undecidable fixes — none, stale, or within the ambiguity margin — fail OPEN.
@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    /// A drained (re)add: when it landed at the OS and the circle it imposed there.
    struct ConditionReadd {
        /// Stamped before the remove/add pair is issued. A replay is created by the add, so no
        /// replay can be dated earlier — while an event dated before it (e.g. a catch-up buffered
        /// in `pendingEvents` across the re-add) is provably not this add's replay.
        let start: Date
        /// Stamped after `add` returned; the replay window extends from here. Kept separate from
        /// `start` because a replay can be dated inside the remove→add gap, before `add` returns.
        let added: Date
        let center: LocationData
        let radius: Double

        /// Whether an event's date falls inside this add's replay window. Both bounds matter:
        /// without the lower one, any event dated before the add — however old — would be gated
        /// and judged against geometry that may postdate it.
        func replayWindowCovers(_ eventDate: Date) -> Bool {
            eventDate >= start &&
                eventDate.timeIntervalSince(added) <= GeofenceConstants.contradictionGateReplayWindow
        }
    }

    /// True when the event lands inside the identifier's replay window AND a trustworthy fix
    /// confidently contradicts it (`BaselineHealDecision` with `lastState` = the incoming
    /// transition — a non-nil result means the fix says the opposite of what the OS delivered).
    /// Geometry comes from the drained add's stamp, not `registeredConditions`: that map updates
    /// synchronously when a reshape is staged, so during its staging→drain gap an event the OS
    /// computed on the old circle must still be judged against the old circle.
    /// The window compares the EVENT's date to the add, not the processing time: an event can sit
    /// in `pendingEvents` until the bootstrap binds the handler, and a belief replay must stay
    /// gated no matter how late it drains — while a real crossing dated outside the window, before
    /// the add or minutes after it, stays ungated no matter when it is processed.
    func isEventContradictedByFreshFix(identifier: String, transition: GeofenceTransition, eventDate: Date) async -> Bool {
        guard let readd = conditionReadds[identifier],
              readd.replayWindowCovers(eventDate)
        else { return false }
        let gateFix = await resolveGateFix()
        guard let gateFix, CLLocationCoordinate2DIsValid(gateFix.coordinate) else { return false }
        let center = CLLocation(latitude: readd.center.latitude, longitude: readd.center.longitude)
        let distanceFromCenter = gateFix.distance(from: center)
        guard BaselineHealDecision.synthesizedTransition(
            distanceFromCenter: distanceFromCenter,
            radius: readd.radius,
            horizontalAccuracy: gateFix.horizontalAccuracy,
            fixAge: -gateFix.timestamp.timeIntervalSinceNow,
            lastState: transition
        ) != nil else { return false }
        logger.geofenceEventRefusedByContradiction(
            identifier: identifier,
            transition: transition,
            distanceFromCenter: distanceFromCenter,
            radius: readd.radius,
            accuracy: gateFix.horizontalAccuracy
        )
        return true
    }

    /// Freshest fix obtainable for the gate: reuses the movement resolver (one-shot request when
    /// the cache is stale, cached-fix fallback on timeout). In a replay burst the FIRST event pays
    /// at most one request and every later event reads the fix it delivered from the cache — the
    /// events loop awaits `process` serially, so the resolver's in-flight coalescing never engages
    /// and repeated requests would stack instead. When an attempt fails to produce a fresh fix,
    /// that failure is remembered for `movementFixMaxAge` and later events skip straight to the
    /// cache (failing open, exactly as the timed-out attempt did) — otherwise a burst with no fix
    /// obtainable would stall the single event consumer for one timeout per gated event. A late
    /// fix from the failed request still reaches `latestFix` and serves the rest of the burst.
    /// A cached fix is acceptable as-is: the gate only runs moments after an add that itself
    /// positioned the staging off the same cache, so it cannot meaningfully predate the state the
    /// event claims. Returns via `bestKnownFix()` so the freshest of the cache and the request
    /// wins; the caller's decision applies the fix-age guard to the result.
    private func resolveGateFix() async -> CLLocation? {
        if Self.gateFixRequestBlocked(failedAt: gateFixRequestFailedAt, now: Date()) {
            return bestKnownFix()
        }
        let fix: CLLocation? = await withCheckedContinuation { continuation in
            movementFixResolver.resolve(cached: bestKnownFix()) { [weak self] _, _ in
                continuation.resume(returning: self?.bestKnownFix())
            }
        }
        let isFresh = fix.map { -$0.timestamp.timeIntervalSinceNow <= GeofenceConstants.movementFixMaxAge } ?? false
        gateFixRequestFailedAt = isFresh ? nil : Date()
        return fix
    }

    /// Whether a new gate-fix request is skipped because the last one recently came back without
    /// a fresh fix. Blocked for `movementFixMaxAge` after the failure: within it a re-request at
    /// the same conditions is unlikely to fare better, and a late fix from the failed request
    /// still lands in `latestFix` where the cache read picks it up.
    nonisolated static func gateFixRequestBlocked(failedAt: Date?, now: Date) -> Bool {
        guard let failedAt else { return false }
        return now.timeIntervalSince(failedAt) < GeofenceConstants.movementFixMaxAge
    }
}
