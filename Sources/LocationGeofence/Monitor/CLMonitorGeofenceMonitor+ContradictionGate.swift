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
    /// True when the event lands inside the identifier's replay window AND a trustworthy fix
    /// confidently contradicts it (`BaselineHealDecision` with `lastState` = the incoming
    /// transition — a non-nil result means the fix says the opposite of what the OS delivered).
    func isEventContradictedByFreshFix(identifier: String, transition: GeofenceTransition) async -> Bool {
        guard let readdedAt = conditionReaddTimestamps[identifier],
              Date().timeIntervalSince(readdedAt) <= GeofenceConstants.contradictionGateReplayWindow,
              let condition = registeredConditions[identifier]
        else { return false }
        let gateFix = await resolveGateFix()
        guard let gateFix, CLLocationCoordinate2DIsValid(gateFix.coordinate) else { return false }
        let center = CLLocation(latitude: condition.center.latitude, longitude: condition.center.longitude)
        let distanceFromCenter = gateFix.distance(from: center)
        guard BaselineHealDecision.synthesizedTransition(
            distanceFromCenter: distanceFromCenter,
            radius: condition.radius,
            horizontalAccuracy: gateFix.horizontalAccuracy,
            fixAge: -gateFix.timestamp.timeIntervalSinceNow,
            lastState: transition
        ) != nil else { return false }
        logger.geofenceEventRefusedByContradiction(
            identifier: identifier,
            transition: transition,
            distanceFromCenter: distanceFromCenter,
            radius: condition.radius,
            accuracy: gateFix.horizontalAccuracy
        )
        return true
    }

    /// Freshest fix obtainable for the gate: reuses the movement resolver (one-shot request when
    /// the cache is stale, coalesced across concurrent events — a replay burst re-adds many
    /// conditions at once and every event shares one resolution — cached-fix fallback on timeout).
    /// A cached fix is acceptable as-is: the gate only runs moments after an add that itself
    /// positioned the staging off the same cache, so it cannot meaningfully predate the state the
    /// event claims. Returns via `bestKnownFix()` so the freshest of the cache and the request
    /// wins; the caller's decision applies the fix-age guard to the result.
    private func resolveGateFix() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            movementFixResolver.resolve(cached: bestKnownFix()) { [weak self] _ in
                continuation.resume(returning: self?.bestKnownFix())
            }
        }
    }
}
