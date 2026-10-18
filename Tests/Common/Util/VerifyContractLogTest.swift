// Contract: cio-sdk-tools `verify push` reads these log lines and their key tails (its `docs/verify-contract.md`).
// Renaming any `ev`, key or value meaning here breaks it.

@testable import CioInternalCommon
@testable import CioInternalCommonMocks
import Foundation
import SharedTests
import Testing
import UserNotifications

/// Lines logged by Common, through the real `LoggerImpl`, as they reach the system log.
struct VerifyContractLogTest {
    private let systemLogger = SystemLoggerMock()
    private let logger: LoggerImpl
    private let commonLogger: SdkCommonLoggerImpl

    init() {
        self.logger = LoggerImpl(logger: systemLogger, logLevelStore: LogLevelStoreMock())
        logger.setLogLevel(.debug)
        self.commonLogger = SdkCommonLoggerImpl(logger: logger)
    }

    private var line: String? {
        systemLogger.logReceivedArguments?.message
    }

    // MARK: sdk.state

    @Test
    func sdkState_givenUserTokenAndKey_expectFirst8KeyCharactersOnly() {
        commonLogger.logSdkState(userId: "u-42", deviceToken: "abcd1234", cdpApiKey: "1a2b3c4d5e6f7a8b")

        #expect(line == "[Init] SDK state || ev=sdk.state version=\(SdkVersion.version) user=u-42 token=abcd1234 key=1a2b3c4d")
        #expect(systemLogger.logReceivedArguments?.level == .debug)
    }

    @Test
    func sdkState_givenNothingHeld_expectAnonymousAndNone() {
        commonLogger.logSdkState(userId: nil, deviceToken: nil, cdpApiKey: nil)

        #expect(line == "[Init] SDK state || ev=sdk.state version=\(SdkVersion.version) user=anonymous token=none key=none")
    }

    @Test
    func sdkState_givenEmptyValues_expectAnonymousAndNone() {
        commonLogger.logSdkState(userId: "", deviceToken: "", cdpApiKey: "")

        let reader = LogTailReader(line ?? "")
        #expect(reader?.keys == ["ev", "version", "user", "token", "key"])
        #expect(reader?.values["user"] == "anonymous")
        #expect(reader?.values["token"] == "none")
        #expect(reader?.values["key"] == "none")
    }

    @Test
    func sdkState_givenUserIdWithSpaces_expectDecodesToUserId() {
        commonLogger.logSdkState(userId: "jane doe@example.com", deviceToken: nil, cdpApiKey: "short")

        let reader = LogTailReader(line ?? "")
        #expect(reader?.sentence == "[Init] SDK state")
        #expect(reader?.values["user"] == "jane doe@example.com")
        #expect(reader?.values["key"] == "short")
    }

    // MARK: push.permission

    @Test
    func permission_expectIOSOwnStatusName() {
        NotificationPermissionLog.log(logger, status: .provisional)

        #expect(line == "[Push] Notification permission: provisional || ev=push.permission status=provisional")
    }

    // MARK: push.deep_link

    @Test
    func deepLink_expectUrlDecodesToTheLink() {
        let url = URL(string: "https://example.com/p?q=a%20b&r=1")!

        commonLogger.logHandlingNotificationDeepLink(url: url)

        #expect(line == "[Push] Handling push notification deep link with url: \(url) || ev=push.deep_link url=https://example.com/p?q=a%2520b&r=1")
        #expect(LogTailReader(line ?? "")?.values["url"] == url.absoluteString)
    }

    // MARK: push.deep_link_outcome

    @Test
    func deepLinkOutcome_expectOneOutcomePerSentence() {
        commonLogger.logDeepLinkHandledByCallback()
        #expect(line == "[Push] Deep link handled by host app callback implementation || ev=push.deep_link_outcome outcome=app_callback")

        commonLogger.logDeepLinkHandledByHostApp()
        #expect(line == "[Push] Deep link handled by internal host app navigation || ev=push.deep_link_outcome outcome=app_navigation")

        commonLogger.logDeepLinkHandledExternally()
        #expect(line == "[Push] Deep link handled by system || ev=push.deep_link_outcome outcome=system")

        commonLogger.logDeepLinkWasNotHandled()
        #expect(line == "[Push] Deep link was not handled || ev=push.deep_link_outcome outcome=not_handled")
    }
}
