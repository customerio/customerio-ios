@testable import CioInternalCommon
@testable import CioMessagingInApp
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class MessagingInAppImplementationTest: UnitTest {
    private var messagingInApp: MessagingInAppImplementation!
    private let moduleConfigDefault = MessagingInAppConfigOptions.Factory.create(siteId: .random, region: .US)

    private let inAppProviderMock = InAppProviderMock()
    private let eventListenerMock = InAppEventListenerMock()
    private let profileStoreMock = ProfileStoreMock()
    private let backgroundQueueMock = QueueMock()

    override func setUp() {
        super.setUp()

        diGraphShared.override(value: inAppProviderMock, forType: InAppProvider.self)
        diGraphShared.override(value: profileStoreMock, forType: ProfileStore.self)
        diGraphShared.override(value: backgroundQueueMock, forType: Queue.self)

        messagingInApp = MessagingInAppImplementation(diGraph: diGraphShared, moduleConfig: moduleConfigDefault)
        messagingInApp.setEventListener(eventListenerMock)
    }

    // MARK: initialize

    func test_initialize_expectInitializeGistSDK() {
        _ = MessagingInAppImplementation(diGraph: diGraphShared, moduleConfig: moduleConfigDefault)

        XCTAssertTrue(inAppProviderMock.initializeCalled)
        XCTAssertFalse(inAppProviderMock.setProfileIdentifierCalled)
    }

    // MARK: initialize given an existing identifier

    func test_initialize_givenExistingIdentifier_expectGistSetProfileIdentifier() {
        let givenProfileIdentifiedInSdk = String.random

        profileStoreMock.identifier = givenProfileIdentifiedInSdk

        _ = MessagingInAppImplementation(diGraph: diGraphShared, moduleConfig: moduleConfigDefault)
//        FIXME: [CDP] Fetch from Journey and update the test case
//        XCTAssertTrue(inAppProviderMock.setProfileIdentifierCalled)
//        XCTAssertEqual(inAppProviderMock.setProfileIdentifierReceivedArguments, givenProfileIdentifiedInSdk)
    }

    // MARK: profile hooks

    func test_givenProfileIdentified_expectSetupWithInApp() {
        let given = String.random

        messagingInApp.profileIdentified(identifier: given)

        XCTAssertEqual(inAppProviderMock.setProfileIdentifierCallsCount, 1)
        XCTAssertEqual(inAppProviderMock.setProfileIdentifierReceivedArguments, given)
    }

    func test_givenProfileNoLongerIdentified_expectRemoveFromInApp() {
        messagingInApp.beforeProfileStoppedBeingIdentified(oldIdentifier: String.random)

        XCTAssertEqual(inAppProviderMock.clearIdentifyCallsCount, 1)
    }

    // MARK: screen view hooks

    func test_givenScreenViewed_expectSetRouteOnInApp() {
        let given = String.random

        messagingInApp.screenViewed(name: given)
        let expectation = XCTestExpectation(description: "Wait for 1 second")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(inAppProviderMock.setRouteCallsCount, 1)
        XCTAssertEqual(inAppProviderMock.setRouteReceivedArguments, given)
    }

    // MARK: event listeners

    func test_eventListeners_expectCallListenerWithData() {
        let givenGistMessage = Message.random
        let expectedInAppMessage = InAppMessage(gistMessage: givenGistMessage)

        // FIXME: [CDP] Test if the task is being forwarded to EventBus (use Mocks to test)
        /* backgroundQueueMock.addTrackInAppDeliveryTaskReturnValue = (
             success: true,
             queueStatus: QueueStatus.successAddingSingleTask
         ) */
        // Message opened
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

    func test_eventListeners_expectCallListenerForEachEvent() {
        let givenGistMessage = Message.random

        // FIXME: [CDP] Test if the task is being forwarded to EventBus (use Mocks to test)
        /* backgroundQueueMock.addTrackInAppDeliveryTaskReturnValue = (
             success: true,
             queueStatus: QueueStatus.successAddingSingleTask
         ) */
        // Message opened
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

    func test_eventListeners_givenCloseAction_expectListenerEvent() {
        let givenGistMessage = Message.random
        let expectedInAppMessage = InAppMessage(gistMessage: givenGistMessage)
        let givenCurrentRoute = String.random
        let givenAction = "gist://close"
        let givenName = String.random
        // FIXME: [CDP] Test if the task is being forwarded to EventBus (use Mocks to test)
        /* backgroundQueueMock.addTrackInAppDeliveryTaskReturnValue = (
             success: true,
             queueStatus: QueueStatus.successAddingSingleTask
         ) */
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

        // FIXME: [CDP] Test if the task is being forwarded to EventBus (use Mocks to test)
        // make sure there is no click tracking for "close" action
        // XCTAssertEqual(backgroundQueueMock.addTrackInAppDeliveryTaskCallsCount, 0)
    }

    func test_inAppTracking_givenCustomAction_expectBQTrackInAppClicked() {
        // FIXME: [CDP] Test if the task is being forwarded to EventBus (use Mocks to test)
        /*
         let givenGistMessage = Message.random
         let expectedInAppMessage = InAppMessage(gistMessage: givenGistMessage)
         let givenCurrentRoute = String.random
         let givenAction = String.random
         let givenName = String.random
         let givenMetaData = ["action_name": givenName, "action_value": givenAction]

         backgroundQueueMock.addTrackInAppDeliveryTaskReturnValue = (
             success: true,
             queueStatus: QueueStatus.successAddingSingleTask
         )

         messagingInApp.action(
             message: givenGistMessage,
             currentRoute: givenCurrentRoute,
             action: givenAction,
             name: givenName
         )

         XCTAssertEqual(backgroundQueueMock.addTrackInAppDeliveryTaskReceivedArguments?.deliveryId, expectedInAppMessage.deliveryId)
         XCTAssertEqual(backgroundQueueMock.addTrackInAppDeliveryTaskReceivedArguments?.event, .clicked)
         XCTAssertEqual(backgroundQueueMock.addTrackInAppDeliveryTaskReceivedArguments?.metaData, givenMetaData)
          */
    }

    func test_dismissMessage_givenNoInAppMessage_expectNoError() {
        // Dismiss in-app message
        XCTAssertFalse(inAppProviderMock.dismissMessageCalled)
        messagingInApp.dismissMessage()
        XCTAssertEqual(inAppProviderMock.dismissMessageCallsCount, 1)
    }

    func test_dismissMessage_givenInAppMessage_expectNoError() {
        let givenGistMessage = Message.random
        _ = InAppMessage(gistMessage: givenGistMessage)

        // Dismiss in-app message when an in-app message is shown on screen
        XCTAssertFalse(inAppProviderMock.dismissMessageCalled)
        messagingInApp.dismissMessage()
        XCTAssertEqual(inAppProviderMock.dismissMessageCallsCount, 1)
    }
}
