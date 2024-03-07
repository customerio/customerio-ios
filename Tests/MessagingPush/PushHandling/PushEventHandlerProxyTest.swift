@testable import CioMessagingPush
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class PushEventHandlerProxyTest: UnitTest {
    var pushEventHandlerProxy: PushEventHandlerProxy!

    private let deepLinkUtilMock = DeepLinkUtilMock()
    private let customerIOMock = CustomerIOInstanceMock()

    override func setUp() {
        super.setUp()

        pushEventHandlerProxy = PushEventHandlerProxyImpl()
    }

    // MARK: thread safety

    func test_onPushAction_ensureThreadSafetyCallingDelegates() {
        runTest(numberOfTimes: 100) { // Ensure no race conditions by running test many times.
            let delegate1 = PushEventHandlerMock()
            class PushEventHandlerMock2: PushEventHandlerMock {}
            let delegate2 = PushEventHandlerMock2()

            let expectDelegatesReceiveEvent = expectation(description: "delegate1 received event")
            expectDelegatesReceiveEvent.expectedFulfillmentCount = 2 // 1 for each delegate. We do not care what order the delegates get called as long as all get called.
            let expectCompleteCallingAllDelegates = expectation(description: "complete calling all delegates")

            // When each delegate gets called, have them call the completion handler on different threads to test the proxy is thread safe.
            delegate1.onPushActionClosure = { _, completion in
                expectDelegatesReceiveEvent.fulfill()

                self.runOnMain {
                    completion()
                }
            }
            delegate2.onPushActionClosure = { _, completion in
                expectDelegatesReceiveEvent.fulfill()

                self.runOnBackground {
                    completion()
                }
            }
            pushEventHandlerProxy.addPushEventHandler(delegate1)
            pushEventHandlerProxy.addPushEventHandler(delegate2)

            pushEventHandlerProxy.onPushAction(PushNotificationActionStub(push: PushNotificationStub.getPushSentFromCIO(), didClickOnPush: true)) {
                expectCompleteCallingAllDelegates.fulfill()
            }

            wait(for: [
                expectDelegatesReceiveEvent,
                expectCompleteCallingAllDelegates
            ], enforceOrder: true)
        }
    }
}
