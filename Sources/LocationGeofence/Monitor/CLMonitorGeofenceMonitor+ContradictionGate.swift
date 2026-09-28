import CioInternalCommon
import CoreLocation
import Foundation

/// Contradiction gate for OS-delivered transitions.
///
/// A CLMonitor (re)add replays the daemon's per-identifier belief as an immediate event computed
/// without a fresh evaluation. That belief can be hours stale, predate the install (it survives
/// uninstall), or default to unsatisfied for a never-seen identifier: false enters for far fences
/// and false-exit storms when registering while inside. The daemon's own re-evaluation follows a
/// few seconds later.
///
/// So only events inside a short window after our own (re)add are vetted, and one a fresh fix
/// unambiguously contradicts is refused BEFORE the baseline advances; the re-evaluation then dedups
/// against the untouched baseline. Outside the window nothing waits on a fix request. Undecidable
/// fixes (none, stale, or within the ambiguity margin) fail open.
@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    /// A drained (re)add: when it landed at the OS and the circle it imposed there.
    struct ConditionReadd {
        /// Stamped before the remove/add pair is issued. No replay of this add can be dated
        /// earlier, so an event dated before it (e.g. one buffered in `pendingEvents`) is not one.
        let start: Date
        /// Stamped after `add` returned; the replay window extends from here. Kept separate from
        /// `start` because a replay can be dated inside the remove→add gap, before `add` returns.
        let added: Date
        let center: LocationData
        let radius: Double

        /// Without the lower bound, any older event would be judged against geometry that may
        /// postdate it.
        func replayWindowCovers(_ eventDate: Date) -> Bool {
            eventDate >= start &&
                eventDate.timeIntervalSince(added) <= GeofenceConstants.contradictionGateReplayWindow
        }
    }

    /// True when the event lands inside the identifier's replay window AND a trustworthy fix
    /// contradicts it (`BaselineHealDecision` with `lastState` = the incoming transition; non-nil
    /// means the fix says the opposite). Geometry comes from the drained add, not the ledger, which
    /// already holds a staged reshape the OS has not taken yet. The window is keyed on the EVENT's
    /// date, not processing time, since an event can sit in `pendingEvents` until the handler binds.
    func isEventContradictedByFreshFix(identifier: String, transition: GeofenceTransition, eventDate: Date) async -> Bool {
        guard let readd = conditionReadds[identifier] else { return false }
        let insideWindow = readd.replayWindowCovers(eventDate)
        logger.geofenceContradictionEvaluated(
            identifier: identifier,
            transition: transition,
            delaySinceAdd: eventDate.timeIntervalSince(readd.added),
            insideWindow: insideWindow
        )
        guard insideWindow else { return false }
        // `process(event:)` skips the gate for the movement trigger, so this branch does not run
        // today. If it did, a fix request would stall the serial event consumer for up to
        // `movementFixRequestTimeout`, hence cache only.
        let isMovementTrigger = identifier == GeofenceConstants.movementTriggerIdentifier
        let gateFix = isMovementTrigger ? bestKnownFix() : await resolveGateFix()
        guard let gateFix, CLLocationCoordinate2DIsValid(gateFix.coordinate) else {
            // `gateFix` here is the unbound optional, so nil and invalid stay distinguishable.
            logger.geofenceContradictionNoFix(
                identifier: identifier,
                transition: transition,
                reason: gateFix == nil ? .noFixAvailable : .invalidCoordinate
            )
            return false
        }
        let center = CLLocation(latitude: readd.center.latitude, longitude: readd.center.longitude)
        let distanceFromCenter = gateFix.distance(from: center)
        let fixAge = dateUtil.now.timeIntervalSince(gateFix.timestamp)
        guard BaselineHealDecision.synthesizedTransition(
            distanceFromCenter: distanceFromCenter,
            radius: readd.radius,
            horizontalAccuracy: gateFix.horizontalAccuracy,
            fixAge: fixAge,
            lastState: transition
        ) != nil else {
            logger.geofenceContradictionAllowed(
                identifier: identifier,
                transition: transition,
                geometry: GateFixGeometry(
                    distanceFromCenter: distanceFromCenter,
                    radius: readd.radius,
                    accuracy: gateFix.horizontalAccuracy,
                    fixAge: fixAge
                )
            )
            return false
        }
        logger.geofenceEventRefusedByContradiction(
            identifier: identifier,
            transition: transition,
            distanceFromCenter: distanceFromCenter,
            radius: readd.radius,
            accuracy: gateFix.horizontalAccuracy
        )
        return true
    }

    /// Freshest fix for the gate, via the movement resolver. Events are processed serially, so the
    /// resolver's coalescing never engages: in a replay burst the first event pays at most one
    /// request and later ones read its fix from the cache. A failed attempt blocks new requests for
    /// `movementFixMaxAge` (see `gateFixRequestBlocked`), or a burst with no fix obtainable would
    /// stall the consumer one timeout per event. Returns `bestKnownFix()`; the caller's decision
    /// applies the age guard.
    private func resolveGateFix() async -> CLLocation? {
        if Self.gateFixRequestBlocked(failedAt: gateFixRequestFailedAt, now: dateUtil.now) {
            return bestKnownFix()
        }
        let isFresh: Bool = await withCheckedContinuation { continuation in
            movementFixResolver.resolve(cached: bestKnownFix(), purpose: .contradictionGate) { _, isFresh in
                continuation.resume(returning: isFresh)
            }
        }
        // The resolver's verdict, not the age of `bestKnownFix()`: a failed request can leave an OS
        // cache younger than `movementFixMaxAge`, which would read as success and skip the block.
        gateFixRequestFailedAt = isFresh ? nil : dateUtil.now
        return bestKnownFix()
    }

    /// Whether a gate-fix request is skipped because one failed within `movementFixMaxAge`. A late
    /// fix from the failed request still lands in `latestFix`, where the cache read picks it up.
    nonisolated static func gateFixRequestBlocked(failedAt: Date?, now: Date) -> Bool {
        guard let failedAt else { return false }
        return now.timeIntervalSince(failedAt) < GeofenceConstants.movementFixMaxAge
    }
}
