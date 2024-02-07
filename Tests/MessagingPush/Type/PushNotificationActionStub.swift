@testable import CioMessagingPush
import Foundation

public class PushNotificationActionStub: PushNotificationAction {
    public var push: PushNotification
    public var didClickOnPush: Bool

    init(push: PushNotification, didClickOnPush: Bool) {
        self.push = push
        self.didClickOnPush = didClickOnPush
    }
}
