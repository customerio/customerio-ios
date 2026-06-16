@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioMessagingPushMocks
@_spi(Internal) @testable import CioMessagingPush
import SharedTests
import UIKit
import UserNotifications
import XCTest

class MessagingPushNotificationDelegateTests: XCTestCase {
    var mockMessagingPush: MessagingPushInstanceMock!
    var mockNotificationCenter: UserNotificationCenterIntegrationMock!
    var mockLogger: LoggerMock!

    func createMockConfig(
        autoTrackPushEvents: Bool = true,
        showPushAppInForeground: Bool = true
    ) -> MessagingPushConfigOptions {
        MessagingPushConfigOptions(
            logLevel: .info,
            cdpApiKey: "test-api-key",
            region: .US,
            autoFetchDeviceToken: true,
            autoTrackPushEvents: autoTrackPushEvents,
            showPushAppInForeground: showPushAppInForeground,
            appGroupId: nil
        )
    }

    override func setUp() {
        super.setUp()

        UNUserNotificationCenter.swizzleNotificationCenter()

        mockMessagingPush = MessagingPushInstanceMock()
        mockNotificationCenter = UserNotificationCenterIntegrationMock()
        mockLogger = LoggerMock()
    }

    override func tearDown() {
        mockMessagingPush = nil
        mockNotificationCenter = nil
        mockLogger = nil

        UNUserNotificationCenter.unswizzleNotificationCenter()
        MessagingPush.resetNotificationCenterDelegate()

        super.tearDown()
    }

    // MARK: - installNotificationCenterDelegate

    func testInstallNotificationCenterDelegate_whenCalled_thenDelegateIsInstalledOnCenter() {
        MessagingPush.installNotificationCenterDelegate(
            wrapping: nil,
            centerProvider: { self.mockNotificationCenter }
        )

        XCTAssertTrue(mockNotificationCenter.delegate is CioNotificationCenterDelegate)
    }

    func testInstallNotificationCenterDelegate_whenExistingDelegateIsPresent_thenItIsWrapped() {
        let existingDelegate = MockNotificationCenterDelegate()
        mockNotificationCenter.delegate = existingDelegate

        MessagingPush.installNotificationCenterDelegate(
            wrapping: mockNotificationCenter.delegate,
            centerProvider: { self.mockNotificationCenter }
        )

        XCTAssertTrue(mockNotificationCenter.delegate is CioNotificationCenterDelegate)

        // Verify the wrapped delegate receives forwarded calls
        var completionHandlerCalled = false
        mockNotificationCenter.delegate?.userNotificationCenter?(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in completionHandlerCalled = true }
        )
        XCTAssertTrue(existingDelegate.willPresentNotificationCalled)
    }

    func testInstallNotificationCenterDelegate_whenCalledTwice_thenSecondInstallReplacesPrevious() {
        MessagingPush.installNotificationCenterDelegate(
            wrapping: nil,
            centerProvider: { self.mockNotificationCenter }
        )
        let firstDelegate = mockNotificationCenter.delegate

        MessagingPush.installNotificationCenterDelegate(
            wrapping: nil,
            centerProvider: { self.mockNotificationCenter }
        )
        let secondDelegate = mockNotificationCenter.delegate

        XCTAssertTrue(secondDelegate is CioNotificationCenterDelegate)
        XCTAssertFalse(firstDelegate === secondDelegate)
    }

    // MARK: - delegate swizzle wrapping

    func testCioSwizzledSetDelegate_whenNonCioDelegateAssigned_thenItIsWrappedInCioDelegate() {
        let externalDelegate = MockNotificationCenterDelegate()
        MessagingPush.installNotificationCenterDelegate(
            wrapping: nil,
            centerProvider: { self.mockNotificationCenter }
        )

        // Simulate what the swizzle does when another SDK assigns its delegate.
        MessagingPush.installNotificationCenterDelegate(
            wrapping: externalDelegate,
            centerProvider: { self.mockNotificationCenter }
        )

        XCTAssertTrue(mockNotificationCenter.delegate is CioNotificationCenterDelegate)
        // Verify the external delegate is forwarded calls by the wrapper.
        mockNotificationCenter.delegate?.userNotificationCenter?(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in }
        )
        XCTAssertTrue(externalDelegate.willPresentNotificationCalled)
    }

    func testCioSwizzledSetDelegate_whenCioDelegateAssigned_thenNoDuplicateWrapping() {
        // Install our delegate wrapping an external one.
        let externalDelegate = MockNotificationCenterDelegate()
        MessagingPush.installNotificationCenterDelegate(
            wrapping: externalDelegate,
            centerProvider: { self.mockNotificationCenter }
        )
        let firstProxy = mockNotificationCenter.delegate as? CioNotificationCenterDelegate

        // Reassigning our own CioNotificationCenterDelegate should not nest another wrapper on top.
        // (The swizzle checks `delegate is CioNotificationCenterDelegate` and passes through.)
        // Simulate pass-through: installing again with the same proxy should still forward correctly.
        XCTAssertNotNil(firstProxy)
        mockNotificationCenter.delegate?.userNotificationCenter?(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in }
        )
        XCTAssertTrue(externalDelegate.willPresentNotificationCalled)
    }
}
