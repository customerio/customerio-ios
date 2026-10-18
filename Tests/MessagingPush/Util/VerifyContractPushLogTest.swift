// Contract: cio-sdk-tools `verify push` reads these log lines and their key tails (its `docs/verify-contract.md`).
// Renaming any `ev`, key or value meaning here breaks it.

@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioMessagingPush
import Foundation
import SharedTests
import Testing

/// Push lines through the real `PushNotificationLoggerImpl` and `LoggerImpl`, as they reach the system log.
struct VerifyContractPushLogTest {
    private let systemLogger = SystemLoggerMock()
    private let pushLogger: PushNotificationLoggerImpl

    init() {
        let logger = LoggerImpl(logger: systemLogger, logLevelStore: LogLevelStoreMock())
        logger.setLogLevel(.debug)
        self.pushLogger = PushNotificationLoggerImpl(logger: logger)
    }

    private var line: String? {
        systemLogger.logReceivedArguments?.message
    }

    // MARK: push.delivered

    @Test
    func delivered_givenIdWithPadding_expectIdExactlyAsReceived() {
        pushLogger.logTrackingPushMessageDelivered(deliveryId: "dgS_abc==")

        // The test runner is an app, not an `.appex`.
        #expect(line == "[Push] Tracking push message delivered with deliveryId: dgS_abc== || ev=push.delivered id=dgS_abc== in=app")
        #expect(LogTailReader(line ?? "")?.values["id"] == "dgS_abc==")
    }

    @Test
    func delivered_givenEmptyId_expectNone() {
        pushLogger.logTrackingPushMessageDelivered(deliveryId: "")

        #expect(LogTailReader(line ?? "")?.values["id"] == "none")
    }

    @Test
    func processKind_givenAppExtensionBundle_expectExtension() {
        #expect(PushNotificationLoggerImpl.processKind(bundlePath: "/x/App.app/PlugIns/NotificationService.appex") == "extension")
        #expect(PushNotificationLoggerImpl.processKind(bundlePath: "/x/App.app") == "app")
    }

    // MARK: push.clicked

    @Test
    func clicked_givenCioPush_expectCioTrueAndId() {
        pushLogger.logClickedCioPushMessage(deliveryId: "dgS_abc")

        #expect(line == "[Push] Clicked CIO push message || ev=push.clicked cio=true id=dgS_abc")
    }

    @Test
    func clicked_givenNonCioPush_expectCioFalseAndNoId() {
        pushLogger.logClickedNonCioPushMessage()

        #expect(line == "[Push] Clicked non CIO push message, ignoring message || ev=push.clicked cio=false")
    }

    @Test
    func clicked_givenEmptyDeliveryId_expectCioTrueAndIdNone() {
        pushLogger.logClickedPushMessageWithEmptyDeliveryId()

        #expect(line == "[Push] Clicked message with empty deliveryId || ev=push.clicked cio=true id=none")
    }

    // MARK: push.opened

    @Test
    func opened_expectId() {
        pushLogger.logTrackingPushMessageOpened(deliveryId: "dgS_abc")

        #expect(line == "[Push] Tracking push message opened with deliveryId: dgS_abc || ev=push.opened id=dgS_abc")
        #expect(systemLogger.logReceivedArguments?.level == .debug)
    }
}
