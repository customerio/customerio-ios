import Foundation
#if canImport(UserNotifications)
import UserNotifications

internal class RichPushRequestHandler {
    private(set) let shared = RichPushRequestHandler()

    private init() {}

    func startRequest(_ request: UNNotificationRequest, completionHandler: @escaping (UNNotificationContent) -> Void) {}
}
#endif
