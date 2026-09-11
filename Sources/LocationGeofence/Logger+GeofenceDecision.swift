import CioInternalCommon
import Foundation

private let geofenceTag = "Geofence"

// MARK: - Crossing decisions

//
// What the SDK concluded about a crossing, as opposed to what the OS handed it (`os.callback.*`)
// or what happened to the event afterwards (`delivery.*`). This family is what replay asserts on.
//
// `transition.accepted` and `transition.synthesized` are shared with Android verbatim — same key,
// same fields, same reason tokens — so one parser reads both. `baseline.refused` is iOS-only:
// Android has no baseline heal, so there is nothing on that side to match.
//
// Grouped by meaning rather than by whichever file had room, which is how `transition.accepted`
// ended up next to the permission records in the first place.

extension Logger {
    /// The SDK accepted a crossing and durably queued it — the decision replay asserts on.
    ///
    /// Distinct from the `delivery.*` family, which fires only once the row leaves. Neither of
    /// those says the SDK judged the crossing real, and on an offline device they can trail it by
    /// many minutes or never arrive, which makes them useless as a signal about geofencing. This
    /// record makes no claim about what happens to the row next.
    /// A field drive showed exactly that — one crossing surfaced 26 minutes late and another,
    /// accepted and persisted, produced no positive record at all.
    ///
    /// `n` is the row count: one per geoset the fence belongs to, so a fan-out is visible as one
    /// acceptance rather than inferred from the delivery records that follow.
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
                + geofenceTail("baseline.healed", .output, [
                    ("id", identifier),
                    ("t", transition.rawValue)
                ]),
            geofenceTag
        )
    }

    /// Every event arriving while a re-add record is held, with its distance in TIME from that add.
    ///
    /// The gate records only refusals, so `contradictionGateReplayWindow` could not be calibrated
    /// from a drive: an event just outside the window and an event that was never a replay both
    /// logged nothing. `dly` is the event's date minus the add, `win` whether the current bound
    /// covered it — together, the distribution the constant is currently guessing at.
    func geofenceContradictionEvaluated(identifier: String, transition: GeofenceTransition, delaySinceAdd: TimeInterval, insideWindow: Bool) {
        debug(
            "Event for region \(identifier) landed \(String(format: "%.3f", delaySinceAdd))s after its re-add"
                + geofenceTail("contradiction.evaluated", .output, [
                    ("id", identifier),
                    ("t", transition.rawValue),
                    ("dly", GeofenceLog.num(delaySinceAdd, 3)),
                    ("win", GeofenceLog.bool(insideWindow))
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

    /// A heal decided a crossing was real and the dedup baseline refused it.
    ///
    /// `io=out` and its own key, deliberately not `os.callback.dropped`: nothing arrived from the
    /// OS here. A heal synthesizes the transition from a fix, so reporting it as a dropped callback
    /// invents an OS delivery that never happened and inflates the received-vs-dropped count —
    /// the count that distinguishes "the OS never reported it" from "we discarded it", which is
    /// the question a paired drive exists to answer.
    func geofenceBaselineRefused(identifier: String, transition: GeofenceTransition, reason: String) {
        debug(
            "Baseline heal for region \(identifier) refused: \(reason)"
                + geofenceTail("baseline.refused", .output, [
                    ("id", identifier),
                    ("t", transition.rawValue),
                    ("why", reason)
                ]),
            geofenceTag
        )
    }

    /// An ENTER the SDK invented because the device was already inside a newly-registered fence.
    ///
    /// Without it a synthesized enter is indistinguishable from a real crossing in the log — the
    /// 2026-09-07 drive opened with exactly this, and only the surrounding context revealed it.
    /// Matches the Android record of the same name and reason token so one parser reads both —
    /// including hardcoding the reason rather than taking it as a parameter, so the prose and the
    /// `why` token cannot drift apart at a second call site.
    func geofenceTransitionSynthesized(geofenceId: String, transition: GeofenceTransition) {
        debug(
            "Geofence '\(geofenceId)': device already inside a newly-registered fence — synthesizing \(transition.rawValue)"
                + geofenceTail("transition.synthesized", .output, [
                    ("id", geofenceId),
                    ("t", transition.rawValue),
                    ("why", "initial_enter_inside")
                ]),
            geofenceTag
        )
    }
}
