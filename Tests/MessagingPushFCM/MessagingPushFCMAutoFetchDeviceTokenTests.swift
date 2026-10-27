@testable import CioInternalCommon
@testable import CioMessagingPush
@testable import CioMessagingPushFCM
import UIKit
import XCTest

// Swizzling changes a class for the rest of the process, so every test uses its own app delegate class.

private class AppDelegateWithDidRegister: NSObject, UIApplicationDelegate {
    var receivedDeviceTokens: [Data] = []

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        receivedDeviceTokens.append(deviceToken)
    }
}

private class AppDelegateWithDidRegisterInitializedTwice: NSObject, UIApplicationDelegate {
    var receivedDeviceTokens: [Data] = []

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        receivedDeviceTokens.append(deviceToken)
    }
}

private class AppDelegateWithoutDidRegister: NSObject, UIApplicationDelegate {}

/// Stands in for a framework base class such as `FlutterAppDelegate`, with the app delegate as its subclass.
private class BaseAppDelegateWithDidRegister: NSObject, UIApplicationDelegate {
    var receivedDeviceTokens: [Data] = []

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        receivedDeviceTokens.append(deviceToken)
    }
}

private class AppDelegateInheritingDidRegister: BaseAppDelegateWithDidRegister {}

private class AppDelegateSubclassedAfterSwizzling: NSObject, UIApplicationDelegate {
    var receivedDeviceTokens: [Data] = []

    // `dynamic` so the subclass's `super` call goes through the Objective-C runtime, like the proxy subclass's call does.
    @objc dynamic func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        receivedDeviceTokens.append(deviceToken)
    }
}

/// Stands in for the subclass an isa-swizzling SDK, such as Firebase's app delegate proxy, creates at runtime.
private class ProxySubclassOfAppDelegate: AppDelegateSubclassedAfterSwizzling {
    override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }
}

private class AppDelegateWrappedByCio: NSObject, UIApplicationDelegate {
    var receivedDeviceTokens: [Data] = []

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        receivedDeviceTokens.append(deviceToken)
    }
}

private class CioAppDelegateUsedWithAutoFetch: CioAppDelegate {}

/// Works like SwiftUI's app delegate, which implements neither registration callback and forwards them to the
/// `UIApplicationDelegateAdaptor` delegate. Tests use the subclasses so each swizzles its own class.
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

private class ForwardingAppDelegateToAppCode: ForwardingAppDelegate {}

private class ForwardingAppDelegateToCioWrapper: ForwardingAppDelegate {}

private class AppDelegateBehindForwardingDelegate: NSObject, UIApplicationDelegate {
    var receivedDeviceTokens: [Data] = []

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        receivedDeviceTokens.append(deviceToken)
    }
}

class MessagingPushFCMAutoFetchDeviceTokenTests: XCTestCase {
    private let apnsToken = Data([0x01, 0x02, 0x03])
    private var firebaseService: MockFirebaseService!

    override func setUp() {
        super.setUp()

        firebaseService = MockFirebaseService()
        MessagingPushFCM.shared.firebaseService = firebaseService
    }

    override func tearDown() {
        MessagingPushFCM.shared.firebaseService = nil
        firebaseService = nil

        super.tearDown()
    }

    func testAutoFetch_whenAppDelegateImplementsDidRegister_thenAppCodeAndFirebaseRegistrationBothRun() {
        let appDelegate = AppDelegateWithDidRegister()

        MessagingPushFCM.shared.swizzleDidRegisterForRemoteNotifications(of: appDelegate)
        didRegister(appDelegate)

        XCTAssertEqual(appDelegate.receivedDeviceTokens, [apnsToken])
        XCTAssertEqual(firebaseService.apnsToken, apnsToken)
        XCTAssertEqual(firebaseService.fetchTokenCallCount, 1)
    }

    func testAutoFetch_whenAppDelegateDoesNotImplementDidRegister_thenFirebaseRegistrationRuns() {
        let appDelegate = AppDelegateWithoutDidRegister()

        MessagingPushFCM.shared.swizzleDidRegisterForRemoteNotifications(of: appDelegate)
        didRegister(appDelegate)

        XCTAssertEqual(firebaseService.apnsToken, apnsToken)
        XCTAssertEqual(firebaseService.fetchTokenCallCount, 1)
    }

    func testAutoFetch_whenInitializedTwice_thenAppCodeAndFirebaseRegistrationRunOnce() {
        let appDelegate = AppDelegateWithDidRegisterInitializedTwice()

        MessagingPushFCM.shared.swizzleDidRegisterForRemoteNotifications(of: appDelegate)
        MessagingPushFCM.shared.swizzleDidRegisterForRemoteNotifications(of: appDelegate)
        didRegister(appDelegate)

        XCTAssertEqual(appDelegate.receivedDeviceTokens, [apnsToken])
        XCTAssertEqual(firebaseService.fetchTokenCallCount, 1)
    }

    func testAutoFetch_whenDidRegisterIsInherited_thenBothRunAndTheBaseClassIsUnchanged() {
        let appDelegate = AppDelegateInheritingDidRegister()
        let otherInstanceOfBaseClass = BaseAppDelegateWithDidRegister()

        MessagingPushFCM.shared.swizzleDidRegisterForRemoteNotifications(of: appDelegate)
        didRegister(appDelegate)
        didRegister(otherInstanceOfBaseClass)

        XCTAssertEqual(appDelegate.receivedDeviceTokens, [apnsToken])
        XCTAssertEqual(otherInstanceOfBaseClass.receivedDeviceTokens, [apnsToken])
        XCTAssertEqual(firebaseService.fetchTokenCallCount, 1)
    }

    func testAutoFetch_whenAppDelegateIsSubclassedAfterSwizzling_thenAppCodeAndFirebaseRegistrationRunOnce() {
        let appDelegate = AppDelegateSubclassedAfterSwizzling()
        let subclassedAppDelegate = ProxySubclassOfAppDelegate()

        MessagingPushFCM.shared.swizzleDidRegisterForRemoteNotifications(of: appDelegate)
        MessagingPushFCM.shared.swizzleDidRegisterForRemoteNotifications(of: subclassedAppDelegate)
        didRegister(subclassedAppDelegate)

        XCTAssertEqual(subclassedAppDelegate.receivedDeviceTokens, [apnsToken])
        XCTAssertEqual(firebaseService.fetchTokenCallCount, 1)
    }

    func testAutoFetch_whenAppDelegateForwardsDidRegister_thenForwardedAppCodeAndFirebaseRegistrationBothRun() {
        let adaptorAppDelegate = AppDelegateBehindForwardingDelegate()
        let appDelegate = ForwardingAppDelegateToAppCode(target: adaptorAppDelegate)

        MessagingPushFCM.shared.swizzleDidRegisterForRemoteNotifications(of: appDelegate)
        didRegister(appDelegate)

        XCTAssertEqual(adaptorAppDelegate.receivedDeviceTokens, [apnsToken])
        XCTAssertEqual(firebaseService.fetchTokenCallCount, 1)
    }

    func testAutoFetch_whenAppDelegateForwardsToTheCioWrapper_thenWrappedAppCodeAndFirebaseRegistrationRunOnce() {
        let wrappedAppDelegate = AppDelegateWrappedByCio()
        let cioAppDelegate = CioAppDelegateUsedWithAutoFetch(
            messagingPush: MessagingPush.shared,
            appDelegate: wrappedAppDelegate,
            config: { MessagingPushConfigBuilder().build() },
            logger: DIGraphShared.shared.logger
        )
        let appDelegate = ForwardingAppDelegateToCioWrapper(target: cioAppDelegate)

        MessagingPushFCM.shared.swizzleDidRegisterForRemoteNotifications(of: appDelegate)
        didRegister(appDelegate)

        XCTAssertEqual(wrappedAppDelegate.receivedDeviceTokens, [apnsToken])
        XCTAssertEqual(firebaseService.fetchTokenCallCount, 1)
    }

    // The wrapper registers the device itself. This covers `initialize` running before the wrapper's
    // `didFinishLaunching`, which is where `appDelegateIntegratedExplicitly` gets set.
    func testAutoFetch_whenAppDelegateIsTheCioWrapper_thenWrappedAppCodeAndFirebaseRegistrationRunOnce() {
        let wrappedAppDelegate = AppDelegateWrappedByCio()
        let appDelegate = CioAppDelegateUsedWithAutoFetch(
            messagingPush: MessagingPush.shared,
            appDelegate: wrappedAppDelegate,
            config: { MessagingPushConfigBuilder().build() },
            logger: DIGraphShared.shared.logger
        )

        MessagingPushFCM.shared.swizzleDidRegisterForRemoteNotifications(of: appDelegate)
        didRegister(appDelegate)

        XCTAssertEqual(wrappedAppDelegate.receivedDeviceTokens, [apnsToken])
        XCTAssertEqual(firebaseService.fetchTokenCallCount, 1)
    }

    /// Calls the delegate the way UIKit does, through Objective-C dispatch, so the swizzled implementation runs.
    private func didRegister(_ appDelegate: UIApplicationDelegate) {
        appDelegate.application?(UIApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: apnsToken)
    }
}
