import Foundation
import CoreFoundation

/// Data from a Customer.io silent (background) push.
///
/// The same push can arrive more than once, so key your work on `deliveryID`.
public struct CustomerIOBackgroundPush: Equatable {
    /// Identifies this delivery. Repeats of one push share it.
    public let deliveryID: String
    /// The device token the push was sent to. Needed only to track Delivered yourself
    /// when `autoTrackPushEvents` is off.
    public let deliveryToken: String
    /// The data set on the message, as text key/value pairs.
    public let data: [String: String]
}

/// What ``MessagingPush/handleBackgroundPush(userInfo:)`` found in a remote notification.
public enum CustomerIOBackgroundPushResult: Equatable {
    /// Not a Customer.io silent push. Pass it to your other push handlers.
    /// A push carrying the older `CIO-Delivery-ID` and `CIO-Delivery-Token` pair is always this case.
    case notBackground
    /// A Customer.io silent push this SDK version can't read, such as a newer version.
    /// Nothing is shown and no receipt is recorded. Complete your handler with `.noData`.
    case unsupported
    /// A Customer.io silent push, with its data.
    case received(CustomerIOBackgroundPush)
}

private enum BackgroundPushParser {
    static func parse(_ userInfo: [AnyHashable: Any]) -> CustomerIOBackgroundPushResult {
        // The legacy relay owns this pair; background envelopes forbid it.
        if userInfo["CIO-Delivery-ID"] is String, userInfo["CIO-Delivery-Token"] is String {
            return .notBackground
        }
        let prefix = "CIO-Background-"
        let metadataKeys: Set = ["\(prefix)Version", "\(prefix)Delivery-ID", "\(prefix)Delivery-Token"]
        // Existing customer keys may share the prefix without declaring background intent.
        guard metadataKeys.contains(where: { userInfo[$0] != nil }) else {
            return .notBackground
        }
        guard userInfo["\(prefix)Version"] as? String == "1",
              let deliveryID = userInfo["\(prefix)Delivery-ID"] as? String,
              !deliveryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let token = userInfo["\(prefix)Delivery-Token"] as? String,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let aps = userInfo["aps"] as? [String: Any], aps.count == 1,
              let available = aps["content-available"] as? NSNumber,
              CFGetTypeID(available) != CFBooleanGetTypeID(), available.doubleValue == 1
        else { return .unsupported }

        var data: [String: String] = [:]
        for (rawKey, value) in userInfo {
            guard let key = rawKey as? String else { return .unsupported }
            let lower = key.lowercased()
            if key == "aps" || metadataKeys.contains(key) || lower.hasPrefix("google.") || lower.hasPrefix("gcm.") { continue }
            guard !key.isEmpty, !lower.hasPrefix("cio-"),
                  !["aps", "cio", "notification", "from", "message_type", "collapse_key"].contains(lower),
                  let value = value as? String
            else { return .unsupported }
            data[key] = value
        }
        return .received(CustomerIOBackgroundPush(deliveryID: deliveryID, deliveryToken: token, data: data))
    }
}

public extension MessagingPush {
    /// Reads a Customer.io silent push and records its Delivered receipt. It never shows a notification
    /// and never tracks Opened.
    ///
    /// Call it from `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`, after enabling
    /// `MessagingPushConfigBuilder.backgroundPushEnabled(_:)` and the Remote notifications background mode.
    /// Your app owns the completion handler. iOS allows about 30 seconds: call it once, as soon as your work ends.
    ///
    /// ```swift
    /// func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    ///                  fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    ///     switch MessagingPush.shared.handleBackgroundPush(userInfo: userInfo) {
    ///     case .received(let push):
    ///         refreshAccount(push.data, deliveryID: push.deliveryID) { completionHandler(.newData) }
    ///     case .unsupported:
    ///         completionHandler(.noData)
    ///     case .notBackground:
    ///         completionHandler(.noData) // or pass it to your other handlers
    ///     }
    /// }
    /// ```
    ///
    /// Delivery is best effort. The same push can arrive twice, so key your work on `deliveryID`. iOS doesn't wake
    /// an app the person force-quit. While the device is offline, Apple keeps only the newest push for the app,
    /// so an earlier silent push can be dropped.
    ///
    /// When `autoTrackPushEvents` is on, the receipt is saved to app storage before this returns, then sent with
    /// extra background time. A receipt that can't be sent is retried on a later push, launch or profile change.
    /// A repeat of the same delivery records no second receipt. Calling this before `MessagingPush.initialize`
    /// returns the data too, and its receipt is sent once the SDK is initialized.
    @available(iOSApplicationExtension, unavailable)
    @discardableResult
    func handleBackgroundPush(userInfo: [AnyHashable: Any]) -> CustomerIOBackgroundPushResult {
        let receivedAt = Date()
        let result = BackgroundPushParser.parse(userInfo)
        switch result {
        case .received(let payload):
            guard Self.moduleConfig.autoTrackPushEvents else { break }
            Self.backgroundPushReceiptSenderCreatingIfNeeded()
                .enqueue(deliveryID: payload.deliveryID, deviceToken: payload.deliveryToken, receivedAt: receivedAt)
        case .unsupported:
            logger.info("Ignoring unsupported background push without displaying a notification")
        case .notBackground:
            break
        }
        return result
    }
}
