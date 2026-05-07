@testable import CioInternalCommon
@_spi(Internal) @testable import CioMessagingPush
import SharedTests
import UIKit
import UserNotifications
import XCTest

class CioNotificationCenterDelegateTests: XCTestCase {
    var mockMessagingPush: MessagingPushInstanceMock!
    var mockNotificationCenterDelegate: MockNotificationCenterDelegate!
    var notificationCenterDelegate: CioNotificationCenterDelegate!

    func createMockConfig(
        showPushAppInForeground: Bool = true
    ) -> MessagingPushConfigOptions {
        MessagingPushConfigOptions(
            logLevel: .info,
            cdpApiKey: "test-api-key",
            region: .US,
            autoFetchDeviceToken: true,
            autoTrackPushEvents: true,
            showPushAppInForeground: showPushAppInForeground,
            appGroupId: nil
        )
    }

    override func setUp() {
        super.setUp()

        UNUserNotificationCenter.swizzleNotificationCenter()

        mockMessagingPush = MessagingPushInstanceMock()
        mockNotificationCenterDelegate = MockNotificationCenterDelegate()

        notificationCenterDelegate = CioNotificationCenterDelegate(
            messagingPush: mockMessagingPush,
            config: { self.createMockConfig() },
            wrappedDelegate: mockNotificationCenterDelegate
        )
    }

    override func tearDown() {
        mockMessagingPush = nil
        mockNotificationCenterDelegate = nil
        notificationCenterDelegate = nil

        UNUserNotificationCenter.unswizzleNotificationCenter()

        super.tearDown()
    }

    // MARK: - willPresent

    func testUserNotificationCenterWillPresent_whenCalled_thenWrappedDelegateIsCalled() {
        var completionHandlerCalled = false
        let completionHandler: (UNNotificationPresentationOptions) -> Void = { _ in
            completionHandlerCalled = true
        }

        notificationCenterDelegate.userNotificationCenter(UNUserNotificationCenter.current(), willPresent: UNNotification.testInstance, withCompletionHandler: completionHandler)

        XCTAssertTrue(mockNotificationCenterDelegate.willPresentNotificationCalled)
        XCTAssertTrue(completionHandlerCalled)
    }

    func testUserNotificationCenterWillPresent_whenWrappedDelegateDoesntImplementMethod_thenDefaultHandlingIsUsed() {
        var completionHandlerCalled = false
        var presentationOptions: UNNotificationPresentationOptions?
        let completionHandler: (UNNotificationPresentationOptions) -> Void = { options in
            completionHandlerCalled = true
            presentationOptions = options
        }

        mockNotificationCenterDelegate.respondsToSelectors = [
            #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:)): false
        ]

        notificationCenterDelegate.userNotificationCenter(UNUserNotificationCenter.current(), willPresent: UNNotification.testInstance, withCompletionHandler: completionHandler)

        XCTAssertFalse(mockNotificationCenterDelegate.willPresentNotificationCalled)
        XCTAssertTrue(completionHandlerCalled)

        if #available(iOS 14.0, *) {
            XCTAssertEqual(presentationOptions, [.list, .banner, .badge, .sound])
        } else {
            XCTAssertEqual(presentationOptions, [.alert, .badge, .sound])
        }
    }

    func testUserNotificationCenterWillPresent_whenWrappedDelegateCallsCompletionHandlerAsync_thenCompletionHandlerIsCalledExactlyOnce() {
        // Regression test: previously the SDK called completionHandler a second time with its own default options
        // when the wrapped delegate deferred the call (e.g. a React Native JS bridge calling back from the JS thread).
        let expectation = XCTestExpectation(description: "Completion handler called")
        expectation.assertForOverFulfill = true
        var callCount = 0
        let completionHandler: (UNNotificationPresentationOptions) -> Void = { _ in
            callCount += 1
            expectation.fulfill()
        }

        mockNotificationCenterDelegate.callWillPresentHandlerAsync = true

        notificationCenterDelegate.userNotificationCenter(UNUserNotificationCenter.current(), willPresent: UNNotification.testInstance, withCompletionHandler: completionHandler)

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(callCount, 1)
        XCTAssertTrue(mockNotificationCenterDelegate.willPresentNotificationCalled)
    }

    func testUserNotificationCenterWillPresent_whenWrappedDelegateDoesntImplementMethodAndShowPushAppInForegroundIsFalse_thenNotificationIsNotShown() {
        var presentationOptions: UNNotificationPresentationOptions?
        let completionHandler: (UNNotificationPresentationOptions) -> Void = { options in
            presentationOptions = options
        }

        let delegate = CioNotificationCenterDelegate(
            messagingPush: mockMessagingPush,
            config: { self.createMockConfig(showPushAppInForeground: false) },
            wrappedDelegate: mockNotificationCenterDelegate
        )

        mockNotificationCenterDelegate.respondsToSelectors = [
            #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:)): false
        ]

        delegate.userNotificationCenter(UNUserNotificationCenter.current(), willPresent: UNNotification.testInstance, withCompletionHandler: completionHandler)

        XCTAssertEqual(presentationOptions, [])
    }

    // MARK: - didReceive

    func testUserNotificationCenterDidReceive_whenNotificationCenterIntegrationIsEnabled_thenWrappedDelegateAndMessagingPushAreCalled() {
        var completionHandlerCalled = false
        let completionHandler = {
            completionHandlerCalled = true
        }

        notificationCenterDelegate.userNotificationCenter(UNUserNotificationCenter.current(), didReceive: UNNotificationResponse.testInstance, withCompletionHandler: completionHandler)

        XCTAssertTrue(mockNotificationCenterDelegate.didReceiveNotificationResponseCalled)
        XCTAssertTrue(completionHandlerCalled)
    }

    func testUserNotificationCenterDidReceive_whenWrappedDelegateCallsCompletionHandlerAsync_thenCompletionHandlerIsCalledExactlyOnce() {
        // Regression test: previously the SDK called completionHandler a second time when the wrapped delegate
        // deferred the call (e.g. a React Native JS bridge calling back from the JS thread).
        let expectation = XCTestExpectation(description: "Completion handler called")
        expectation.assertForOverFulfill = true
        var callCount = 0
        let completionHandler: () -> Void = {
            callCount += 1
            expectation.fulfill()
        }

        mockNotificationCenterDelegate.callDidReceiveHandlerAsync = true

        notificationCenterDelegate.userNotificationCenter(UNUserNotificationCenter.current(), didReceive: UNNotificationResponse.testInstance, withCompletionHandler: completionHandler)

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(callCount, 1)
        XCTAssertTrue(mockNotificationCenterDelegate.didReceiveNotificationResponseCalled)
    }

    func testUserNotificationCenterDidReceive_whenWrappedNotificationCenterDelegateIsNil_thenNotificationCompletionHandlerIsCalled() {
        let delegate = CioNotificationCenterDelegate(
            messagingPush: mockMessagingPush,
            config: { self.createMockConfig() },
            wrappedDelegate: nil
        )
        var completionHandlerCalled = false
        let completionHandler = {
            completionHandlerCalled = true
        }

        delegate.userNotificationCenter(UNUserNotificationCenter.current(), didReceive: UNNotificationResponse.testInstance, withCompletionHandler: completionHandler)

        XCTAssertTrue(completionHandlerCalled)
    }

    // MARK: - openSettingsFor

    func testUserNotificationCenterOpenSettingsFor_whenCalled_thenWrappedDelegateIsCalled() {
        notificationCenterDelegate.userNotificationCenter(UNUserNotificationCenter.current(), openSettingsFor: UNNotification.testInstance)

        XCTAssertTrue(mockNotificationCenterDelegate.openSettingsForNotificationCalled)
    }
}
