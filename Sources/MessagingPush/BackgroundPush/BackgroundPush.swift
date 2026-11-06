import Foundation

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
    /// A regular Customer.io push, with `CIO-Delivery-ID` and `CIO-Delivery-Token`, is always this case.
    case notBackground
    /// A Customer.io silent push this SDK can't read, for example one without a delivery token or with a value
    /// that isn't text. Nothing is shown and no receipt is recorded. Complete your handler with `.noData`.
    case unsupported
    /// A Customer.io silent push, with its data.
    case received(CustomerIOBackgroundPush)
}

private enum BackgroundPushParser {
    static func parse(_ userInfo: [AnyHashable: Any]) -> CustomerIOBackgroundPushResult {
        // A push with this pair is a regular Customer.io push, even when its data uses background key names.
        if userInfo["CIO-Delivery-ID"] is String, userInfo["CIO-Delivery-Token"] is String {
            return .notBackground
        }
        let deliveryIDKey = "CIO-Background-Delivery-ID"
        let tokenKey = "CIO-Background-Delivery-Token"
        guard userInfo[deliveryIDKey] != nil else { return .notBackground }
        guard let deliveryID = userInfo[deliveryIDKey] as? String, let token = userInfo[tokenKey] as? String else {
            return .unsupported
        }

        var data: [String: String] = [:]
        for (rawKey, value) in userInfo {
            guard let key = rawKey as? String else { return .unsupported }
            if ["aps", deliveryIDKey, tokenKey].contains(key) || key.hasPrefix("gcm.") || key.hasPrefix("google.") { continue }
            guard let value = value as? String else { return .unsupported }
            data[key] = value
        }
        return .received(CustomerIOBackgroundPush(deliveryID: deliveryID, deliveryToken: token, data: data))
    }
}

public extension MessagingPush {
    /// Reads a Customer.io silent push. It never shows a notification and never tracks Opened.
    ///
    /// Call it from `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` to get the push's data.
    /// Silent pushes need the Remote notifications background mode. Your app owns the completion handler.
    /// iOS allows about 30 seconds: call it once, as soon as your work ends.
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
    /// With `autoTrackPushEvents` on, the push's Delivered receipt is saved before this returns, then sent, and
    /// retried later if sending fails. Apps using `CioAppDelegateWrapper` get the receipt before their handler runs,
    /// and calling this as well doesn't record a second one. It also works before `MessagingPush.initialize`,
    /// which then sends the receipt.
    @available(iOSApplicationExtension, unavailable)
    @discardableResult
    func handleBackgroundPush(userInfo: [AnyHashable: Any]) -> CustomerIOBackgroundPushResult {
        let result = Self.recordBackgroundPush(userInfo: userInfo)
        if result == .unsupported {
            logger.info("Ignoring unsupported background push without displaying a notification")
        }
        return result
    }
}

extension MessagingPush {
    /// Reads `userInfo` and, for a Customer.io silent push with `autoTrackPushEvents` on, saves its Delivered receipt.
    /// `handleBackgroundPush(userInfo:)` and `CioAppDelegateWrapper` both call it; a push both see gets one receipt.
    @available(iOSApplicationExtension, unavailable)
    @discardableResult
    static func recordBackgroundPush(userInfo: [AnyHashable: Any]) -> CustomerIOBackgroundPushResult {
        let receivedAt = Date()
        let result = BackgroundPushParser.parse(userInfo)
        if case .received(let payload) = result, moduleConfig.autoTrackPushEvents {
            backgroundPushReceiptSenderCreatingIfNeeded()
                .enqueue(deliveryID: payload.deliveryID, deviceToken: payload.deliveryToken, receivedAt: receivedAt)
        }
        return result
    }
}
