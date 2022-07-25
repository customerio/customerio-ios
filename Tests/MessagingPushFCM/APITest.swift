// import CioMessagingPush // do not import. We want to test that customers only need to import 'CioMessagingPushFCM'
import CioMessagingPushFCM // do not use `@testable` so we can test functions are made public and not `internal`.
import CioTracking // do not use `@testable` so we can test functions are made public and not `internal`.
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
class MessagingPushFCMAPITest: UnitTest {
    // Test that public functions are accessible by mocked instances
    let mock = MessagingPushFCMInstanceMock()
    // Test that all public functions are accessible by non-singleton instances
    let instance: MessagingPushFCMInstance = MessagingPushFCM(customerIO: CustomerIO(siteId: "", apiKey: ""))

    func test_allPublicFunctions() throws {
        try skipRunningTest()

        MessagingPush.shared.registerDeviceToken(fcmToken: "")
        mock.registerDeviceToken(fcmToken: "")
        instance.registerDeviceToken(fcmToken: "")

        MessagingPush.shared.messaging("", didReceiveRegistrationToken: "token")
        mock.messaging("", didReceiveRegistrationToken: "token")
        instance.messaging("", didReceiveRegistrationToken: "token")

        MessagingPush.shared.messaging("", didReceiveRegistrationToken: nil)
        mock.messaging("", didReceiveRegistrationToken: nil)
        instance.messaging("", didReceiveRegistrationToken: nil)

        MessagingPush.shared.application("",
                                         didFailToRegisterForRemoteNotificationsWithError: CustomerIOError
                                             .notInitialized)
        mock.application("", didFailToRegisterForRemoteNotificationsWithError: CustomerIOError.notInitialized)
        instance.application("", didFailToRegisterForRemoteNotificationsWithError: CustomerIOError.notInitialized)

        MessagingPush.shared.deleteDeviceToken()
        mock.deleteDeviceToken()
        instance.deleteDeviceToken()

        MessagingPush.shared.trackMetric(deliveryID: "", event: .delivered, deviceToken: "")
        mock.trackMetric(deliveryID: "", event: .delivered, deviceToken: "")
        instance.trackMetric(deliveryID: "", event: .delivered, deviceToken: "")

        #if canImport(UserNotifications)
        MessagingPush.shared
            .didReceive(UNNotificationRequest(identifier: "", content: UNNotificationContent(),
                                              trigger: nil)) { _ in }
        mock.didReceive(UNNotificationRequest(identifier: "", content: UNNotificationContent(),
                                              trigger: nil)) { _ in }
        instance.didReceive(UNNotificationRequest(identifier: "", content: UNNotificationContent(),
                                                  trigger: nil)) { _ in }

        MessagingPush.shared.serviceExtensionTimeWillExpire()
        instance.serviceExtensionTimeWillExpire()
        mock.serviceExtensionTimeWillExpire()

        _ = MessagingPush.shared.userNotificationCenter(.current(), didReceive: UNNotificationResponse.testInstance,
                                                        withCompletionHandler: {})
        // Cannot guarantee instance or mock will have userNotificationCenter() function as that function is not available to app extensions.
        #endif
    }
}
