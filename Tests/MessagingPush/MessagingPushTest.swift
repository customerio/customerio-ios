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

    func test_backgroundReadinessIsFalseWhenHostLacksRemoteNotificationMode() {
        let events = EventBusHandlerMock()
        diGraphShared.override(value: events, forType: EventBusHandler.self)
        MessagingPush.initialize(withConfig: MessagingPushConfigBuilder().autoTrackPushEvents(false).backgroundPushEnabled(true).build())
        let readiness = events.postEventReceivedInvocations.compactMap { $0 as? BackgroundPushReadinessChangedEvent }
        XCTAssertEqual(readiness.count, 1)
        XCTAssertEqual(readiness.first?.ready, false)
    }

    func test_extensionNeverPublishesHostReadiness() {
        let events = EventBusHandlerMock()
        diGraphShared.override(value: events, forType: EventBusHandler.self)
        MessagingPush.initializeExtensionModule(config: MessagingPushConfigBuilder().backgroundPushEnabled(true).build())
        XCTAssertFalse(events.postEventReceivedInvocations.contains { $0 is BackgroundPushReadinessChangedEvent })
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
    private func installReceiptSender(
        send: @escaping (BackgroundTrackRequest) -> Result<Void, BackgroundDeliveryHttpError> = { _ in .success(()) }
    ) -> ReceiptHarness {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("receipts.json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = CioAppGroupPendingPushDeliveryStore(privateFileURL: file, logger: log)
        let client = BackgroundDeliveryHttpClientMock()
        client.sendTrackEventClosure = { request, done in done(send(request)) }
        let sender = BackgroundPushReceiptSender(store: store, httpClient: client, taskRunner: NoBackgroundTaskRunner(), logger: log)
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
}
