import CioInternalCommon
import Foundation

private let geofenceTag = "Geofence"

// MARK: - Delivery

//
// Classified `out` and namespaced under `delivery.` so replay can drop the whole family: what
// replay checks is that the SDK *accepted* a transition, not that it reached the backend. Kept
// deliberately parallel to the Android records of the same names — one parser reads both, so a
// key that means something different here is worse than a key that is missing.
//
// The distinction these exist to preserve: `transition.accepted` says the SDK judged the crossing
// real and made it durable. Everything below depends on the network and says nothing about
// geofencing. Before this split, the only positive record fired on delivery, so an offline device
// looked as though it had missed crossings it had in fact handled correctly.

extension Logger {
    /// Left our hands over direct HTTP and was removed from the pending store.
    func geofenceDeliverySent(geofenceId: String, transition: GeofenceTransition, via: String) {
        debug(
            "Geofence '\(geofenceId)' \(transition.rawValue): delivered (\(via)); removed from pending store"
                + geofenceTail("delivery.sent", .output, [
                    ("id", geofenceId),
                    ("t", transition.rawValue),
                    ("via", via)
                ]),
            geofenceTag
        )
    }

    /// Handed to another queue that now owns delivery and retry.
    ///
    /// Not `delivery.sent`: the EventBus handoff resolving is the strongest signal available, and
    /// it is explicitly not a durable-persistence ack — calling it "sent" would overstate it.
    func geofenceDeliveryQueued(geofenceId: String, transition: GeofenceTransition, via: String) {
        debug(
            "Geofence '\(geofenceId)' \(transition.rawValue): handed to \(via), which owns delivery and retry from here"
                + geofenceTail("delivery.queued", .output, [
                    ("id", geofenceId),
                    ("t", transition.rawValue),
                    ("via", via)
                ]),
            geofenceTag
        )
    }

    /// The send failed and the row stays queued.
    ///
    /// Previously silent, which is what made an offline drive unreadable: a crossing the SDK had
    /// accepted and was retrying was indistinguishable from one it never saw.
    func geofenceDeliveryFailed(geofenceId: String, transition: GeofenceTransition, retry: Bool) {
        debug(
            "Geofence '\(geofenceId)' \(transition.rawValue): delivery failed; "
                + (retry ? "row stays queued for the next flush" : "not retrying")
                + geofenceTail("delivery.failed", .output, [
                    ("id", geofenceId),
                    ("t", transition.rawValue),
                    ("ok", GeofenceLog.bool(false)),
                    ("retry", GeofenceLog.bool(retry))
                ]),
            geofenceTag
        )
    }
}
