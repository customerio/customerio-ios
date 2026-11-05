import Foundation
import SharedTests
import UIKit
import UserNotifications
import XCTest

@_spi(Internal) @testable import CioInternalCommon
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

    func test_initializeForExtension_expectNoReceiptSender() {
        MessagingPush.initializeExtensionModule(config: MessagingPushConfigBuilder(cdpApiKey: "pk_us_key", region: nil).build())

        XCTAssertNil(MessagingPush.backgroundPushReceiptSender.wrappedValue)
    }

    private let backgroundPush: [AnyHashable: Any] = [
        "aps": ["content-available": 1],
        "CIO-Background-Version": "1",
        "CIO-Background-Delivery-ID": "delivery",
        "CIO-Background-Delivery-Token": "target",
        "order_id": "42"
    ]

    private struct ReceiptHarness {
        let store: CioAppGroupPendingPushDeliveryStore
        let client: BackgroundDeliveryHttpClientMock
        let sender: BackgroundPushReceiptSender
    }

    /// Installs a receipt sender backed by a temporary file. Sends succeed unless `send` says otherwise.
    /// Its clock stands still, so a slow run never reaches the drain deadline.
    private func installReceiptSender(
        send: @escaping (BackgroundTrackRequest) -> Result<Void, BackgroundDeliveryHttpError> = { _ in .success(()) }
    ) -> ReceiptHarness {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("receipts.json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = CioAppGroupPendingPushDeliveryStore(privateFileURL: file, logger: log)
        let client = BackgroundDeliveryHttpClientMock()
        client.sendTrackEventClosure = { request, done in done(send(request)) }
        let sender = BackgroundPushReceiptSender(store: store, httpClient: client, taskRunner: NoBackgroundTaskRunner(), logger: log, uptime: { 0 })
        MessagingPush.backgroundPushReceiptSender.wrappedValue = sender
        return ReceiptHarness(store: store, client: client, sender: sender)
    }

    func test_backgroundPushBeforeInitialization_savesReceiptAndSendsItOnlyOnceInitialized() async {
        let harness = installReceiptSender()
        XCTAssertFalse(MessagingPush.shared.hasBeenInitialized)

        guard case .received(let payload) = MessagingPush.shared.handleBackgroundPush(userInfo: backgroundPush) else {
            return XCTFail("Background data must reach the host before initialization")
        }
        XCTAssertEqual(payload.data, ["order_id": "42"])
        XCTAssertEqual(harness.store.loadAll().map(\.deliveryId), ["delivery"])
        // Waits for initialize, which knows whether the app tracks automatically.
        await harness.sender.waitUntilIdle()
        XCTAssertEqual(harness.client.sendTrackEventCallsCount, 0)

        MessagingPush.initialize()
        await harness.sender.waitUntilIdle()

        XCTAssertTrue(harness.store.loadAll().isEmpty)
        XCTAssertEqual(harness.client.sendTrackEventReceivedArguments?.request.properties["recipient"] as? String, "target")
    }

    func test_backgroundPushBeforeInitialization_withAutoTrackingOff_sendsNoReceipt() async {
        let harness = installReceiptSender()

        guard case .received = MessagingPush.shared.handleBackgroundPush(userInfo: backgroundPush) else {
            return XCTFail("Background data must reach the host before initialization")
        }
        MessagingPush.initialize(withConfig: MessagingPushConfigBuilder().autoTrackPushEvents(false).build())
        await harness.sender.waitUntilIdle()

        XCTAssertEqual(harness.client.sendTrackEventCallsCount, 0)
        XCTAssertTrue(harness.store.loadAll().isEmpty)
    }

    func test_receiptsRetryWhenDataPipelinePublishesItsReadyProfile() async {
        let keyReady = Synchronized(false)
        let harness = installReceiptSender { _ in keyReady.wrappedValue ? .success(()) : .failure(.missingCdpApiKey) }
        MessagingPush.initialize(withConfig: MessagingPushConfigBuilder().autoTrackPushEvents(false).build())
        harness.sender.enqueue(deliveryID: "delivery", deviceToken: "target", receivedAt: Date())
        await harness.sender.waitUntilIdle()
        XCTAssertEqual(harness.store.loadAll().count, 1)
        keyReady.wrappedValue = true
        await diGraphShared.eventBusHandler.postEventAndWait(AnonymousProfileIdentifiedEvent(identifier: "anonymous"))
        await harness.sender.waitUntilIdle()
        XCTAssertTrue(harness.store.loadAll().isEmpty)
    }

    /// Sends `userInfo` to `delegate` as UIKit does, through Objective-C dispatch.
    private func deliverLikeUIKit(_ userInfo: [AnyHashable: Any], to delegate: UIApplicationDelegate) {
        delegate.application?(UIApplication.shared, didReceiveRemoteNotification: userInfo) { _ in }
    }

    func test_silentPushThroughTheAppDelegateWrapper_recordsDeliveredWithoutAppCode() async {
        let harness = installReceiptSender()
        MessagingPush.initialize()
        let app = RemoteNotificationRecordingAppDelegate(callsHandleBackgroundPush: false)
        let wrapper = CioProviderAgnosticAppDelegate(messagingPush: MessagingPush.shared, appDelegate: app, logger: log)

        deliverLikeUIKit(backgroundPush, to: wrapper)
        await harness.sender.waitUntilIdle()

        XCTAssertEqual(app.receivedUserInfos.count, 1)
        XCTAssertEqual(harness.client.sendTrackEventCallsCount, 1)
        XCTAssertEqual(harness.client.sendTrackEventReceivedArguments?.request.anonymousId, "delivery")
    }

    func test_silentPushThroughTheAppDelegateWrapper_whenAppAlsoCallsHandleBackgroundPush_recordsDeliveredOnce() async {
        let harness = installReceiptSender()
        MessagingPush.initialize()
        let app = RemoteNotificationRecordingAppDelegate(callsHandleBackgroundPush: true)
        let wrapper = CioProviderAgnosticAppDelegate(messagingPush: MessagingPush.shared, appDelegate: app, logger: log)

        deliverLikeUIKit(backgroundPush, to: wrapper)
        await harness.sender.waitUntilIdle()

        XCTAssertEqual(app.results, [.received(CustomerIOBackgroundPush(deliveryID: "delivery", deliveryToken: "target", data: ["order_id": "42"]))])
        XCTAssertEqual(harness.client.sendTrackEventCallsCount, 1)
    }

    func test_silentPushToAWrapperSubclassWithItsOwnHandler_recordsDeliveredWithoutAppCode() async {
        let harness = installReceiptSender()
        MessagingPush.initialize()
        let wrapper = WrapperSubclassWithOwnHandler(messagingPush: MessagingPush.shared, appDelegate: nil, logger: log)

        deliverLikeUIKit(backgroundPush, to: wrapper)
        await harness.sender.waitUntilIdle()

        XCTAssertEqual(wrapper.receivedUserInfos.count, 1)
        XCTAssertEqual(harness.client.sendTrackEventCallsCount, 1)
    }

    func test_silentPushThroughTheOlderCallback_recordsDeliveredWithoutAppCode() async {
        let harness = installReceiptSender()
        MessagingPush.initialize()
        let app = OlderCallbackAppDelegate()
        let wrapper = CioProviderAgnosticAppDelegate(messagingPush: MessagingPush.shared, appDelegate: app, logger: log)
        let olderSelector = NSSelectorFromString("application:didReceiveRemoteNotification:")

        // UIKit calls the older callback only when the delegate lacks the newer one.
        XCTAssertFalse(wrapper.responds(to: #selector(UIApplicationDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:))))
        XCTAssertTrue(wrapper.responds(to: olderSelector))
        wrapper.perform(olderSelector, with: UIApplication.shared, with: backgroundPush)
        await harness.sender.waitUntilIdle()

        XCTAssertEqual(app.receivedUserInfos.count, 1)
        XCTAssertEqual(harness.client.sendTrackEventCallsCount, 1)
    }

    private enum WrapperHandlerSetting: CaseIterable {
        case unset, declines, takes
    }

    func test_wrapperBackgroundPushHandler_eachSetting_completesOnceAndRecordsDeliveredOnce() async throws {
        let harness = installReceiptSender()
        MessagingPush.initialize()
        var expectedSends = 0
        for setting in WrapperHandlerSetting.allCases {
            for throughProxy in [false, true] {
                let label = "\(setting), through proxy: \(throughProxy)"
                var push = backgroundPush
                push["CIO-Background-Delivery-ID"] = "delivery-\(setting)-\(throughProxy)"
                let handlerPushes = Synchronized<[CustomerIOBackgroundPush]>([])
                switch setting {
                case .unset:
                    MessagingPush.wrapperBackgroundPushHandler = nil
                case .declines:
                    MessagingPush.wrapperBackgroundPushHandler = { push, _ in
                        handlerPushes.mutating { $0.append(push) }
                        return false
                    }
                case .takes:
                    MessagingPush.wrapperBackgroundPushHandler = { push, completionHandler in
                        handlerPushes.mutating { $0.append(push) }
                        completionHandler(.newData)
                        return true
                    }
                }
                let app = RemoteNotificationRecordingAppDelegate(callsHandleBackgroundPush: true)
                let wrapper = CioProviderAgnosticAppDelegate(messagingPush: MessagingPush.shared, appDelegate: app, logger: log)
                if throughProxy {
                    try proxyLikeFirebase(wrapper, forwardsWhenClassLacksIt: true)
                }
                var completions: [UIBackgroundFetchResult] = []

                await(wrapper as UIApplicationDelegate).application?(UIApplication.shared, didReceiveRemoteNotification: push) { completions.append($0) }
                await harness.sender.waitUntilIdle()
                expectedSends += 1

                XCTAssertEqual(completions.count, 1, label)
                XCTAssertEqual(harness.client.sendTrackEventCallsCount, expectedSends, label)
                XCTAssertEqual(handlerPushes.wrappedValue.map(\.deliveryID), setting == .unset ? [] : ["delivery-\(setting)-\(throughProxy)"], label)
                XCTAssertEqual(app.receivedUserInfos.count, setting == .takes ? 0 : 1, label)
            }
        }
    }

    func test_wrapperBackgroundPushHandler_otherPushes_neverReachIt() {
        let handlerCalls = Synchronized(0)
        MessagingPush.wrapperBackgroundPushHandler = { _, _ in
            handlerCalls.mutating { $0 += 1 }
            return true
        }
        let app = RemoteNotificationRecordingAppDelegate(callsHandleBackgroundPush: false)
        let wrapper = CioProviderAgnosticAppDelegate(messagingPush: MessagingPush.shared, appDelegate: app, logger: log)
        var unsupported = backgroundPush
        unsupported["CIO-Background-Version"] = "2"

        for userInfo in [["aps": ["content-available": 1], "order_id": "42"], unsupported] {
            deliverLikeUIKit(userInfo, to: wrapper)
        }

        XCTAssertEqual(handlerCalls.wrappedValue, 0)
        XCTAssertEqual(app.receivedUserInfos.count, 2)
    }

    func test_wrapperBackgroundPushHandler_thatNeverCompletes_isCompletedOnceByTheTimeout() async {
        _ = installReceiptSender()
        MessagingPush.initialize()
        MessagingPush.wrapperBackgroundPushTimeout.wrappedValue = 0.01
        let heldCompletion = Synchronized<((UIBackgroundFetchResult) -> Void)?>(nil)
        MessagingPush.wrapperBackgroundPushHandler = { _, completionHandler in
            heldCompletion.wrappedValue = completionHandler
            return true
        }
        let app = RemoteNotificationRecordingAppDelegate(callsHandleBackgroundPush: false)
        let wrapper = CioProviderAgnosticAppDelegate(messagingPush: MessagingPush.shared, appDelegate: app, logger: log)
        let completed = expectation(description: "Completed by the timeout")
        let results = Synchronized<[UIBackgroundFetchResult]>([])

        await(wrapper as UIApplicationDelegate).application?(UIApplication.shared, didReceiveRemoteNotification: backgroundPush) { result in
            results.mutating { $0.append(result) }
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 5)
        // The wrapper SDK answering late, then twice, changes nothing.
        heldCompletion.wrappedValue?(.newData)
        heldCompletion.wrappedValue?(.newData)

        XCTAssertEqual(results.wrappedValue, [.noData])
        XCTAssertTrue(app.receivedUserInfos.isEmpty)
    }

    func test_otherPushThroughTheAppDelegateWrapper_recordsNothing() async {
        let harness = installReceiptSender()
        MessagingPush.initialize()
        let app = RemoteNotificationRecordingAppDelegate(callsHandleBackgroundPush: false)
        let wrapper = CioProviderAgnosticAppDelegate(messagingPush: MessagingPush.shared, appDelegate: app, logger: log)

        deliverLikeUIKit(["aps": ["content-available": 1], "order_id": "42"], to: wrapper)
        await harness.sender.waitUntilIdle()

        XCTAssertEqual(app.receivedUserInfos.count, 1)
        XCTAssertEqual(harness.client.sendTrackEventCallsCount, 0)
        XCTAssertTrue(harness.store.loadAll().isEmpty)
    }
}

/// An app's subclass of the wrapper that handles remote notifications itself and never calls `handleBackgroundPush`.
private final class WrapperSubclassWithOwnHandler: CioProviderAgnosticAppDelegate {
    private(set) var receivedUserInfos: [[AnyHashable: Any]] = []

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        receivedUserInfos.append(userInfo)
        completionHandler(.noData)
    }
}

/// Implements only the callback without a completion handler.
private final class OlderCallbackAppDelegate: NSObject, UIApplicationDelegate {
    private(set) var receivedUserInfos: [[AnyHashable: Any]] = []

    @objc(application:didReceiveRemoteNotification:)
    func olderApplication(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {
        receivedUserInfos.append(userInfo)
    }
}

/// An app delegate with its own remote notification handler.
private final class RemoteNotificationRecordingAppDelegate: NSObject, UIApplicationDelegate {
    private let callsHandleBackgroundPush: Bool
    private(set) var receivedUserInfos: [[AnyHashable: Any]] = []
    private(set) var results: [CustomerIOBackgroundPushResult] = []

    init(callsHandleBackgroundPush: Bool) {
        self.callsHandleBackgroundPush = callsHandleBackgroundPush
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        receivedUserInfos.append(userInfo)
        if callsHandleBackgroundPush {
            results.append(MessagingPush.shared.handleBackgroundPush(userInfo: userInfo))
        }
        completionHandler(.noData)
    }
}
