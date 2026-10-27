@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioMessagingPush
@testable import CioMessagingPushAPN
@testable import CioMessagingPushMocks
import UIKit
import XCTest

// Swizzling changes a class for the rest of the process, so every test uses its own app delegate class.

private class AppDelegateWithRegistrationCallbacks: NSObject, UIApplicationDelegate {
    var receivedDeviceTokens: [Data] = []
    var receivedErrorCount = 0

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        receivedDeviceTokens.append(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        receivedErrorCount += 1
    }
}

private class AppDelegateWithRegistrationCallbacksInitializedTwice: NSObject, UIApplicationDelegate {
    var receivedDeviceTokens: [Data] = []
    var receivedErrorCount = 0

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        receivedDeviceTokens.append(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        receivedErrorCount += 1
    }
}

private class AppDelegateWithoutRegistrationCallbacks: NSObject, UIApplicationDelegate {}

private class AppDelegateBehindForwardingDelegate: NSObject, UIApplicationDelegate {
    var receivedDeviceTokens: [Data] = []
    var receivedErrorCount = 0

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        receivedDeviceTokens.append(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        receivedErrorCount += 1
    }
}

/// Works like SwiftUI's app delegate, which implements neither registration callback and forwards them to the
/// `UIApplicationDelegateAdaptor` delegate.
private class ForwardingAppDelegate: NSObject, UIApplicationDelegate {
    private let target: NSObject

    init(target: NSObject) {
        self.target = target
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || target.responds(to: aSelector)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        target.responds(to: aSelector) ? target : nil
    }
}

class MessagingPushAPNAutoFetchDeviceTokenTests: XCTestCase {
    private let apnsToken = Data([0x01, 0x02, 0x03])
    private var implementationMock: MessagingPushInstanceMock!
    private var loggerMock: LoggerMock!

    override func setUp() {
        super.setUp()

        loggerMock = LoggerMock()
        DIGraphShared.shared.override(value: loggerMock, forType: Logger.self)

        implementationMock = MessagingPushInstanceMock()
        MessagingPush.setUpSharedInstanceForUnitTest(
            implementation: implementationMock,
            diGraphShared: DIGraphShared.shared,
            config: MessagingPushConfigBuilder().build()
        )
    }

    override func tearDown() {
        MessagingPush.resetTestEnvironment()
        DIGraphShared.shared.reset()
        implementationMock = nil
        loggerMock = nil

        super.tearDown()
    }

    func testAutoFetch_whenAppDelegateImplementsCallbacks_thenAppCodeAndCustomerIOBothRun() {
        let appDelegate = AppDelegateWithRegistrationCallbacks()

        MessagingPushAPN.shared.swizzleDidRegisterForRemoteNotifications(of: appDelegate)
        didRegister(appDelegate)
        didFailToRegister(appDelegate)

        XCTAssertEqual(appDelegate.receivedDeviceTokens, [apnsToken])
        XCTAssertEqual(implementationMock.registerDeviceTokenReceivedInvocations, ["010203"])
        XCTAssertEqual(appDelegate.receivedErrorCount, 1)
        XCTAssertEqual(registrationFailureLogCount, 1)
        XCTAssertFalse(implementationMock.deleteDeviceTokenCalled)
    }

    func testAutoFetch_whenAppDelegateDoesNotImplementCallbacks_thenCustomerIORuns() {
        let appDelegate = AppDelegateWithoutRegistrationCallbacks()

        MessagingPushAPN.shared.swizzleDidRegisterForRemoteNotifications(of: appDelegate)
        didRegister(appDelegate)
        didFailToRegister(appDelegate)

        XCTAssertEqual(implementationMock.registerDeviceTokenReceivedInvocations, ["010203"])
        XCTAssertEqual(registrationFailureLogCount, 1)
    }

    func testAutoFetch_whenAppDelegateForwardsCallbacks_thenForwardedAppCodeAndCustomerIOBothRun() {
        let adaptorAppDelegate = AppDelegateBehindForwardingDelegate()
        let appDelegate = ForwardingAppDelegate(target: adaptorAppDelegate)

        MessagingPushAPN.shared.swizzleDidRegisterForRemoteNotifications(of: appDelegate)
        didRegister(appDelegate)
        didFailToRegister(appDelegate)

        XCTAssertEqual(adaptorAppDelegate.receivedDeviceTokens, [apnsToken])
        XCTAssertEqual(implementationMock.registerDeviceTokenReceivedInvocations, ["010203"])
        XCTAssertEqual(adaptorAppDelegate.receivedErrorCount, 1)
        XCTAssertEqual(registrationFailureLogCount, 1)
    }

    func testAutoFetch_whenInitializedTwice_thenAppCodeAndCustomerIORunOnce() {
        let appDelegate = AppDelegateWithRegistrationCallbacksInitializedTwice()

        MessagingPushAPN.shared.swizzleDidRegisterForRemoteNotifications(of: appDelegate)
        MessagingPushAPN.shared.swizzleDidRegisterForRemoteNotifications(of: appDelegate)
        didRegister(appDelegate)
        didFailToRegister(appDelegate)

        XCTAssertEqual(appDelegate.receivedDeviceTokens, [apnsToken])
        XCTAssertEqual(implementationMock.registerDeviceTokenReceivedInvocations, ["010203"])
        XCTAssertEqual(appDelegate.receivedErrorCount, 1)
        XCTAssertEqual(registrationFailureLogCount, 1)
    }

    private var registrationFailureLogCount: Int {
        loggerMock.errorReceivedInvocations.filter { $0.message.contains("Failed to register for remote notifications") }.count
    }

    /// Calls the delegate the way UIKit does, through Objective-C dispatch, so the swizzled implementation runs.
    private func didRegister(_ appDelegate: UIApplicationDelegate) {
        appDelegate.application?(UIApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: apnsToken)
    }

    private func didFailToRegister(_ appDelegate: UIApplicationDelegate) {
        appDelegate.application?(UIApplication.shared, didFailToRegisterForRemoteNotificationsWithError: NSError(domain: "test", code: 1))
    }
}
