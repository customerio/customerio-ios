import Foundation
import SharedTests
import UserNotifications
import XCTest

@testable import CioInternalCommon
@testable import CioMessagingPush

class PushNotificationCenterRegistrarTests: UnitTest {
    private var registrar: PushNotificationCenterRegistrarImpl!
    private var pushEventHandlerMock: PushEventHandlerMock!
    private var pushEventHandlerProxyMock: PushEventHandlerProxyMock!
    private var userNotificationCenterMock: UserNotificationCenterMock!

    override func setUp() {
        super.setUp()

        pushEventHandlerMock = PushEventHandlerMock()
        pushEventHandlerProxyMock = PushEventHandlerProxyMock()
        userNotificationCenterMock = UserNotificationCenterMock()

        registrar = PushNotificationCenterRegistrarImpl(
            pushEventHandler: pushEventHandlerMock,
            pushEventHandlerProxy: pushEventHandlerProxyMock,
            userNotificationCenter: userNotificationCenterMock
        )
    }

    // MARK: activate

    func test_activate_expectSetsSelfAsNotificationCenterDelegate() {
        registrar.activate()

        XCTAssertTrue(userNotificationCenterMock.currentDelegate === registrar)
    }

    func test_activate_givenExistingDelegate_expectExistingDelegateAddedToProxy() {
        let existingDelegate = MockNotificationCenterDelegate()
        userNotificationCenterMock.currentDelegate = existingDelegate

        registrar.activate()

        XCTAssertEqual(pushEventHandlerProxyMock.addPushEventHandlerCallsCount, 1)
    }

    func test_activate_givenNoExistingDelegate_expectNoHandlerAddedToProxy() {
        userNotificationCenterMock.currentDelegate = nil

        registrar.activate()

        XCTAssertFalse(pushEventHandlerProxyMock.addPushEventHandlerCalled)
    }

    // MARK: willPresent

    func test_willPresent_expectCallsPushEventHandler() {
        let expectation = expectation(description: "shouldDisplayPushAppInForeground called")
        pushEventHandlerMock.shouldDisplayPushAppInForegroundClosure = { _, completionHandler in
            expectation.fulfill()
            completionHandler(true)
        }

        registrar.userNotificationCenter(
            UNUserNotificationCenter.mockCenter(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in }
        )

        waitForExpectations(timeout: 2)
    }

    func test_willPresent_givenShouldShowTrue_expectBannerOptions() {
        pushEventHandlerMock.shouldDisplayPushAppInForegroundClosure = { _, completionHandler in
            completionHandler(true)
        }
        var receivedOptions: UNNotificationPresentationOptions?

        registrar.userNotificationCenter(
            UNUserNotificationCenter.mockCenter(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { options in receivedOptions = options }
        )

        XCTAssertNotNil(receivedOptions)
        XCTAssertFalse(receivedOptions!.isEmpty)
    }

    func test_willPresent_givenShouldShowFalse_expectEmptyOptions() {
        pushEventHandlerMock.shouldDisplayPushAppInForegroundClosure = { _, completionHandler in
            completionHandler(false)
        }
        var receivedOptions: UNNotificationPresentationOptions?

        registrar.userNotificationCenter(
            UNUserNotificationCenter.mockCenter(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { options in receivedOptions = options }
        )

        XCTAssertEqual(receivedOptions, [])
    }

    // MARK: didReceive

    func test_didReceive_expectCallsOnPushAction() {
        let expectation = expectation(description: "onPushAction called")
        pushEventHandlerMock.onPushActionClosure = { _, completionHandler in
            expectation.fulfill()
            completionHandler()
        }

        registrar.userNotificationCenter(
            UNUserNotificationCenter.mockCenter(),
            didReceive: UNNotificationResponse.mockResponse(),
            withCompletionHandler: {}
        )

        waitForExpectations(timeout: 2)
    }
}

// MARK: - Test helpers

extension UNNotificationResponse {
    fileprivate static func mockResponse() -> UNNotificationResponse {
        unsafeBitCast(NSObject(), to: UNNotificationResponse.self)
    }
}

extension UNUserNotificationCenter {
    /// Creates a UNUserNotificationCenter instance without calling `.current()`,
    /// which crashes in unit tests due to missing bundle context.
    fileprivate static func mockCenter() -> UNUserNotificationCenter {
        unsafeBitCast(NSObject(), to: UNUserNotificationCenter.self)
    }
}
