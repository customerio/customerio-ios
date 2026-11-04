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

    private typealias RemoteNotificationIMP = @convention(c) (
        AnyObject, Selector, UIApplication, NSDictionary, @escaping @convention(block) (UIBackgroundFetchResult) -> Void
    ) -> Void

    private let remoteNotificationSelector = #selector(UIApplicationDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:))

    private func callImplementation(_ implementation: IMP, on object: AnyObject, userInfo: [AnyHashable: Any]) -> UIBackgroundFetchResult? {
        var result: UIBackgroundFetchResult?
        unsafeBitCast(implementation, to: RemoteNotificationIMP.self)(
            object, remoteNotificationSelector, UIApplication.shared, userInfo as NSDictionary, { result = $0 }
        )
        return result
    }

    /// Calls the class's own implementation, as an app delegate proxy finds it, skipping `forwardingTarget(for:)`.
    private func callClassImplementation(on delegate: NSObject, userInfo: [AnyHashable: Any]) throws -> UIBackgroundFetchResult? {
        let method = try XCTUnwrap(class_getInstanceMethod(type(of: delegate), remoteNotificationSelector), "A swizzling proxy finds no implementation to call")
        return callImplementation(method_getImplementation(method), on: delegate, userInfo: userInfo)
    }

    /// Does what Firebase's app delegate proxy does: moves `object` to a new subclass with the proxy's own
    /// implementation, and returns the original implementation the proxy then calls.
    private func proxyLikeFirebase(_ object: NSObject) throws -> IMP {
        let realClass: AnyClass = try XCTUnwrap(object_getClass(object))
        let original = try XCTUnwrap(class_getInstanceMethod(realClass, remoteNotificationSelector).map(method_getImplementation))
        let proxyClass: AnyClass = try XCTUnwrap(objc_allocateClassPair(realClass, "TestProxy_\(UUID().uuidString)", 0))
        typealias Donor = @convention(block) (NSObject, UIApplication, NSDictionary, @escaping @convention(block) (UIBackgroundFetchResult) -> Void) -> Void
        let donor: Donor = { _, _, _, completion in completion(.noData) }
        let types = protocol_getMethodDescription(UIApplicationDelegate.self, remoteNotificationSelector, false, true).types
        class_addMethod(proxyClass, remoteNotificationSelector, imp_implementationWithBlock(donor), types.map { UnsafePointer($0) })
        objc_registerClassPair(proxyClass)
        object_setClass(object, proxyClass)
        return original
    }

    func testDidReceiveRemoteNotification_whenCalledOnTheWrapperClass_thenWrappedDelegateHandlesIt() throws {
        let wrapped = BackgroundPushAppDelegate()
        let wrapper = CioProviderAgnosticAppDelegate(messagingPush: mockMessagingPush, appDelegate: wrapped, config: { self.createMockConfig() }, logger: mockLogger)

        let result = try callClassImplementation(on: wrapper, userInfo: ["order_id": "42"])

        XCTAssertEqual(wrapped.receivedUserInfo?["order_id"] as? String, "42")
        XCTAssertEqual(result, .newData)
        XCTAssertTrue(wrapper.responds(to: remoteNotificationSelector))
    }

    func testDidReceiveRemoteNotification_whenAProxyCallsItWithSilentPushOff_thenAppIsNotCalledAsBefore() throws {
        let wrapped = BackgroundPushAppDelegate()
        let wrapper = CioProviderAgnosticAppDelegate(messagingPush: mockMessagingPush, appDelegate: wrapped, config: { self.createMockConfig() }, logger: mockLogger)
        let original = try proxyLikeFirebase(wrapper)

        XCTAssertEqual(callImplementation(original, on: wrapper, userInfo: ["order_id": "42"]), .noData)
        XCTAssertNil(wrapped.receivedUserInfo)
    }

    func testDidReceiveRemoteNotification_whenAProxyCallsItWithSilentPushOn_thenAppHandlesIt() throws {
        let wrapped = BackgroundPushAppDelegate()
        var config = createMockConfig()
        config.backgroundPushEnabled = true
        let wrapper = CioProviderAgnosticAppDelegate(messagingPush: mockMessagingPush, appDelegate: wrapped, config: { config }, logger: mockLogger)
        let original = try proxyLikeFirebase(wrapper)

        XCTAssertEqual(callImplementation(original, on: wrapper, userInfo: ["order_id": "42"]), .newData)
        XCTAssertEqual(wrapped.receivedUserInfo?["order_id"] as? String, "42")
    }

    func testDidReceiveRemoteNotification_whenWrappedDelegateLacksIt_thenWrapperDoesNotClaimItAndCompletesWithNoData() throws {
        XCTAssertFalse(appDelegate.responds(to: remoteNotificationSelector), "UIKit must not treat the app as handling background pushes")

        XCTAssertEqual(try callClassImplementation(on: appDelegate, userInfo: [:]), .noData)
    }

    func testDidReceiveRemoteNotification_whenAppSubclassImplementsIt_thenSubclassRuns() throws {
        // Compiles without `override`, so apps that already implement it in their subclass keep building.
        let subclass = SubclassWithBackgroundPushHandler(messagingPush: mockMessagingPush, appDelegate: mockAppDelegate, logger: mockLogger)

        let result = try callClassImplementation(on: subclass, userInfo: ["order_id": "42"])

        XCTAssertEqual(subclass.receivedUserInfo?["order_id"] as? String, "42")
        XCTAssertEqual(result, .newData)
    }

    func testInstallRemoteNotificationForwarding_whenSwiftUIStyleDelegateForwardsToWrapper_thenAProxyReachesTheApp() throws {
        let wrapped = BackgroundPushAppDelegate()
        var config = createMockConfig()
        config.backgroundPushEnabled = true
        let wrapper = CioProviderAgnosticAppDelegate(messagingPush: mockMessagingPush, appDelegate: wrapped, config: { config }, logger: mockLogger)
        let applicationDelegate = AdaptorStyleAppDelegate(target: wrapper)
        XCTAssertNil(class_getInstanceMethod(AdaptorStyleAppDelegate.self, remoteNotificationSelector))

        wrapper.installRemoteNotificationForwarding(on: applicationDelegate)
        let original = try proxyLikeFirebase(applicationDelegate)

        XCTAssertEqual(callImplementation(original, on: applicationDelegate, userInfo: ["order_id": "42"]), .newData)
        XCTAssertEqual(wrapped.receivedUserInfo?["order_id"] as? String, "42")
    }

    func testInstallRemoteNotificationForwarding_whenAppHasNoHandler_thenDelegateClassIsLeftAlone() {
        // `mockAppDelegate` doesn't handle background pushes.
        let applicationDelegate = NoHandlerAdaptorStyleAppDelegate(target: appDelegate)

        appDelegate.installRemoteNotificationForwarding(on: applicationDelegate)

        XCTAssertNil(class_getInstanceMethod(NoHandlerAdaptorStyleAppDelegate.self, remoteNotificationSelector))
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
    var receivedUserInfo: [AnyHashable: Any]?

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        receivedUserInfo = userInfo
        completionHandler(.newData)
    }
}

private final class SubclassWithBackgroundPushHandler: CioProviderAgnosticAppDelegate {
    var receivedUserInfo: [AnyHashable: Any]?

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        receivedUserInfo = userInfo
        completionHandler(.newData)
    }
}

/// Like SwiftUI's app delegate: forwards to the `UIApplicationDelegateAdaptor` delegate without implementing the callback.
/// Tests patch its subclasses, one per test, as adding a method to a class lasts for the whole test run.
private class AdaptorStyleAppDelegateBase: NSObject, UIApplicationDelegate {
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

private final class AdaptorStyleAppDelegate: AdaptorStyleAppDelegateBase {}

private final class NoHandlerAdaptorStyleAppDelegate: AdaptorStyleAppDelegateBase {}
