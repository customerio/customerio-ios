import CioInternalCommon
import Foundation

private let geofenceTag = "Geofence"

// MARK: - Delivery

//
// Namespaced under `delivery.` so replay can drop the whole family: replay checks that the SDK
// *accepted* a transition (`transition.accepted`), not that it reached the backend. Parallel to
// the Android records of the same names so one parser reads both.

extension Logger {
    /// Left our hands over direct HTTP and was removed from the pending store.
    func geofenceDeliverySent(geofenceId: String, transition: GeofenceTransition, via: String) {
        debug(
            "Geofence '\(geofenceId)' \(transition.rawValue): delivered (\(via)); removed from pending store"
                + geofenceTail("delivery.sent", .observation, [
                    ("id", geofenceId),
                    ("t", transition.rawValue),
                    ("via", via)
                ]),
            geofenceTag
        )
    }

    /// Handed to another queue that now owns delivery and retry. Not `delivery.sent`: the EventBus
    /// handoff is not a durable-persistence ack.
    func geofenceDeliveryQueued(geofenceId: String, transition: GeofenceTransition, via: String) {
        debug(
            "Geofence '\(geofenceId)' \(transition.rawValue): handed to \(via), which owns delivery and retry from here"
                + geofenceTail("delivery.queued", .observation, [
                    ("id", geofenceId),
                    ("t", transition.rawValue),
                    ("via", via)
                ]),
            geofenceTag
        )
    }

    /// The send failed and the row stays queued. Reports what happened, with no retry prediction.
    func geofenceDeliveryFailed(geofenceId: String, transition: GeofenceTransition, error: BackgroundDeliveryHttpError) {
        debug(
            "Geofence '\(geofenceId)' \(transition.rawValue): delivery failed (\(error.diagnosticReason)); row stays queued"
                + geofenceTail("delivery.failed", .observation, [
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
// Classified `in`: the queue file is an input the SDK reads back. These records separate a
// backlog that shrank from one that was lost.

/// Why the pending queue file could not be turned into rows.
enum GeofenceQueueReadFailure: String {
    /// The bytes could not be obtained — Data Protection before first unlock, or an I/O error.
    /// The rows are intact on disk, so nothing may be written over them.
    case readFailed = "read_failed"
    /// The bytes came back but are not a row array, so there is nothing left to preserve.
    case notARowArray = "not_a_row_array"
    /// The file's location could not be resolved at all, so no read or write can ever succeed.
    case noFileLocation = "no_file_location"

    var prose: String {
        switch self {
        case .readFailed: return "the file could not be read"
        case .notARowArray: return "the file is not a row array"
        case .noFileLocation: return "the file location could not be resolved"
        }
    }
}

extension Logger {
    /// Rows skipped because they did not decode.
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
    /// Stable token for the tail. No retryable/permanent verdict: every flush retries every queued
    /// row regardless.
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
