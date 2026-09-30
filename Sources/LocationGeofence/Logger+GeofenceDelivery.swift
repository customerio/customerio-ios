import CioInternalCommon
import Foundation

private let geofenceTag = "Geofence"

// MARK: - Delivery

//
// Keep the `delivery.` prefix: replay drops the whole family. Same names as Android.

extension Logger {
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

    /// Not `delivery.sent`: the EventBus handoff is not a durable ack.
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

enum GeofenceQueueReadFailure: String {
    /// E.g. Data Protection before first unlock. The rows are intact on disk: nothing may overwrite
    /// them.
    case readFailed = "read_failed"
    /// Nothing left to preserve.
    case notARowArray = "not_a_row_array"
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
    var diagnosticReason: String {
        switch self {
        case .missingApiHost: return "missing_api_host"
        case .missingCdpApiKey: return "missing_cdp_api_key"
        case .invalidRequest: return "invalid_request"
        case .transport: return "transport"
        // 0 is synthesized for no response at all, not a server status.
        case .http(let statusCode): return statusCode == 0 ? "no_response" : "http_\(statusCode)"
        }
    }
}
