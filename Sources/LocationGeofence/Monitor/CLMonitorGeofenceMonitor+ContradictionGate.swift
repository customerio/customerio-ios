import CioInternalCommon
import CoreLocation
import Foundation

/// A CLMonitor (re)add replays the daemon's possibly stale belief as an immediate event. Events in a
/// short window after our own add that a fresh fix contradicts are refused; undecidable fixes fail
/// open.
@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    struct ConditionReadd {
        /// Before the remove/add pair: an event dated earlier can't be this add's replay.
        let start: Date
        /// After `add` returned; the window runs from here. A replay can still be dated inside the
        /// remove→add gap, hence `start`.
        let added: Date
        let center: LocationData
        let radius: Double

        /// The lower bound stops an older event being judged against geometry that may postdate it.
        func replayWindowCovers(_ eventDate: Date) -> Bool {
            eventDate >= start &&
                eventDate.timeIntervalSince(added) <= GeofenceConstants.contradictionGateReplayWindow
        }
    }

    /// Windowed on the EVENT's date, not processing time: an event can sit in `pendingEvents`.
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
        // Unreachable today (`process(event:)` skips the trigger). Cache only: a fix request would
        // stall the serial event consumer.
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

    /// A failed request blocks new ones for `movementFixMaxAge`, or a burst with no fix obtainable
    /// would stall the consumer one timeout per event.
    private func resolveGateFix() async -> CLLocation? {
        if Self.gateFixRequestBlocked(failedAt: gateFixRequestFailedAt, now: dateUtil.now) {
            return bestKnownFix()
        }
        let isFresh: Bool = await withCheckedContinuation { continuation in
            movementFixResolver.resolve(cached: bestKnownFix(), purpose: .contradictionGate) { _, isFresh in
                continuation.resume(returning: isFresh)
            }
        }
        // The resolver's verdict, not the fix's age: a failed request can leave a young OS cache.
        gateFixRequestFailedAt = isFresh ? nil : dateUtil.now
        return bestKnownFix()
    }

    nonisolated static func gateFixRequestBlocked(failedAt: Date?, now: Date) -> Bool {
        guard let failedAt else { return false }
        return now.timeIntervalSince(failedAt) < GeofenceConstants.movementFixMaxAge
    }
}
