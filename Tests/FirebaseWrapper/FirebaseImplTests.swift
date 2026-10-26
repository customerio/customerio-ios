@testable import CioFirebaseWrapper
import CioInternalCommon
import CioInternalCommonMocks
import CioMessagingPushFCM
import UIKit
import XCTest

private final class FirebaseServiceDelegateSpy: FirebaseServiceDelegate {
    var tokens: [String?] = []
    var registrations: [String?] = []

    func didReceiveRegistrationToken(_ token: String?) {
        tokens.append(token)
    }

    func didReceiveRegistration(_ installationId: String?) {
        registrations.append(installationId)
    }
}

class FirebaseImplTests: XCTestCase {
    private var notificationCenter: NotificationCenter!
    private var logger: LoggerMock!
    private var serviceDelegate: FirebaseServiceDelegateSpy!
    private var installationIdEnabledInInfoPlist = false

    override func setUp() {
        super.setUp()
        notificationCenter = NotificationCenter()
        logger = LoggerMock()
        serviceDelegate = FirebaseServiceDelegateSpy()
        installationIdEnabledInInfoPlist = false
        TokenOnlyMessagingStub.current = nil
        FIDMessagingStub.current = nil
        IncompatibleMessagingStub.current = nil
        InstallationsStub.current = nil
    }

    // MARK: - Helpers

    private func makeImpl(messagingClassName: String) -> FirebaseImpl {
        let impl = FirebaseImpl(
            runtime: FirebaseRuntime(messagingClassName: messagingClassName, installationsClassName: "CioTestInstallations"),
            notificationCenter: notificationCenter,
            logger: logger,
            isInstallationIdEnabledInInfoPlist: { [weak self] in self?.installationIdEnabledInInfoPlist ?? false }
        )
        impl.delegate = serviceDelegate
        return impl
    }

    @discardableResult
    private func configureTokenOnlyFirebase() -> TokenOnlyMessagingStub {
        let messaging = TokenOnlyMessagingStub()
        messaging.notificationCenter = notificationCenter
        TokenOnlyMessagingStub.current = messaging
        return messaging
    }

    @discardableResult
    private func configureFIDFirebase(installationId: String? = "fid-123") -> FIDMessagingStub {
        let messaging = FIDMessagingStub()
        messaging.notificationCenter = notificationCenter
        FIDMessagingStub.current = messaging
        let installations = InstallationsStub()
        installations.installationId = installationId
        InstallationsStub.current = installations
        return messaging
    }

    // What `FirebaseApp.configure()` posts; the adapter reacts on the next main-queue turn.
    private func postFirebaseAppReady(isDefaultApp: Bool = true) {
        notificationCenter.post(name: FirebaseImpl.firebaseAppReadyNotification, object: nil, userInfo: ["FIRAppIsDefaultAppKey": NSNumber(value: isDefaultApp)])
        drainMainQueue()
    }

    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }

    // MARK: - Availability

    func test_availability_givenMessagingNotLinked_expectMissingAndNotLinkedError() {
        let impl = makeImpl(messagingClassName: "CioTestMissingMessaging")
        var receivedError: Error?

        impl.fetchToken { _, error in receivedError = error }

        XCTAssertEqual(impl.availability, .missing)
        XCTAssertEqual(receivedError as? FirebaseImplError, .firebaseMessagingNotLinked)
    }

    func test_availability_givenTokenMethodWithDifferentSignature_expectIncompatibleAndNotCalled() {
        let messaging = IncompatibleMessagingStub()
        IncompatibleMessagingStub.current = messaging
        let impl = makeImpl(messagingClassName: "CioTestIncompatibleMessaging")
        var receivedError: Error?

        impl.fetchToken { _, error in receivedError = error }

        XCTAssertEqual(impl.availability, .incompatible(unsatisfied: ["tokenWithCompletion:"]))
        XCTAssertEqual(receivedError as? FirebaseImplError, .incompatibleFirebase(unsatisfied: ["tokenWithCompletion:"]))
        XCTAssertEqual(messaging.tokenCallCount, 0)
        XCTAssertNil(messaging.delegate)
    }

    // MARK: - Firebase configured

    func test_apnsToken_givenFirebaseConfigured_expectSetOnMessaging() {
        let messaging = configureTokenOnlyFirebase()
        let impl = makeImpl(messagingClassName: "CioTestTokenOnlyMessaging")
        let token = Data([0x01, 0x02])

        impl.apnsToken = token

        XCTAssertEqual(messaging.apnsToken, token)
        XCTAssertEqual(impl.apnsToken, token)
    }

    func test_fetchToken_givenFirebaseConfigured_expectTokenFromMessaging() {
        let messaging = configureTokenOnlyFirebase()
        messaging.token = "fcm-token"
        let impl = makeImpl(messagingClassName: "CioTestTokenOnlyMessaging")
        var received: String?

        impl.fetchToken { token, _ in received = token }

        XCTAssertEqual(received, "fcm-token")
    }

    // MARK: - Before FirebaseApp.configure()

    func test_apnsToken_givenSetBeforeFirebaseConfigured_expectLatestAppliedOnceReady() {
        let impl = makeImpl(messagingClassName: "CioTestTokenOnlyMessaging")
        impl.apnsToken = Data([0x01])
        impl.apnsToken = Data([0x02])
        XCTAssertEqual(impl.apnsToken, Data([0x02]))

        let messaging = configureTokenOnlyFirebase()
        postFirebaseAppReady()

        XCTAssertEqual(messaging.apnsToken, Data([0x02]))
        XCTAssertEqual(messaging.apnsTokenSetCount, 1)
    }

    func test_apnsToken_givenClearedBeforeFirebaseConfigured_expectClearedOnceReady() {
        let impl = makeImpl(messagingClassName: "CioTestTokenOnlyMessaging")
        impl.apnsToken = Data([0x01])
        impl.apnsToken = nil

        let messaging = configureTokenOnlyFirebase()
        messaging.apnsToken = Data([0xFF])
        messaging.apnsTokenSetCount = 0
        postFirebaseAppReady()

        XCTAssertNil(messaging.apnsToken)
        XCTAssertEqual(messaging.apnsTokenSetCount, 1)
    }

    func test_fetchToken_givenRequestedBeforeFirebaseConfigured_expectCompletedOnceAfterAPNsToken() {
        let impl = makeImpl(messagingClassName: "CioTestTokenOnlyMessaging")
        var results: [String?] = []
        impl.apnsToken = Data([0x01])
        impl.fetchToken { token, _ in results.append(token) }
        XCTAssertTrue(results.isEmpty)

        let messaging = configureTokenOnlyFirebase()
        messaging.token = "fcm-token"
        postFirebaseAppReady()
        impl.flushIfFirebaseIsReady()

        XCTAssertEqual(results, ["fcm-token"])
        XCTAssertEqual(messaging.tokenCallCount, 1)
        XCTAssertEqual(messaging.apnsTokenWhenTokenRequested, Data([0x01]))
    }

    func test_firebaseAppReady_givenNonDefaultApp_expectStillWaiting() {
        let impl = makeImpl(messagingClassName: "CioTestTokenOnlyMessaging")
        var completed = false
        impl.fetchToken { _, _ in completed = true }

        let messaging = configureTokenOnlyFirebase()
        postFirebaseAppReady(isDefaultApp: false)

        XCTAssertFalse(completed)
        XCTAssertEqual(messaging.tokenCallCount, 0)
    }

    func test_didBecomeActive_givenFirebaseConfiguredSinceRequest_expectQueuedFetchCompleted() {
        let impl = makeImpl(messagingClassName: "CioTestTokenOnlyMessaging")
        var completed = false
        impl.fetchToken { _, _ in completed = true }

        configureTokenOnlyFirebase()
        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertTrue(completed)
    }

    func test_fetchToken_givenFirebaseNotConfigured_expectWaitingLoggedOnce() {
        let impl = makeImpl(messagingClassName: "CioTestTokenOnlyMessaging")

        impl.fetchToken { _, _ in }
        impl.apnsToken = Data([0x01])

        XCTAssertEqual(logger.infoCallsCount, 1)
    }

    // MARK: - Firebase Installation ID

    func test_isInstallationIdEnabled_givenFirebaseNotConfigured_expectFirebasesRule() {
        let fidImpl = makeImpl(messagingClassName: "CioTestFIDMessaging")
        InstallationsStub.current = nil

        installationIdEnabledInInfoPlist = true
        XCTAssertTrue(fidImpl.isInstallationIdEnabled)
        installationIdEnabledInInfoPlist = false
        XCTAssertFalse(fidImpl.isInstallationIdEnabled)

        installationIdEnabledInInfoPlist = true
        XCTAssertFalse(makeImpl(messagingClassName: "CioTestTokenOnlyMessaging").isInstallationIdEnabled)
    }

    func test_isInstallationIdEnabled_givenFirebaseConfigured_expectMessagingValue() {
        let messaging = configureFIDFirebase()
        messaging.installationIdEnabled = true

        XCTAssertTrue(makeImpl(messagingClassName: "CioTestFIDMessaging").isInstallationIdEnabled)
    }

    func test_fetchInstallationId_givenRequestedBeforeFirebaseConfigured_expectRegisteredAndFIDOnceReady() {
        let impl = makeImpl(messagingClassName: "CioTestFIDMessaging")
        var results: [String?] = []
        impl.fetchInstallationId { fid, _ in results.append(fid) }
        XCTAssertTrue(results.isEmpty)

        let messaging = configureFIDFirebase(installationId: "fid-123")
        postFirebaseAppReady()

        XCTAssertEqual(results, ["fid-123"])
        XCTAssertEqual(messaging.registerCallCount, 1)
    }

    func test_fetchInstallationId_givenRegistrationFails_expectError() {
        let messaging = configureFIDFirebase()
        messaging.registerError = NSError(domain: "test", code: 1)
        var received: String?
        var receivedError: Error?

        makeImpl(messagingClassName: "CioTestFIDMessaging").fetchInstallationId { fid, error in
            received = fid
            receivedError = error
        }

        XCTAssertNil(received)
        XCTAssertNotNil(receivedError)
    }

    func test_fetchInstallationId_givenFirebaseWithoutFID_expectNilWithoutError() {
        configureTokenOnlyFirebase()
        var called = false
        var received: String?
        var receivedError: Error?

        makeImpl(messagingClassName: "CioTestTokenOnlyMessaging").fetchInstallationId { fid, error in
            called = true
            received = fid
            receivedError = error
        }

        XCTAssertTrue(called)
        XCTAssertNil(received)
        XCTAssertNil(receivedError)
    }

    // MARK: - Registration updates

    func test_refresh_givenAppDelegateSetBefore_expectBothGetItOnce() {
        let messaging = configureTokenOnlyFirebase()
        let appDelegate = AppMessagingDelegateSpy()
        messaging.delegate = appDelegate
        let impl = makeImpl(messagingClassName: "CioTestTokenOnlyMessaging")

        messaging.simulateRegistrationRefresh("new-token", isInstallationId: false)

        XCTAssertTrue(messaging.delegate is FirebaseMessagingDelegateInterposer)
        XCTAssertEqual(appDelegate.tokens, ["new-token"])
        XCTAssertEqual(serviceDelegate.tokens, ["new-token"])
        withExtendedLifetime(impl) {}
    }

    func test_refresh_givenNoAppDelegate_expectServiceGetsItOnce() {
        let messaging = configureTokenOnlyFirebase()
        let impl = makeImpl(messagingClassName: "CioTestTokenOnlyMessaging")

        messaging.simulateRegistrationRefresh("new-token", isInstallationId: false)
        messaging.simulateRegistrationRefresh("newer-token", isInstallationId: false)

        XCTAssertEqual(serviceDelegate.tokens, ["new-token", "newer-token"])
        withExtendedLifetime(impl) {}
    }

    func test_refresh_givenFIDMode_expectRegistrationForwardedOnce() {
        let messaging = configureFIDFirebase()
        messaging.installationIdEnabled = true
        let appDelegate = AppMessagingDelegateSpy()
        messaging.delegate = appDelegate
        let impl = makeImpl(messagingClassName: "CioTestFIDMessaging")

        messaging.simulateRegistrationRefresh("new-fid", isInstallationId: true)

        XCTAssertEqual(serviceDelegate.registrations, ["new-fid"])
        XCTAssertTrue(serviceDelegate.tokens.isEmpty)
        XCTAssertEqual(appDelegate.registrations, ["new-fid"])
        withExtendedLifetime(impl) {}
    }

    func test_refresh_givenAppReplacesDelegateLater_expectNotificationFallbackOnce() {
        let messaging = configureTokenOnlyFirebase()
        let impl = makeImpl(messagingClassName: "CioTestTokenOnlyMessaging")
        let laterAppDelegate = AppMessagingDelegateSpy()
        messaging.delegate = laterAppDelegate

        messaging.simulateRegistrationRefresh("new-token", isInstallationId: false)

        XCTAssertEqual(laterAppDelegate.tokens, ["new-token"])
        XCTAssertEqual(serviceDelegate.tokens, ["new-token"])
        withExtendedLifetime(impl) {}
    }

    func test_refresh_givenChainingDelegateInstalledLater_expectServiceGetsItOnce() {
        let messaging = configureTokenOnlyFirebase()
        let impl = makeImpl(messagingClassName: "CioTestTokenOnlyMessaging")
        let chaining = ChainingMessagingDelegate()
        chaining.previous = messaging.delegate as? NSObject
        messaging.delegate = chaining

        messaging.simulateRegistrationRefresh("new-token", isInstallationId: false)

        XCTAssertEqual(chaining.tokens, ["new-token"])
        XCTAssertEqual(serviceDelegate.tokens, ["new-token"])
        withExtendedLifetime(impl) {}
    }

    func test_interposer_givenOtherDelegateCallback_expectForwardedToAppDelegate() {
        let messaging = configureTokenOnlyFirebase()
        let appDelegate = AppMessagingDelegateSpy()
        messaging.delegate = appDelegate
        let impl = makeImpl(messagingClassName: "CioTestTokenOnlyMessaging")
        let didUnregister = NSSelectorFromString("messaging:didUnregister:")
        let interposer = messaging.delegate as? NSObject

        XCTAssertEqual(interposer?.responds(to: didUnregister), true)
        _ = interposer?.perform(didUnregister, with: messaging, with: "old-fid" as NSString)

        XCTAssertEqual(appDelegate.unregistrations, ["old-fid"])
        withExtendedLifetime(impl) {}
    }

    func test_interposer_givenFirebaseConfiguredAfterInit_expectInstalledOnceReady() {
        let impl = makeImpl(messagingClassName: "CioTestTokenOnlyMessaging")
        let messaging = configureTokenOnlyFirebase()
        let appDelegate = AppMessagingDelegateSpy()
        messaging.delegate = appDelegate

        postFirebaseAppReady()
        messaging.simulateRegistrationRefresh("new-token", isInstallationId: false)

        XCTAssertTrue(messaging.delegate is FirebaseMessagingDelegateInterposer)
        XCTAssertEqual(appDelegate.tokens, ["new-token"])
        XCTAssertEqual(serviceDelegate.tokens, ["new-token"])
        withExtendedLifetime(impl) {}
    }
}
