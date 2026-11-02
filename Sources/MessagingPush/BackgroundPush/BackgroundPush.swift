import Foundation
import CoreFoundation

/// Business data received in a Customer.io background push. Delivery can be repeated;
/// use `deliveryID` to make application work idempotent.
public struct CustomerIOBackgroundPush: Equatable {
    public let deliveryID: String
    /// The original target token, for manual delivered tracking when automatic tracking is disabled.
    public let deliveryToken: String
    public let data: [String: String]
}

/// Only `notBackground` is eligible for another push handler. An unsupported marked
/// message must be consumed without falling back to notification rendering.
public enum CustomerIOBackgroundPushResult: Equatable {
    case notBackground
    case unsupported
    case received(CustomerIOBackgroundPush)
}

private enum BackgroundPushParser {
    static func parse(_ userInfo: [AnyHashable: Any]) -> (CustomerIOBackgroundPushResult, String?) {
        let prefix = "CIO-Background-"
        let metadataKeys: Set = ["\(prefix)Version", "\(prefix)Delivery-ID", "\(prefix)Delivery-Token"]
        // Existing customer keys may share the prefix without declaring background intent.
        guard metadataKeys.contains(where: { userInfo[$0] != nil }) else {
            return (.notBackground, nil)
        }
        guard userInfo["\(prefix)Version"] as? String == "1",
              let deliveryID = userInfo["\(prefix)Delivery-ID"] as? String,
              !deliveryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let token = userInfo["\(prefix)Delivery-Token"] as? String,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let aps = userInfo["aps"] as? [String: Any], aps.count == 1,
              let available = aps["content-available"] as? NSNumber,
              CFGetTypeID(available) != CFBooleanGetTypeID(), available.doubleValue == 1
        else { return (.unsupported, nil) }

        var data: [String: String] = [:]
        for (rawKey, value) in userInfo {
            guard let key = rawKey as? String else { return (.unsupported, nil) }
            let lower = key.lowercased()
            if key == "aps" || metadataKeys.contains(key) || lower.hasPrefix("google.") || lower.hasPrefix("gcm.") { continue }
            guard !key.isEmpty, !lower.hasPrefix("cio-"),
                  !["aps", "cio", "notification", "from", "message_type", "collapse_key"].contains(lower),
                  let value = value as? String
            else { return (.unsupported, nil) }
            data[key] = value
        }
        return (.received(CustomerIOBackgroundPush(deliveryID: deliveryID, deliveryToken: token, data: data)), token)
    }
}

public extension MessagingPush {
    /// Call from the host's background remote-notification handler. The host owns
    /// its fetch completion handler and must finish within the system's deadline.
    /// This method never displays a notification or tracks an opened event.
    /// Initialize MessagingPush before calling to enable automatic delivered metrics.
    /// Before returning, saves a delivered receipt in app storage and starts sending
    /// it with extra background time. Unsent receipts are retried on a later push or launch.
    /// The receipt records SDK receipt only. Delivery is not guaranteed and can repeat.
    @discardableResult
    func handleBackgroundPush(userInfo: [AnyHashable: Any]) -> CustomerIOBackgroundPushResult {
        let receivedAt = Date()
        let (result, token) = BackgroundPushParser.parse(userInfo)
        switch result {
        case .received(let payload):
            guard let token, Self.moduleConfig.autoTrackPushEvents else { break }
            guard let sender = Self.backgroundPushReceiptSender else {
                logger.info("Background push received before host initialization; no automatic delivered metric was recorded")
                break
            }
            sender.enqueue(deliveryID: payload.deliveryID, deviceToken: token, receivedAt: receivedAt)
        case .unsupported:
            logger.info("Ignoring unsupported background push without displaying a notification")
        case .notBackground:
            break
        }
        return result
    }
}
