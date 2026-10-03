import CioInternalCommon
import Foundation

private let geofenceTag = "Geofence"

// MARK: - Crossing decisions

//
// `transition.accepted` and `transition.synthesized` match Android verbatim (key, fields, tokens).

extension Logger {
    /// `n` is the row count, one per geoset the fence belongs to.
    func geofenceTransitionAccepted(geofenceId: String, transition: GeofenceTransition, rows: Int) {
        debug(
            "Accepted \(transition.rawValue) for geofence \(geofenceId), queued \(rows) row(s)"
                + geofenceTail("transition.accepted", .output, [
                    ("id", geofenceId),
                    ("t", transition.rawValue),
                    ("n", GeofenceLog.int(rows))
                ]),
            geofenceTag
        )
    }

    func geofenceBaselineHealed(identifier: String, transition: GeofenceTransition) {
        info(
            "Synthesized \(transition.rawValue) for region \(identifier): fresh fix contradicts stored baseline (OS never delivered the crossing)"
                + geofenceTail("baseline.healed", .observation, [
                    ("id", identifier),
                    ("t", transition.rawValue)
                ]),
            geofenceTag
        )
    }

    /// `dly` is the event's date minus the add; `win` whether the window covered it.
    func geofenceContradictionEvaluated(identifier: String, transition: GeofenceTransition, delaySinceAdd: TimeInterval, insideWindow: Bool) {
        debug(
            "Event for region \(identifier) landed \(String(format: "%.3f", delaySinceAdd))s after its re-add"
                + geofenceTail("contradiction.evaluated", .observation, [
                    ("id", identifier),
                    ("t", transition.rawValue),
                    ("dly", GeofenceLog.num(delaySinceAdd, 3)),
                    ("win", GeofenceLog.bool(insideWindow))
                ]),
            geofenceTag
        )
    }

    /// `edge` is negative inside (circle convention); polygon records use the opposite sign.
    func geofenceContradictionAllowed(
        identifier: String,
        transition: GeofenceTransition,
        geometry: GateFixGeometry
    ) {
        debug(
            "Allowed OS \(transition.rawValue) for region \(identifier): the gate did not refuse it (distance \(Int(geometry.distanceFromCenter)) m, radius \(Int(geometry.radius)) m, accuracy \(Int(geometry.accuracy)) m, fix age \(String(format: "%.1f", geometry.fixAge))s)"
                + geofenceTail("contradiction.allowed", .observation, [
                    ("id", identifier),
                    ("t", transition.rawValue),
                    ("dist", GeofenceLog.num(geometry.distanceFromCenter, 0)),
                    ("rad", GeofenceLog.num(geometry.radius, 0)),
                    ("edge", GeofenceLog.num(geometry.signedEdgeDistance, 0)),
                    ("acc", GeofenceLog.num(geometry.accuracy)),
                    ("age", GeofenceLog.num(geometry.fixAge))
                ]),
            geofenceTag
        )
    }

    /// Fails open. A blocked fix request doesn't land here: it logs `contradiction.allowed` with a
    /// large `age`.
    func geofenceContradictionNoFix(
        identifier: String,
        transition: GeofenceTransition,
        reason: ContradictionGateNoFixReason
    ) {
        debug(
            "Allowed OS \(transition.rawValue) for region \(identifier): \(reason.prose)"
                + geofenceTail("contradiction.no_fix", .observation, [
                    ("id", identifier),
                    ("t", transition.rawValue),
                    ("why", reason.rawValue)
                ]),
            geofenceTag
        )
    }

    func geofenceEventRefusedByContradiction(identifier: String, transition: GeofenceTransition, distanceFromCenter: Double, radius: Double, accuracy: Double) {
        info(
            "Refused OS \(transition.rawValue) for region \(identifier): a fresh fix contradicts it (distance \(Int(distanceFromCenter)) m, radius \(Int(radius)) m, accuracy \(Int(accuracy)) m)"
                + geofenceTail("contradiction.refused", .observation, [
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

    /// Not `os.callback.dropped`: nothing arrived from the OS, so it must not skew that count.
    func geofenceBaselineRefused(identifier: String, transition: GeofenceTransition, reason: String) {
        debug(
            "Baseline heal for region \(identifier) refused: \(reason)"
                + geofenceTail("baseline.refused", .observation, [
                    ("id", identifier),
                    ("t", transition.rawValue),
                    ("why", reason)
                ]),
            geofenceTag
        )
    }

    /// `why` is hardcoded to match Android.
    func geofenceTransitionSynthesized(geofenceId: String, transition: GeofenceTransition) {
        debug(
            "Geofence '\(geofenceId)': device already inside a newly-registered fence — synthesizing \(transition.rawValue)"
                + geofenceTail("transition.synthesized", .observation, [
                    ("id", geofenceId),
                    ("t", transition.rawValue),
                    ("why", "initial_enter_inside")
                ]),
            geofenceTag
        )
    }
}
