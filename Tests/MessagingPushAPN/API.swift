@testable import CioMessagingPush
@testable import CioMessagingPushAPN
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

/**
 Contains an example of every public facing SDK function call. This file helps
 us prevent introducing breaking changes to the SDK by accident. If a public function
 of the SDK is modified, this test class will not successfully compile. By not compiling,
 that is a reminder to either fix the comilation and introduce the breaking change or
 fix the mistake and not introduce the breaking change in the code base.
 */
class MessagingPushAPNAPITest: UnitTest {
    func test_allPublicFunctions() {
        _ = XCTSkip()

        MessagingPush.shared.registerDeviceToken(apnDeviceToken: Data())
        MessagingPush.shared.application("", didRegisterForRemoteNotificationsWithDeviceToken: Data())
        MessagingPush.shared.application("",
                                         didFailToRegisterForRemoteNotificationsWithError: CustomerIOError
                                             .notInitialized)

        MessagingPush.shared
            .didReceive(UNNotificationRequest(identifier: "", content: UNNotificationContent(),
                                              trigger: nil)) { content in }
    }
}
