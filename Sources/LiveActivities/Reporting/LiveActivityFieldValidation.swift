import CioInternalCommon
import Foundation

/// Best-effort validation of required Live Activity fields on local `start`/`update`.
///
/// The typed struct API already makes most required fields non-optional at compile time;
/// this adds a runtime guard for the cases the type system can't catch — required *string*
/// slots that are present but empty. Missing/empty required fields are logged as an error
/// via the SDK logger; the operation is not blocked (the OS still renders what it can, and
/// push-side decode failures are enforced by ActivityKit).
///
/// Required-key sets mirror §1 of the field contract, keyed by each template's activity
/// identifier (the `notificationType`). Attributes and content-state are merged before the
/// check, so a key may live in either envelope.
enum LiveActivityFieldValidation {
    /// Required non-empty string slots per activity identifier.
    private static let requiredStringKeys: [String: [String]] = [
        "io.customer.liveactivities.deliverytracking": ["title"],
        "io.customer.liveactivities.flightstatus": ["title"],
        "io.customer.liveactivities.auctionbid": ["title", "statusMessage", "currentBid", "currencySymbol"],
        "io.customer.liveactivities.countdowntimer": ["title", "subtitle"],
        "io.customer.liveactivities.livescore": []
    ]

    static func warnIfMissingRequired(
        attributes: some Encodable,
        contentState: some Encodable,
        operation: String,
        notificationType: String,
        logger: Logger
    ) {
        guard let required = requiredStringKeys[notificationType], !required.isEmpty else { return }

        var merged: [String: Any] = [:]
        if let a = LiveActivityReporter.encode(attributes) { merged.merge(a) { _, new in new } }
        if let c = LiveActivityReporter.encode(contentState) { merged.merge(c) { _, new in new } }

        for key in required {
            let value = merged[key] as? String
            if value == nil || value?.isEmpty == true {
                logger.error(
                    "Live Activity \(operation) for \(notificationType) is missing required field '\(key)'.",
                    "LiveActivities",
                    nil
                )
            }
        }
    }

    /// Content-state-only overload for `update`, where no attributes are available.
    static func warnIfMissingRequired(
        contentState: some Encodable,
        operation: String,
        notificationType: String,
        logger: Logger
    ) {
        guard let required = requiredStringKeys[notificationType], !required.isEmpty else { return }

        var merged: [String: Any] = [:]
        if let c = LiveActivityReporter.encode(contentState) { merged.merge(c) { _, new in new } }

        // On update, only content-state keys are present; attributes-only required keys
        // (e.g. `title`/`currencySymbol` for auction) can't be re-validated here, so skip
        // any key absent from the content-state envelope.
        for key in required where merged[key] != nil {
            let value = merged[key] as? String
            if value?.isEmpty == true {
                logger.error(
                    "Live Activity \(operation) for \(notificationType) has empty required field '\(key)'.",
                    "LiveActivities",
                    nil
                )
            }
        }
    }
}
