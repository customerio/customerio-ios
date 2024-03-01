@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class PushEventHandlerTest: UnitTest {
    private var pushEventHandler: PushEventHandler!

    private var pushEventHandlerProxy: PushEventHandlerProxy {
        diGraphShared.pushEventHandlerProxy
    }

    private var pushClickHandler = PushClickHandlerMock()

    override func setUp() {
        super.setUp()

        pushEventHandler = IOSPushEventListener(
            jsonAdapter: diGraphShared.jsonAdapter,
            pushEventHandlerProxy: pushEventHandlerProxy,
            moduleConfig: diGraphShared.messagingPushConfigOptions,
            pushClickHandler: pushClickHandler,
            pushHistory: diGraphShared.pushHistory,
            logger: diGraphShared.logger
        )
    }

    // MARK: onPushAction

    /*
     The CIO SDK push event handler forwards push notifications to other push event handlers in the host app.

     But, what if the CIO SDK event handler forwards a push event back to the CIO SDK event handler? This could cause an infinite loop.

     This test simulates that scenario to make sure that an inifinite loop would not happen.
     */
    func test_onPushAction_expectNoInfiniteLoopIfSdkForwardsPushEventBacktoSdkAgain() {
        // The push event handler proxy is what forwards push events to other push event handlers in the app.
        // To test if an infinite loop would happen, add ourself as a push event handler to get events forwarded to.
        pushEventHandlerProxy.addPushEventHandler(pushEventHandler)

        // Make sure push is not from CIO otherwise event does not get forwarded.
        let givenPush = PushNotificationStub.getPushNotSentFromCIO()

        // Send the CIO SDK push event handler an event. If an infinite loop occurs, this test will timeout or crash.
        pushEventHandler.onPushAction(PushNotificationActionStub(push: givenPush, didClickOnPush: true)) {}
    }
}
