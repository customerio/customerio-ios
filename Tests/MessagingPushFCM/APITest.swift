// import CioMessagingPush // do not import. We want to test that customers only need to import 'CioMessagingPushFCM'
import CioMessagingPushFCM // do not use `@testable` so we can test functions are made public and not `internal`.
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

    func test_allPublicFunctions() throws {
        try skipRunningTest()

        // Config is optional because MessagingPushConfigOptions does not have any required fields.
        // Providing default value for config makes it easier for customers to initialize MessagingPush module.
        MessagingPush.initialize()
        MessagingPush.initialize(withConfig: MessagingPushConfigBuilder().build())

        // MessagingPushFCM should be able to be initialized with the same initialize() function as MessagingPush.
        MessagingPushFCM.initialize()
        MessagingPushFCM.initialize(withConfig: MessagingPushConfigBuilder().build())

        // This is the `initialize()` function that's available to Notification Service Extension and not available
        // to other targets (such as iOS).
        // You should be able to uncomment the initialize() function below and should get compile errors saying that the
        // function is not available to iOS.
        // MessagingPush.initialize(withConfig: MessagingPushConfigBuilder(cdpApiKey: .random).build())
        // MessagingPushFCM.initialize(withConfig: MessagingPushConfigBuilder(cdpApiKey: .random).build())

        // `moduleConfig` is not really meant to be accessed by customers, so it is okay to not have it in the mock.
        // However, it is public so we should make sure it does not change.
        _ = MessagingPush.moduleConfig

        MessagingPush.shared.registerDeviceToken(fcmToken: "")
        mock.registerDeviceToken(fcmToken: "")

        MessagingPush.shared.messaging("", didReceiveRegistrationToken: "token")
        mock.messaging("", didReceiveRegistrationToken: "token")

        MessagingPush.shared.messaging("", didReceiveRegistrationToken: nil)
        mock.messaging("", didReceiveRegistrationToken: nil)

        MessagingPush.shared.application(
            "",
            didFailToRegisterForRemoteNotificationsWithError: GenericError.registrationFailed
        )
        mock.application("", didFailToRegisterForRemoteNotificationsWithError: GenericError.registrationFailed)

        MessagingPush.shared.deleteDeviceToken()
        mock.deleteDeviceToken()

        MessagingPush.shared.trackMetric(deliveryID: "", event: .delivered, deviceToken: "")
        mock.trackMetric(deliveryID: "", event: .delivered, deviceToken: "")
    }

    func test_allPublicModuleConfigOptions() throws {
        try skipRunningTest()

        _ = MessagingPushConfigBuilder()
            .autoFetchDeviceToken(true)
            .autoTrackPushEvents(true)
            .showPushAppInForeground(true)
            .build()

        // This is a constructor for `MessagingPushConfigBuilder` that's available to Notification Service Extension and not available
        // to other targets (such as iOS).
        // You should be able to uncomment the initialize() function below and should get compile errors saying that the
        // function is not available to iOS.
        // _ = MessagingPushConfigBuilder(cdpApiKey: .random).build()

        let configOptions: [String: Any] = [:]
        _ = MessagingPushConfigBuilder.build(from: configOptions)
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
