@testable import CioMessagingPush
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

/**
 Contains an example of every public facing SDK function call. This file helps
 us prevent introducing breaking changes to the SDK by accident. If a public function
 of the SDK is modified, this test class will not successfully compile. By not compiling,
 that is a reminder to either fix the compilation and introduce the breaking change or
 fix the mistake and not introduce the breaking change in the code base.
 */
class MessaginPushAPITest: UnitTest {
    func test_allPublicTrackingFunctions() {
        _ = XCTSkip()

        MessagingPush.shared.registerDeviceToken("")
        MessagingPush.shared.deleteDeviceToken()
        MessagingPush.shared.trackMetric(deliveryID: "", event: .converted, deviceToken: "")

        // Not testing userNotificationCenter(didReceive: withCompletionHandler:) because
        // 1. You can't create an instance of UNNotificationResponse
        // 2. This function should only change because an iOS SDK changed it which will require us to
        // introduce a breaking change anyway.
        // MessagingPush.shared.userNotificationCenter(.current(), didReceive: UNNotificationResponse()) {}
    }
}
