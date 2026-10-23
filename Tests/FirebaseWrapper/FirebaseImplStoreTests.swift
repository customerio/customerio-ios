@testable import CioFirebaseWrapper
import CioInternalCommonMocks
import XCTest

class FirebaseImplStoreTests: XCTestCase {
    private var notificationCenter: NotificationCenter!
    private var makeAdapterCallCount = 0

    override func setUp() {
        super.setUp()
        FirebaseImplStore.reset()
        notificationCenter = NotificationCenter()
        makeAdapterCallCount = 0
        TokenOnlyMessagingStub.current = nil
    }

    override func tearDown() {
        FirebaseImplStore.reset()
        super.tearDown()
    }

    // What each `MessagingPushFCM.initialize(withConfig:)` call does.
    private func initializeAdapter() -> FirebaseImpl {
        FirebaseImplStore.adapter { [self] in
            makeAdapterCallCount += 1
            return FirebaseImpl(
                runtime: FirebaseRuntime(messagingClassName: "CioTestTokenOnlyMessaging", installationsClassName: "CioTestInstallations"),
                notificationCenter: notificationCenter,
                logger: LoggerMock()
            )
        }
    }

    private func configureFirebase() -> TokenOnlyMessagingStub {
        let messaging = TokenOnlyMessagingStub()
        messaging.notificationCenter = notificationCenter
        TokenOnlyMessagingStub.current = messaging
        return messaging
    }

    func test_adapter_givenInitializedTwice_expectSameAdapter() {
        let first = initializeAdapter()
        let second = initializeAdapter()

        XCTAssertTrue(first === second)
        XCTAssertEqual(makeAdapterCallCount, 1)
    }

    func test_adapter_givenReinitializedBeforeFirebaseConfigured_expectQueuedAPNsTokenKept() {
        initializeAdapter().apnsToken = Data([0x01])
        let adapter = initializeAdapter()

        let messaging = configureFirebase()
        adapter.flushIfFirebaseIsReady()

        XCTAssertEqual(messaging.apnsToken, Data([0x01]))
    }

    func test_adapter_givenReinitializedAfterFirebaseConfigured_expectAppDelegateStillForwarded() {
        let messaging = configureFirebase()
        let appDelegate = AppMessagingDelegateSpy()
        messaging.delegate = appDelegate
        let first = initializeAdapter()
        let interposer = messaging.delegate

        let second = initializeAdapter()
        messaging.simulateRegistrationRefresh("new-token", isInstallationId: false)

        XCTAssertTrue(messaging.delegate === interposer)
        XCTAssertEqual(appDelegate.tokens, ["new-token"])
        withExtendedLifetime((first, second)) {}
    }
}
