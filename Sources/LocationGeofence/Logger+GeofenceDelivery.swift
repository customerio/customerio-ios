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
    /// `why` and `retry` both come from the error, because without them an offline device and a
    /// revoked API key produce byte-identical records — and the Android record of this name has
    /// always carried `why`.
    func geofenceDeliveryFailed(geofenceId: String, transition: GeofenceTransition, error: BackgroundDeliveryHttpError) {
        let retry = error.isRetryable
        debug(
            "Geofence '\(geofenceId)' \(transition.rawValue): delivery failed (\(error.diagnosticReason)); "
                + (retry ? "row stays queued for the next flush" : "retrying cannot help")
                + geofenceTail("delivery.failed", .output, [
                    ("id", geofenceId),
                    ("t", transition.rawValue),
                    ("ok", GeofenceLog.bool(false)),
                    ("retry", GeofenceLog.bool(retry)),
                    ("why", error.diagnosticReason)
                ]),
            geofenceTag
        )
    }
}

extension BackgroundDeliveryHttpError {
    /// Stable token for the tail. Mirrors the Android `why` vocabulary on `delivery.failed`.
    var diagnosticReason: String {
        switch self {
        case .missingApiHost: return "missing_api_host"
        case .missingCdpApiKey: return "missing_cdp_api_key"
        case .invalidRequest: return "invalid_request"
        case .transport: return "transport"
        case .http(let statusCode): return "http_\(statusCode)"
        }
    }

    /// Whether another attempt with the same row and config could ever succeed.
    ///
    /// A missing host or key, a malformed request, and a 4xx other than 408/429 fail identically
    /// forever. Reporting those as retryable made a permanent misconfiguration read as flaky
    /// network — the two need different responses from whoever reads the log.
    var isRetryable: Bool {
        switch self {
        case .transport: return true
        case .missingApiHost, .missingCdpApiKey, .invalidRequest: return false
        case .http(let statusCode):
            if statusCode == 408 || statusCode == 429 { return true }
            return !(400 ..< 500).contains(statusCode)
        }
    }
}
