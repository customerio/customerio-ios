@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

class MessagingInAppImplementationTest: IntegrationTest {
    private var messagingInApp: MessagingInAppImplementation {
        // get MessagingInAppImplementation instance so we can call its methods directly
        (MessagingInApp.shared.implementation as! MessagingInAppImplementation) // swiftlint:disable:this force_cast
    }

    private var eventBusHandler: EventBusHandler {
        diGraphShared.eventBusHandler
    }

    private let gistProviderMock = GistProviderMock()
    private let eventListenerMock = InAppEventListenerMock()
    private let inAppMessageManagerMock = InAppMessageManagerMock()

    override func setUpDependencies() {
        super.setUpDependencies()

        diGraphShared.override(value: gistProviderMock, forType: GistProvider.self)
        diGraphShared.override(value: inAppMessageManagerMock, forType: InAppMessageManager.self)
    }

    override func setUp() {
        setupMocks()

        // do not call super.setUp() because we want to initialize the module manually in test functions so we can test module being initialized.
    }

    private func setupMocks() {
        // Set up default return values for InAppMessageManagerMock

        inAppMessageManagerMock.dispatchReturnValue = Task {}
        inAppMessageManagerMock.subscribeReturnValue = Task {}

        // Mock the dispatch method to fulfill the initialization expectation
        inAppMessageManagerMock.dispatchClosure = { action, completion in
            if case .initialize = action {
                completion?()
            }
            return Task {}
        }
    }

    // Function to call when test function is ready to initialize the SDK module.
    //
    // There are async tasks that can be performed after the module is initialized.
    // Each parameter of this function represents 1 async task that could be performed. Have each test function specify what async tasks it expects to have happen.
    // Make sure to have the test function eventually wait for the returned expectations to be fulfilled.
    private func initializeModule(
        expectProfileToIdentify: Bool = false,
        expectSdkReset: Bool = false,
        expectScreenViewEvent: Bool = false
    ) -> [XCTestExpectation] {
        super.setUp(modifyModuleConfig: nil)

        var combinedExpectations: [XCTestExpectation] = []

        // Set default values on all expectations created in this function.
        let createDefaultExpectation: (String, Bool) -> XCTestExpectation = { description, expectToHappen in
            let expectation = self.expectation(description: description)

            // Setup expectation to only assert that the event happened or did not.
            // The number of times the expectation is called is not checked as it has been unreliable.
            // Instead, have the test function check the number of times a mock was called.
            expectation.assertForOverFulfill = false
            expectation.isInverted = !expectToHappen

            return expectation
        }

        let profileIdentifiedExpectation = createDefaultExpectation("Profile identified event to be received", expectProfileToIdentify)
        gistProviderMock.setUserTokenClosure = { _ in
            profileIdentifiedExpectation.fulfill()
        }
        combinedExpectations.append(profileIdentifiedExpectation)

        let sdkResetExpectation = createDefaultExpectation("SDK reset event to be received", expectSdkReset)
        gistProviderMock.resetStateClosure = {
            sdkResetExpectation.fulfill()
        }
        combinedExpectations.append(sdkResetExpectation)

        let screenViewEventExpectation = createDefaultExpectation("Screen view event to be received", expectScreenViewEvent)
        gistProviderMock.setCurrentRouteClosure = { _ in
            screenViewEventExpectation.fulfill()
        }
        combinedExpectations.append(screenViewEventExpectation)

        return combinedExpectations
    }

    // MARK: initialize

    func test_initialize_expectInitializeGistSDK() async {
        await waitForExpectations(initializeModule())

        inAppMessageManagerMock.dispatchReturnValue = Task {}
        inAppMessageManagerMock.subscribeReturnValue = Task {}

        if let dispatchArgs = inAppMessageManagerMock.dispatchReceivedArguments?.action {
            if case .initialize(let siteId, let dataCenter, let environment) = dispatchArgs {
                XCTAssertEqual(siteId, messagingInAppConfigOptions.siteId)
                XCTAssertEqual(dataCenter, messagingInAppConfigOptions.region.rawValue)
                XCTAssertEqual(environment, GistEnvironment.production)
            } else {
                XCTFail("Expected dispatch action to be .initialize")
            }
        } else {
            XCTFail("dispatchReceivedArguments is nil")
        }
    }

    // MARK: initialize given an existing identifier

    func test_initialize_givenExistingIdentifier_expectGistSetProfileIdentifier() async throws {
        let givenProfileIdentifiedInSdk = String.random

        await postEventAndWait(event: ProfileIdentifiedEvent(identifier: givenProfileIdentifiedInSdk))

        await waitForExpectations(initializeModule(expectProfileToIdentify: true))

        XCTAssertTrue(gistProviderMock.setUserTokenCalled)
        XCTAssertEqual(gistProviderMock.setUserTokenReceivedArguments, givenProfileIdentifiedInSdk)
    }

    // MARK: profile hooks

    func test_givenProfileIdentified_expectSetupWithInApp() async {
        let expectAsyncEventBusEvents = initializeModule(expectProfileToIdentify: true)

        let given = String.random

        await postEventAndWait(event: ProfileIdentifiedEvent(identifier: given))

        await waitForExpectations(expectAsyncEventBusEvents)

        XCTAssertEqual(gistProviderMock.setUserTokenCallsCount, 1)
        XCTAssertEqual(gistProviderMock.setUserTokenReceivedArguments, given)
    }

    func test_givenProfileNoLongerIdentified_expectRemoveFromInApp() async throws {
        let expectAsyncEventBusEvents = initializeModule(expectProfileToIdentify: true, expectSdkReset: true)

        await postEventAndWait(event: ProfileIdentifiedEvent(identifier: String.random))
        await postEventAndWait(event: ResetEvent())

        await waitForExpectations(expectAsyncEventBusEvents)

        XCTAssertEqual(gistProviderMock.resetStateCallsCount, 1)
    }

    // MARK: screen view hooks

    func test_givenScreenViewed_expectSetRouteOnInApp() async throws {
        let expectAsyncEventBusEvents = initializeModule(expectScreenViewEvent: true)

        let given = String.random

        await postEventAndWait(event: ScreenViewedEvent(name: given))

        await waitForExpectations(expectAsyncEventBusEvents)

        XCTAssertEqual(gistProviderMock.setCurrentRouteCallsCount, 1)
        XCTAssertEqual(gistProviderMock.setCurrentRouteReceivedArguments, given)
    }

    // MARK: event listeners

    func test_eventListeners_expectNoCallListenerWithData() async {
        await waitForExpectations(initializeModule())

        messagingInApp.setEventListener(eventListenerMock)

        XCTAssertFalse(eventListenerMock.messageShownCalled)

        // message dismissed
        XCTAssertFalse(eventListenerMock.messageDismissedCalled)

        // error with message
        XCTAssertFalse(eventListenerMock.errorWithMessageCalled)

        // message action taken
        XCTAssertFalse(eventListenerMock.messageActionTakenCalled)
    }

    // MARK: dismiss message

    func test_dismissMessage_givenNoInAppMessage_expectNoError() async {
        await waitForExpectations(initializeModule())

        // Dismiss in-app message
        XCTAssertFalse(gistProviderMock.dismissMessageCalled)
        messagingInApp.dismissMessage()
        XCTAssertEqual(gistProviderMock.dismissMessageCallsCount, 1)
    }
}

extension MessagingInAppImplementationTest {
    func postEventAndWait<E: EventRepresentable>(event: E) async {
        await eventBusHandler.postEventAndWait(event)
    }
}
