// import CioMessagingPush // do not import. We want to test that customers only need to import 'CioMessagingPushAPN'
import CioMessagingPushAPN // do not use `@testable` so we can test functions are made public and not `internal`.
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
class MessagingPushAPNAPITest: UnitTest {
    // Test that public functions are accessible by mocked instances
    let mock = MessagingPushAPNInstanceMock()

    func test_allPublicFunctions() throws {
        try skipRunningTest()

        MessagingPush.shared.registerDeviceToken(apnDeviceToken: Data())
        mock.registerDeviceToken(apnDeviceToken: Data())

        MessagingPush.shared.application("", didRegisterForRemoteNotificationsWithDeviceToken: Data())
        mock.application("", didRegisterForRemoteNotificationsWithDeviceToken: Data())

        MessagingPush.shared.application(
            "",
            didFailToRegisterForRemoteNotificationsWithError: CustomerIOError
                .notInitialized
        )
        mock.application(
            "",
            didFailToRegisterForRemoteNotificationsWithError: CustomerIOError
                .notInitialized
        )

        MessagingPush.shared.deleteDeviceToken()
        mock.deleteDeviceToken()

        MessagingPush.shared.trackMetric(deliveryID: "", event: .delivered, deviceToken: "")
        mock.trackMetric(deliveryID: "", event: .delivered, deviceToken: "")
    }

    func test_richPushPublicFunctions() throws {
        try skipRunningTest()

        #if canImport(UserNotifications)
        MessagingPush.shared
            .didReceive(UNNotificationRequest(
                identifier: "",
                content: UNNotificationContent(),
                trigger: nil
            )) { _ in }
        mock.didReceive(UNNotificationRequest(
            identifier: "",
            content: UNNotificationContent(),
            trigger: nil
        )) { _ in }

        MessagingPush.shared.serviceExtensionTimeWillExpire()
        mock.serviceExtensionTimeWillExpire()
        #endif
    }

    func test_deepLinkPublicFunctions() throws {
        try skipRunningTest()

        #if canImport(UserNotifications)
        // Cannot guarantee instance or mock will have userNotificationCenter() function as that function is not
        // available to app extensions.
        _ = MessagingPush.shared.userNotificationCenter(
            .current(),
            didReceive: UNNotificationResponse.testInstance,
            withCompletionHandler: {}
        )
        // custom handler
        let pushContent: CustomerIOParsedPushPayload? = MessagingPush.shared.userNotificationCenter(
            .current(),
            didReceive: UNNotificationResponse
                .testInstance
        )

        // make sure all properties that a customer might care about are all public
        _ = pushContent?.notificationContent
        _ = pushContent?.title
        _ = pushContent?.body
        _ = pushContent?.deepLink
        _ = pushContent?.image
        #endif
    }
}
