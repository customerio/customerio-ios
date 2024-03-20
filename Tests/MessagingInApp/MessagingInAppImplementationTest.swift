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

    private let inAppProviderMock = InAppProviderMock()
    private let eventListenerMock = InAppEventListenerMock()
    private let eventBusHandlerMock = EventBusHandlerMock()

    override func setUpDependencies() {
        super.setUpDependencies()

        diGraphShared.override(value: inAppProviderMock, forType: InAppProvider.self)
    }

    override func setUp() {
        // do not call super.setUp() because we want to initialize the module manually in test functions so we can test module being initialized.
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
        inAppProviderMock.setProfileIdentifierClosure = { _ in
            profileIdentifiedExpectation.fulfill()
        }
        combinedExpectations.append(profileIdentifiedExpectation)

        let sdkResetExpectation = createDefaultExpectation("SDK reset event to be received", expectSdkReset)
        inAppProviderMock.clearIdentifyClosure = {
            sdkResetExpectation.fulfill()
        }
        combinedExpectations.append(sdkResetExpectation)

        let screenViewEventExpectation = createDefaultExpectation("Screen view event to be received", expectScreenViewEvent)
        inAppProviderMock.setRouteClosure = { _ in
            screenViewEventExpectation.fulfill()
        }
        combinedExpectations.append(screenViewEventExpectation)

        return combinedExpectations
    }

    // MARK: initialize

    func test_initialize_expectInitializeGistSDK() async {
        await waitForExpectations(initializeModule())

        XCTAssertTrue(inAppProviderMock.initializeCalled)
        XCTAssertFalse(inAppProviderMock.setProfileIdentifierCalled)
    }

    // MARK: initialize given an existing identifier

    func test_initialize_givenExistingIdentifier_expectGistSetProfileIdentifier() async throws {
        let givenProfileIdentifiedInSdk = String.random

        await postEventAndWait(event: ProfileIdentifiedEvent(identifier: givenProfileIdentifiedInSdk))

        await waitForExpectations(initializeModule(expectProfileToIdentify: true))

        XCTAssertTrue(inAppProviderMock.setProfileIdentifierCalled)
        XCTAssertEqual(inAppProviderMock.setProfileIdentifierReceivedArguments, givenProfileIdentifiedInSdk)
    }

    // MARK: profile hooks

    func test_givenProfileIdentified_expectSetupWithInApp() async {
        let expectAsyncEventBusEvents = initializeModule(expectProfileToIdentify: true)

        let given = String.random

        await postEventAndWait(event: ProfileIdentifiedEvent(identifier: given))

        await waitForExpectations(expectAsyncEventBusEvents)

        XCTAssertEqual(inAppProviderMock.setProfileIdentifierCallsCount, 1)
        XCTAssertEqual(inAppProviderMock.setProfileIdentifierReceivedArguments, given)
    }

    func test_givenProfileNoLongerIdentified_expectRemoveFromInApp() async throws {
        let expectAsyncEventBusEvents = initializeModule(expectProfileToIdentify: true, expectSdkReset: true)

        await postEventAndWait(event: ProfileIdentifiedEvent(identifier: String.random))
        await postEventAndWait(event: ResetEvent())

        await waitForExpectations(expectAsyncEventBusEvents)

        XCTAssertEqual(inAppProviderMock.clearIdentifyCallsCount, 1)
    }

    // MARK: screen view hooks

    func test_givenScreenViewed_expectSetRouteOnInApp() async throws {
        let expectAsyncEventBusEvents = initializeModule(expectScreenViewEvent: true)

        let given = String.random

        await postEventAndWait(event: ScreenViewedEvent(name: given))

        await waitForExpectations(expectAsyncEventBusEvents)

        XCTAssertEqual(inAppProviderMock.setRouteCallsCount, 1)
        XCTAssertEqual(inAppProviderMock.setRouteReceivedArguments, given)
    }

    // MARK: event listeners

    func test_eventListeners_expectCallListenerWithData() async {
        await waitForExpectations(initializeModule())

        let givenGistMessage = Message.random
        let expectedInAppMessage = InAppMessage(gistMessage: givenGistMessage)

        messagingInApp.setEventListener(eventListenerMock)

        XCTAssertFalse(eventListenerMock.messageShownCalled)
        messagingInApp.messageShown(message: givenGistMessage)
        XCTAssertEqual(eventListenerMock.messageShownCallsCount, 1)
        XCTAssertEqual(eventListenerMock.messageShownReceivedArguments, expectedInAppMessage)

        // message dismissed
        XCTAssertFalse(eventListenerMock.messageDismissedCalled)
        messagingInApp.messageDismissed(message: givenGistMessage)
        XCTAssertEqual(eventListenerMock.messageDismissedCallsCount, 1)
        XCTAssertEqual(eventListenerMock.messageDismissedReceivedArguments, expectedInAppMessage)

        // error with message
        XCTAssertFalse(eventListenerMock.errorWithMessageCalled)
        messagingInApp.messageError(message: givenGistMessage)
        XCTAssertEqual(eventListenerMock.errorWithMessageCallsCount, 1)
        XCTAssertEqual(eventListenerMock.errorWithMessageReceivedArguments, expectedInAppMessage)

        // message action taken
        XCTAssertFalse(eventListenerMock.messageActionTakenCalled)
        let givenCurrentRoute = String.random
        let givenAction = String.random
        let givenName = String.random
        messagingInApp.action(
            message: givenGistMessage,
            currentRoute: givenCurrentRoute,
            action: givenAction,
            name: givenName
        )
        XCTAssertEqual(eventListenerMock.messageActionTakenCallsCount, 1)
        XCTAssertEqual(eventListenerMock.messageActionTakenReceivedArguments?.message, expectedInAppMessage)
        XCTAssertEqual(eventListenerMock.messageActionTakenReceivedArguments?.actionValue, givenAction)
        XCTAssertEqual(eventListenerMock.messageActionTakenReceivedArguments?.actionName, givenName)
    }

    func test_eventListeners_expectCallListenerForEachEvent() async {
        await waitForExpectations(initializeModule())

        let givenGistMessage = Message.random

        messagingInApp.setEventListener(eventListenerMock)

        XCTAssertEqual(eventListenerMock.messageShownCallsCount, 0)
        messagingInApp.messageShown(message: givenGistMessage)
        XCTAssertEqual(eventListenerMock.messageShownCallsCount, 1)
        messagingInApp.messageShown(message: givenGistMessage)
        XCTAssertEqual(eventListenerMock.messageShownCallsCount, 2)

        // message dismissed
        XCTAssertEqual(eventListenerMock.messageDismissedCallsCount, 0)
        messagingInApp.messageDismissed(message: givenGistMessage)
        XCTAssertEqual(eventListenerMock.messageDismissedCallsCount, 1)
        messagingInApp.messageDismissed(message: givenGistMessage)
        XCTAssertEqual(eventListenerMock.messageDismissedCallsCount, 2)

        // error with message
        XCTAssertEqual(eventListenerMock.errorWithMessageCallsCount, 0)
        messagingInApp.messageError(message: givenGistMessage)
        XCTAssertEqual(eventListenerMock.errorWithMessageCallsCount, 1)
        messagingInApp.messageError(message: givenGistMessage)
        XCTAssertEqual(eventListenerMock.errorWithMessageCallsCount, 2)

        // message action taken
        XCTAssertEqual(eventListenerMock.messageActionTakenCallsCount, 0)
        messagingInApp.action(message: givenGistMessage, currentRoute: .random, action: .random, name: .random)
        XCTAssertEqual(eventListenerMock.messageActionTakenCallsCount, 1)
        messagingInApp.action(message: givenGistMessage, currentRoute: .random, action: .random, name: .random)
        XCTAssertEqual(eventListenerMock.messageActionTakenCallsCount, 2)
    }

    func test_eventListeners_givenCloseAction_expectListenerEvent() async {
        // override event bus handler to mock it so we can capture events
        diGraphShared.override(value: eventBusHandlerMock, forType: EventBusHandler.self)

        await waitForExpectations(initializeModule())

        let givenGistMessage = Message.random
        let expectedInAppMessage = InAppMessage(gistMessage: givenGistMessage)
        let givenCurrentRoute = String.random
        let givenAction = "gist://close"
        let givenName = String.random

        messagingInApp.setEventListener(eventListenerMock)

        XCTAssertEqual(eventListenerMock.messageActionTakenCallsCount, 0)

        messagingInApp.action(
            message: givenGistMessage,
            currentRoute: givenCurrentRoute,
            action: givenAction,
            name: givenName
        )

        XCTAssertEqual(eventListenerMock.messageActionTakenCallsCount, 1)
        XCTAssertEqual(eventListenerMock.messageActionTakenReceivedArguments?.message, expectedInAppMessage)
        XCTAssertEqual(eventListenerMock.messageActionTakenReceivedArguments?.actionValue, givenAction)
        XCTAssertEqual(eventListenerMock.messageActionTakenReceivedArguments?.actionName, givenName)

        // make sure there is no click tracking for "close" action
        XCTAssertEqual(eventBusHandlerMock.postEventCallsCount, 0)
    }

    func test_inAppTracking_givenCustomAction_expectBQTrackInAppClicked() async {
        // override event bus handler to mock it so we can capture events
        diGraphShared.override(value: eventBusHandlerMock, forType: EventBusHandler.self)

        await waitForExpectations(initializeModule())

        let givenGistMessage = Message.random
        let expectedInAppMessage = InAppMessage(gistMessage: givenGistMessage)
        let givenCurrentRoute = String.random
        let givenAction = String.random
        let givenName = String.random
        let givenMetaData = ["action_name": givenName, "action_value": givenAction]

        messagingInApp.action(
            message: givenGistMessage,
            currentRoute: givenCurrentRoute,
            action: givenAction,
            name: givenName
        )

        XCTAssertEqual(eventBusHandlerMock.postEventCallsCount, 1)
        guard let postEventArgument = eventBusHandlerMock.postEventArguments as? TrackInAppMetricEvent else {
            XCTFail("captured arguments must not be nil")
            return
        }

        XCTAssertEqual(postEventArgument.deliveryID, expectedInAppMessage.deliveryId)
        XCTAssertEqual(postEventArgument.event, InAppMetric.clicked.rawValue)
        XCTAssertEqual(postEventArgument.params, givenMetaData)
    }

    func test_dismissMessage_givenNoInAppMessage_expectNoError() async {
        await waitForExpectations(initializeModule())

        // Dismiss in-app message
        XCTAssertFalse(inAppProviderMock.dismissMessageCalled)
        messagingInApp.dismissMessage()
        XCTAssertEqual(inAppProviderMock.dismissMessageCallsCount, 1)
    }

    func test_dismissMessage_givenInAppMessage_expectNoError() async {
        await waitForExpectations(initializeModule())

        let givenGistMessage = Message.random
        _ = InAppMessage(gistMessage: givenGistMessage)

        // Dismiss in-app message when an in-app message is shown on screen
        XCTAssertFalse(inAppProviderMock.dismissMessageCalled)
        messagingInApp.dismissMessage()
        XCTAssertEqual(inAppProviderMock.dismissMessageCallsCount, 1)
    }
}

extension MessagingInAppImplementationTest {
    func postEventAndWait<E: EventRepresentable>(event: E) async {
        await eventBusHandler.postEventAndWait(event)
    }
}
