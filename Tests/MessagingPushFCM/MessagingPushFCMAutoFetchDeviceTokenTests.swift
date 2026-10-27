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

private class AppDelegateWrappedByCio: NSObject, UIApplicationDelegate {
    var receivedDeviceTokens: [Data] = []

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        receivedDeviceTokens.append(deviceToken)
    }
}

private class CioAppDelegateUsedWithAutoFetch: CioAppDelegate {}

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
