@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioMessagingPushMocks
@_spi(Internal) @testable import CioMessagingPush
import SharedTests
import UIKit
import UserNotifications
import XCTest

/// Test-only equivalent of framework lifecycle-provider protocols that are discovered at runtime.
@objc(CioTestAppLifecycleProvider)
private protocol TestAppLifecycleProvider: NSObjectProtocol {
    func addApplicationLifeCycleDelegate(_ delegate: NSObject)
}

private final class LifecycleProviderAppDelegate: NSObject, UIApplicationDelegate, TestAppLifecycleProvider {
    var addedLifecycleDelegate: NSObject?

    func addApplicationLifeCycleDelegate(_ delegate: NSObject) {
        addedLifecycleDelegate = delegate
    }
}

class CioProviderAgnosticAppDelegateTests: XCTestCase {
    // Mock Classes
    var mockMessagingPush: MessagingPushInstanceMock!
    var mockAppDelegate: MockAppDelegate!
    var mockNotificationCenter: UserNotificationCenterIntegrationMock!
    var mockNotificationCenterDelegate: MockNotificationCenterDelegate!
    var mockLogger: LoggerMock!
    var appDelegate: CioProviderAgnosticAppDelegate!

    func createMockConfig(
        autoFetchDeviceToken: Bool = true,
        autoTrackPushEvents: Bool = true,
        showPushAppInForeground: Bool = true
    ) -> MessagingPushConfigOptions {
        MessagingPushConfigOptions(
            logLevel: .info,
            cdpApiKey: "test-api-key",
            region: .US,
            autoFetchDeviceToken: autoFetchDeviceToken,
            autoTrackPushEvents: autoTrackPushEvents,
            showPushAppInForeground: showPushAppInForeground,
            appGroupId: nil,
            apiHost: nil
        )
    }

    override func setUp() {
        super.setUp()

        UNUserNotificationCenter.swizzleNotificationCenter()

        mockMessagingPush = MessagingPushInstanceMock()
        mockAppDelegate = MockAppDelegate()
        mockNotificationCenter = UserNotificationCenterIntegrationMock()
        mockNotificationCenterDelegate = MockNotificationCenterDelegate()
        mockLogger = LoggerMock()

        // Configure mock notification center with a delegate
        mockNotificationCenter.delegate = mockNotificationCenterDelegate

        // Create AppDelegate with mocks
        appDelegate = CioProviderAgnosticAppDelegate(
            messagingPush: mockMessagingPush,
            appDelegate: mockAppDelegate,
            config: { self.createMockConfig() },
            logger: mockLogger
        )
    }

    override func tearDown() {
        mockMessagingPush = nil
        mockAppDelegate = nil
        mockNotificationCenter = nil
        mockNotificationCenterDelegate = nil
        mockLogger = nil
        appDelegate = nil

        UNUserNotificationCenter.unswizzleNotificationCenter()

        MessagingPush.appDelegateIntegratedExplicitly = false
        MessagingPush.resetNotificationCenterDelegate()

        super.tearDown()
    }

    // MARK: - Tests for application(_:didFinishLaunchingWithOptions:)

    func testDidFinishLaunchingWithOptions_whenValidConfigIsUsed_thenAppDelegateIntegratedFlagIsSet() {
        let result = appDelegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        XCTAssertTrue(MessagingPush.appDelegateIntegratedExplicitly)
        XCTAssertTrue(result)
        XCTAssertTrue(mockAppDelegate.didFinishLaunchingCalled)
    }

    func testDidFinishLaunchingWithOptions_whenValidConfigIsUsed_thenTokenIsRequested() {
        _ = appDelegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        XCTAssertTrue(mockLogger.debugCallsCount == 1)
        XCTAssertTrue(mockLogger.debugReceivedInvocations.contains {
            $0.message.contains("CIO: Registering for remote notifications")
        })
    }

    func testDidFinishLaunchingWithOptions_whenValidConfigIsUsed_thenTokenIsNotRequested() {
        appDelegate = CioProviderAgnosticAppDelegate(
            messagingPush: mockMessagingPush,
            appDelegate: mockAppDelegate,
            config: { self.createMockConfig(autoFetchDeviceToken: false) },
            logger: mockLogger
        )

        let result = appDelegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        XCTAssertTrue(result)
        XCTAssertTrue(mockAppDelegate.didFinishLaunchingCalled)
        XCTAssertFalse(mockLogger.debugReceivedInvocations.contains {
            $0.message.contains("CIO: Registering for remote notifications")
        })
    }

    // MARK: - Tests for remote notification registration

    func testDidRegisterForRemoteNotifications_whenCalled_thenWrappedDelegateIsCalled() {
        // Setup
        let application = UIApplication.shared
        let deviceToken = "device_token".data(using: .utf8)!

        // Call the method
        appDelegate.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)

        // Verify behavior
        XCTAssertTrue(mockAppDelegate.didRegisterForRemoteNotificationsCalled)
        XCTAssertEqual(mockAppDelegate.deviceTokenReceived, deviceToken)
    }

    func testDidFailToRegisterForRemoteNotifications_whenCalled_thenWrappedDelegateCalledAndTokenNotDeleted() {
        // Setup
        let application = UIApplication.shared
        let error = NSError(domain: "test", code: 123, userInfo: nil)

        // Call the method
        appDelegate.application(application, didFailToRegisterForRemoteNotificationsWithError: error)

        // Verify behavior
        XCTAssertTrue(mockAppDelegate.didFailToRegisterForRemoteNotificationsCalled)
        XCTAssertEqual((mockAppDelegate.errorReceived as NSError?)?.domain, "test")
        XCTAssertFalse(mockMessagingPush.deleteDeviceTokenCalled)
    }

    // MARK: - Tests for method forwarding

    func testConforms_whenWrappedDelegateConformsToProtocol_thenObjectiveCInvocationIsForwarded() throws {
        let wrappedDelegate = LifecycleProviderAppDelegate()
        appDelegate = CioProviderAgnosticAppDelegate(
            messagingPush: mockMessagingPush,
            appDelegate: wrappedDelegate,
            config: { self.createMockConfig() },
            logger: mockLogger
        )
        let lifecycleDelegate = NSObject()
        let lifecycleProviderProtocol = try XCTUnwrap(NSProtocolFromString("CioTestAppLifecycleProvider"))
        let addLifecycleDelegateSelector = #selector(TestAppLifecycleProvider.addApplicationLifeCycleDelegate(_:))

        XCTAssertTrue(appDelegate.conforms(to: lifecycleProviderProtocol))
        XCTAssertTrue(appDelegate.responds(to: addLifecycleDelegateSelector))
        let forwardingTarget = appDelegate.forwardingTarget(for: addLifecycleDelegateSelector) as AnyObject?
        XCTAssertTrue(forwardingTarget === wrappedDelegate)

        appDelegate.perform(addLifecycleDelegateSelector, with: lifecycleDelegate)

        XCTAssertTrue(wrappedDelegate.addedLifecycleDelegate === lifecycleDelegate)
    }

    func testConforms_whenProtocolIsImplementedByWrapperSuperclass_thenReturnsTrue() throws {
        let applicationDelegateProtocol = try XCTUnwrap(NSProtocolFromString("UIApplicationDelegate"))

        XCTAssertTrue(appDelegate.conforms(to: applicationDelegateProtocol))
    }

    func testConforms_whenWrappedDelegateIsNil_thenForeignProtocolReturnsFalse() throws {
        appDelegate = CioProviderAgnosticAppDelegate(
            messagingPush: mockMessagingPush,
            appDelegate: nil,
            config: { self.createMockConfig() },
            logger: mockLogger
        )
        let tableViewDelegateProtocol = try XCTUnwrap(NSProtocolFromString("UITableViewDelegate"))

        XCTAssertFalse(appDelegate.conforms(to: tableViewDelegateProtocol))
    }

    func testConforms_whenNeitherWrapperNorWrappedDelegateConforms_thenReturnsFalse() throws {
        let tableViewDelegateProtocol = try XCTUnwrap(NSProtocolFromString("UITableViewDelegate"))

        XCTAssertFalse(appDelegate.conforms(to: tableViewDelegateProtocol))
    }

    func testResponds_whenSelectorIsProvided_thenItShouldCorrectlyDetectResponse() {
        // Test all implemented optional methods
        for selector in appDelegate.implementedOptionalMethods {
            XCTAssertTrue(appDelegate.responds(to: selector), "Should respond to \(selector)")
        }

        // Test implementation for methodimplemented by the wrapped app delegate
        let wrappedSelector = #selector(UIApplicationDelegate.applicationDidBecomeActive(_:))
        XCTAssertTrue(appDelegate.responds(to: wrappedSelector), "Should respond to wrapped delegate's selector \(wrappedSelector)")

        // Test a non-implemented method
        let nonImplementedSelector = #selector(UIApplicationDelegate.applicationDidEnterBackground(_:))
        XCTAssertFalse(appDelegate.responds(to: nonImplementedSelector), "Should not respond to \(nonImplementedSelector)")
    }

    func testForwardingTarget_whenSelectorIsProvided_thenItShouldCorrectlyDetectTarget() {
        // Test forwarding for an implemented method
        let implementedSelector = #selector(UIApplicationDelegate.application(_:didFinishLaunchingWithOptions:))
        XCTAssertEqual(appDelegate.forwardingTarget(for: implementedSelector) as? CioProviderAgnosticAppDelegate, appDelegate)

        // Test forwarding for a method implemented by the wrapped app delegate
        let wrappedSelector = #selector(UIApplicationDelegate.applicationDidBecomeActive(_:))
        XCTAssertEqual(appDelegate.forwardingTarget(for: wrappedSelector) as? MockAppDelegate, mockAppDelegate)

        // Test forwarding for a method not implemented by any delegate
        let nonImplementedSelector = #selector(UIApplicationDelegate.applicationDidEnterBackground(_:))
        XCTAssertNil(appDelegate.forwardingTarget(for: nonImplementedSelector))
    }

    // MARK: - Tests for extension methods

    func testApplicationContinueUserActivity_whenCalled_thenWrappedDelegateIsCalled() {
        // Setup
        let userActivity = NSUserActivity(activityType: "test")
        let restorationHandler: ([UIUserActivityRestoring]?) -> Void = { _ in }

        // Call the method
        let result = appDelegate.application(UIApplication.shared, continue: userActivity, restorationHandler: restorationHandler)

        // Verify behavior
        XCTAssertTrue(mockAppDelegate.continueUserActivityCalled)
        XCTAssertTrue(result)
    }

    func testApplicationOpenUrl_whenCalled_thenWrappedDelegateIsCalled() {
        // Setup
        let testUrl = URL(string: "myapp://deeplink")!
        let testOptions: [UIApplication.OpenURLOptionsKey: Any] = [.sourceApplication: "com.test.app"]

        // Call the method
        let result = appDelegate.application(UIApplication.shared, open: testUrl, options: testOptions)

        // Verify behavior
        XCTAssertTrue(mockAppDelegate.openUrlCalled)
        XCTAssertEqual(mockAppDelegate.urlReceived, testUrl)
        XCTAssertEqual(mockAppDelegate.optionsReceived?[.sourceApplication] as? String, "com.test.app")
        XCTAssertTrue(result)
    }

    // MARK: - Background remote notifications

    private let remoteNotificationSelector = #selector(UIApplicationDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:))

    private func makeWrapper(wrapping wrapped: CioAppDelegateType?, backgroundModes: [String] = []) -> CioProviderAgnosticAppDelegate {
        let wrapper = CioProviderAgnosticAppDelegate(messagingPush: mockMessagingPush, appDelegate: wrapped, config: { self.createMockConfig() }, logger: mockLogger)
        wrapper.readBackgroundModes = { backgroundModes }
        return wrapper
    }

    /// Calls the delegate as UIKit does: only when it responds, through Objective-C dispatch.
    /// Returns each completion handler result, or `nil` when UIKit would not call it.
    private func deliverLikeUIKit(to delegate: NSObject, userInfo: [AnyHashable: Any] = ["order_id": "42"]) -> [UIBackgroundFetchResult]? {
        guard delegate.responds(to: remoteNotificationSelector) else { return nil }
        var results: [UIBackgroundFetchResult] = []
        (delegate as? UIApplicationDelegate)?.application?(UIApplication.shared, didReceiveRemoteNotification: userInfo) { results.append($0) }
        return results
    }

    func testWrapperClass_whenCreated_thenHasNoRemoteNotificationMethodOfItsOwn() {
        // A proxy that subclasses the app delegate then finds no method here to call as the original.
        _ = makeWrapper(wrapping: BackgroundPushAppDelegate())

        XCTAssertNil(class_getInstanceMethod(CioProviderAgnosticAppDelegate.self, remoteNotificationSelector))
    }

    func testDidReceiveRemoteNotification_whenUIKitCallsTheWrapper_thenAppHandlesItOnce() {
        let wrapped = BackgroundPushAppDelegate()
        let wrapper = makeWrapper(wrapping: wrapped)

        XCTAssertEqual(deliverLikeUIKit(to: wrapper), [.newData])
        XCTAssertEqual(wrapped.receivedUserInfos.count, 1)
        XCTAssertEqual(wrapped.receivedUserInfos.first?["order_id"] as? String, "42")
    }

    func testDidReceiveRemoteNotification_whenAProxyForwardsLikeGoogleUtilities815_thenAppHandlesItOnce() throws {
        let wrapped = BackgroundPushAppDelegate()
        let wrapper = makeWrapper(wrapping: wrapped)
        try proxyLikeFirebase(wrapper)

        XCTAssertEqual(deliverLikeUIKit(to: wrapper), [.newData])
        XCTAssertEqual(wrapped.receivedUserInfos.count, 1)
    }

    func testDidReceiveRemoteNotification_whenSwiftUIStyleDelegateForwardsToTheWrapperUnderAProxy_thenAppHandlesItOnce() throws {
        let wrapped = BackgroundPushAppDelegate()
        let applicationDelegate = AdaptorStyleAppDelegate(target: makeWrapper(wrapping: wrapped))
        try proxyLikeFirebase(applicationDelegate)

        XCTAssertEqual(deliverLikeUIKit(to: applicationDelegate), [.newData])
        XCTAssertEqual(wrapped.receivedUserInfos.count, 1)
    }

    func testResponds_whenAppHasNoHandlerAndNoBackgroundMode_thenUIKitDoesNotCallTheWrapper() {
        // `mockAppDelegate` doesn't handle remote notifications.
        XCTAssertNil(deliverLikeUIKit(to: makeWrapper(wrapping: mockAppDelegate)))
    }

    func testResponds_whenAppHasNoHandlerButHasTheBackgroundMode_thenWrapperTakesItAndCompletesWithNoData() {
        let wrapper = makeWrapper(wrapping: mockAppDelegate, backgroundModes: ["remote-notification"])

        XCTAssertEqual(deliverLikeUIKit(to: wrapper), [.noData])
    }

    func testResponds_whenAppHasOnlyTheOlderCallback_thenWrapperDoesNotTakeItFromUIKit() {
        let wrapper = makeWrapper(wrapping: LegacyRemoteNotificationAppDelegate(), backgroundModes: ["remote-notification"])

        XCTAssertFalse(wrapper.responds(to: remoteNotificationSelector))
    }

    func testDidReceiveRemoteNotification_whenAppSubclassImplementsIt_thenSubclassRuns() {
        // Compiles without `override`, so apps that already implement it in their subclass keep building.
        let subclass = SubclassWithBackgroundPushHandler(messagingPush: mockMessagingPush, appDelegate: mockAppDelegate, logger: mockLogger)

        XCTAssertEqual(deliverLikeUIKit(to: subclass), [.newData])
        XCTAssertEqual(subclass.receivedUserInfo?["order_id"] as? String, "42")
    }

    func testRespondsToApplicationOpenUrl_whenSelectorIsInImplementedMethods_thenReturnsTrue() {
        // Test that the app delegate responds to the URL opening selector
        let urlSelector = #selector(UIApplicationDelegate.application(_:open:options:))
        XCTAssertTrue(appDelegate.responds(to: urlSelector), "AppDelegate should respond to application(_:open:options:) selector")

        // More importantly, test that it's handled by CioAppDelegate itself, not just forwarded
        XCTAssertEqual(appDelegate.forwardingTarget(for: urlSelector) as? CioProviderAgnosticAppDelegate, appDelegate, "URL handling should be handled by CioAppDelegate, not forwarded to wrapped delegate")
    }
}

private final class BackgroundPushAppDelegate: NSObject, UIApplicationDelegate {
    var receivedUserInfos: [[AnyHashable: Any]] = []

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        receivedUserInfos.append(userInfo)
        completionHandler(.newData)
    }
}

/// Implements only the callback without a completion handler, which UIKit calls when the delegate lacks the newer one.
private final class LegacyRemoteNotificationAppDelegate: NSObject, UIApplicationDelegate {
    @objc(application:didReceiveRemoteNotification:)
    func legacyApplication(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {}
}

private final class SubclassWithBackgroundPushHandler: CioProviderAgnosticAppDelegate {
    var receivedUserInfo: [AnyHashable: Any]?

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        receivedUserInfo = userInfo
        completionHandler(.newData)
    }
}

/// Like SwiftUI's app delegate: forwards to the `UIApplicationDelegateAdaptor` delegate without implementing the callback.
private final class AdaptorStyleAppDelegate: NSObject, UIApplicationDelegate {
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
