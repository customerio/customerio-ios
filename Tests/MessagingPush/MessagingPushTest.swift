import Foundation
import SharedTests
import UIKit
import UserNotifications
import XCTest

@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@_spi(Internal) @testable import CioMessagingPush

class MessagingPushTest: IntegrationTest {
    override func initializeSDKComponents() -> MessagingPushInstance? {
        // We want to manually initialize the module in test functions. So, override this function to disable automatic module initialization.
        nil
    }

    override func setUp() {
        super.setUp()
        UNUserNotificationCenter.swizzleNotificationCenter()
    }

    override func tearDown() {
        UNUserNotificationCenter.unswizzleNotificationCenter()
        MessagingPush.resetNotificationCenterDelegate()
        super.tearDown()
    }

    // MARK: initialize

    func test_initialize_whenAutoTrackPushEventsIsTrue_thenNotificationDelegateIsInstalled() {
        MessagingPush.initialize()

        XCTAssertNotNil(MessagingPush.shared.installedNotificationCenterDelegate)
    }

    func test_initialize_whenAutoTrackPushEventsIsFalse_thenNotificationDelegateIsNotInstalled() {
        MessagingPush.initialize(
            withConfig: MessagingPushConfigBuilder()
                .autoTrackPushEvents(false)
                .build()
        )

        XCTAssertNil(MessagingPush.shared.installedNotificationCenterDelegate)
    }

    /// Verifies that the tracking path inside CioNotificationCenterDelegate — which casts messagingPush
    /// to the concrete MessagingPush type — does not swallow the completionHandler.
    /// initialize() is intentionally not called: the nil implementation returns early without
    /// accessing push properties (which would crash on unsafeBitCast test stubs), so the
    /// test confirms the cast succeeds and the graceful nil-implementation path still calls completionHandler.
    func test_didReceive_whenMessagingPushIsConcreteType_thenCompletionHandlerIsCalled() {
        let delegate = CioNotificationCenterDelegate(
            messagingPush: MessagingPush.shared,
            config: { MessagingPush.moduleConfig },
            wrappedDelegate: nil
        )

        var completionHandlerCalled = false
        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: UNNotificationResponse.testInstance,
            withCompletionHandler: { completionHandlerCalled = true }
        )

        XCTAssertTrue(completionHandlerCalled)
    }

    func test_initialize_whenAutoTrackPushEventsIsTrue_thenExistingDelegateIsWrapped() {
        let existingDelegate = MockNotificationCenterDelegate()
        UNUserNotificationCenter.current().delegate = existingDelegate

        MessagingPush.initialize()

        XCTAssertNotNil(MessagingPush.shared.installedNotificationCenterDelegate)
        MessagingPush.shared.installedNotificationCenterDelegate?.userNotificationCenter(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in }
        )
        XCTAssertTrue(existingDelegate.willPresentNotificationCalled)
    }

    // MARK: initializeForExtension

    func test_initializeForExtension_givenSecretKey_expectNotInitializedAndNoRequests() {
        let httpClientMock = HttpClientMock()
        mockCollection.add(mock: httpClientMock)
        diGraphShared.override(value: httpClientMock, forType: HttpClient.self)
        let givenSecretKey = "sk_us_\(String.random)"

        MessagingPush.initializeExtensionModule(
            config: MessagingPushConfigBuilder(cdpApiKey: givenSecretKey, region: nil).build()
        )

        XCTAssertFalse(MessagingPush.shared.hasBeenInitialized)
        XCTAssertNotEqual(MessagingPush.moduleConfig.cdpApiKey, givenSecretKey)

        var actualContent: UNNotificationContent?
        let handled = MessagingPush.shared.didReceive(makeCIORequest()) { actualContent = $0 }

        XCTAssertFalse(handled)
        XCTAssertEqual(actualContent?.title, "Original")
        XCTAssertFalse(httpClientMock.requestCalled)
        XCTAssertFalse(httpClientMock.downloadFileCalled)
    }

    func test_initializeForExtension_givenPublicKey_expectInitialized() {
        let givenPublicKey = "pk_us_\(String.random)"

        MessagingPush.initializeExtensionModule(
            config: MessagingPushConfigBuilder(cdpApiKey: givenPublicKey, region: nil).build()
        )

        XCTAssertTrue(MessagingPush.shared.hasBeenInitialized)
        XCTAssertEqual(MessagingPush.moduleConfig.cdpApiKey, givenPublicKey)
    }

    func test_initializeForExtension_givenLegacyKey_expectInitialized() {
        let givenLegacyKey = String.random

        MessagingPush.initializeExtensionModule(
            config: MessagingPushConfigBuilder(cdpApiKey: givenLegacyKey, region: nil).build()
        )

        XCTAssertTrue(MessagingPush.shared.hasBeenInitialized)
        XCTAssertEqual(MessagingPush.moduleConfig.cdpApiKey, givenLegacyKey)
    }

    private func makeCIORequest() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Original"
        content.userInfo = [
            "CIO-Delivery-ID": "id",
            "CIO-Delivery-Token": "token"
        ]
        return UNNotificationRequest(identifier: "id", content: content, trigger: nil)
    }
}
