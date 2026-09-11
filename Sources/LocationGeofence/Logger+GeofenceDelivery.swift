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
    ///
    /// Reports `why` and nothing more. An earlier version also carried a `retry` flag; it was
    /// wrong on the commonest path (a default-config cold wake has no persisted key and recovers
    /// on the next foreground flush) and it meant something different from the Android field of
    /// the same name. Delivery is out of the harness's scope either way, so the honest record is
    /// what happened, not a prediction about what happens next.
    func geofenceDeliveryFailed(geofenceId: String, transition: GeofenceTransition, error: BackgroundDeliveryHttpError) {
        debug(
            "Geofence '\(geofenceId)' \(transition.rawValue): delivery failed (\(error.diagnosticReason)); row stays queued"
                + geofenceTail("delivery.failed", .output, [
                    ("id", geofenceId),
                    ("t", transition.rawValue),
                    ("ok", GeofenceLog.bool(false)),
                    ("why", error.diagnosticReason)
                ]),
            geofenceTag
        )
    }
}

// MARK: - Pending queue reads

//
// Classified `in`: the queue file is an input the SDK reads back, and a replay that fed these
// forward as outputs would invent deliveries. Both records exist because a shrinking backlog and
// a vanished one used to look identical — one undecodable row discarded the whole queue silently.

/// Why the pending queue file could not be turned into rows.
enum GeofenceQueueReadFailure: String {
    /// The bytes could not be obtained — Data Protection before first unlock, or an I/O error.
    /// The rows are intact on disk, so nothing may be written over them.
    case readFailed = "read_failed"
    /// The bytes came back but are not a row array, so there is nothing left to preserve.
    case notARowArray = "not_a_row_array"

    var prose: String {
        switch self {
        case .readFailed: return "the file could not be read"
        case .notARowArray: return "the file is not a row array"
        }
    }
}

extension Logger {
    /// Rows skipped because they did not decode. The count travels because it is the only thing
    /// that separates a backlog that shrank from one that was thrown away.
    func geofenceQueueRowsDropped(count: Int, of total: Int) {
        error(
            "Pending geofence queue: skipped \(count) of \(total) row(s) that did not decode"
                + geofenceTail("queue.rows_dropped", .input, [
                    ("why", "decode_failed"),
                    ("n", GeofenceLog.int(count)),
                    ("total", GeofenceLog.int(total))
                ]),
            geofenceTag,
            nil
        )
    }

    /// The queue could not be read at all. `why` decides whether the rows survive: a read failure
    /// leaves them on disk untouched, an unparseable file has already lost them.
    func geofenceQueueUnreadable(reason: GeofenceQueueReadFailure) {
        error(
            "Pending geofence queue unreadable: \(reason.prose)"
                + geofenceTail("queue.unreadable", .input, [("why", reason.rawValue)]),
            geofenceTag,
            nil
        )
    }
}

extension BackgroundDeliveryHttpError {
    /// Stable token for the tail, so a reader can tell an offline device from a misconfigured one.
    ///
    /// Deliberately not paired with a retryable/permanent verdict: the SDK re-attempts every queued
    /// row on every flush regardless, so any such flag would describe a theory rather than the
    /// SDK's behaviour.
    var diagnosticReason: String {
        switch self {
        case .missingApiHost: return "missing_api_host"
        case .missingCdpApiKey: return "missing_cdp_api_key"
        case .invalidRequest: return "invalid_request"
        case .transport: return "transport"
        // `BackgroundDeliveryHttpClient` synthesizes 0 when there was no response at all, which is
        // not a status a server ever sent.
        case .http(let statusCode): return statusCode == 0 ? "no_response" : "http_\(statusCode)"
        }
    }
}
