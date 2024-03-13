@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class PushEventHandlerProxyTest: UnitTest {
    private var proxy: PushEventHandlerProxyImpl!

    override func setUp() {
        super.setUp()

        proxy = PushEventHandlerProxyImpl(logger: log)
    }

    // MARK: thread safety

    func test_onPushAction_ensureThreadSafetyCallingDelegates() {
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
        proxy.addPushEventHandler(delegate1)
        proxy.addPushEventHandler(delegate2)

        proxy.onPushAction(PushNotificationActionStub(push: PushNotificationStub.getPushSentFromCIO(), didClickOnPush: true)) {
            expectCompleteCallingAllDelegates.fulfill()
        }

        wait(for: [
            expectDelegatesReceiveEvent,
            expectCompleteCallingAllDelegates
        ], enforceOrder: true)
    }

    func test_shouldDisplayPushAppInForeground_ensureThreadSafetyCallingDelegates() {
        let givenPush = PushNotificationStub.getPushSentFromCIO()

        let delegate1 = PushEventHandlerMock()
        class PushEventHandlerMock2: PushEventHandlerMock {}
        let delegate2 = PushEventHandlerMock2()

        let expectDelegatesReceiveEvent = expectation(description: "delegate1 received event")
        expectDelegatesReceiveEvent.expectedFulfillmentCount = 2 // 1 for each delegate. We do not care what order the delegates get called as long as all get called.
        let expectCompleteCallingAllDelegates = expectation(description: "complete calling all delegates")

        // When each delegate gets called, have them call the completion handler on different threads to test the proxy is thread safe.
        delegate1.shouldDisplayPushAppInForegroundClosure = { _, completion in
            expectDelegatesReceiveEvent.fulfill()

            self.runOnMain {
                completion(false)
            }
        }
        delegate2.shouldDisplayPushAppInForegroundClosure = { _, completion in
            expectDelegatesReceiveEvent.fulfill()

            self.runOnBackground {
                completion(true)
            }
        }
        proxy.addPushEventHandler(delegate1)
        proxy.addPushEventHandler(delegate2)

        proxy.shouldDisplayPushAppInForeground(givenPush, completionHandler: { actualShouldDisplayPush in
            // Assert that the 1 delegate that returns `true` is the return result.
            XCTAssertTrue(actualShouldDisplayPush)

            expectCompleteCallingAllDelegates.fulfill()
        })

        wait(for: [
            expectDelegatesReceiveEvent,
            expectCompleteCallingAllDelegates
        ], enforceOrder: true)
    }

    // MARK: shouldDisplayPushAppInForeground

    func test_shouldDisplayPushAppInForeground_givenNoHandlers_expectTrue() {
        let push = PushNotificationStub.getPushSentFromCIO()
        var actual: Bool!

        proxy.shouldDisplayPushAppInForeground(push) { value in
            actual = value
        }

        XCTAssertTrue(actual)
    }

    func test_shouldDisplayPushAppInForeground_givenOneHandler_expectReturnResultFromHandler() async throws {
        let push = PushNotificationStub.getPushSentFromCIO()
        var actual: Bool!

        let handler = PushEventHandlerMock()
        handler.shouldDisplayPushAppInForegroundClosure = { _, onComplete in
            onComplete(true)
        }
        proxy.addPushEventHandler(handler)

        await waitForAsyncOperation { asyncComplete in
            self.proxy.shouldDisplayPushAppInForeground(push) { value in
                actual = value
                asyncComplete()
            }
        }

        XCTAssertTrue(actual)
    }

    // The SDK's logic to combine the return results is: return `false`, unless at least 1 push handler returns `true`.
    // To test that, we will perform multiple checks in the test function and watch the results change after each check.
    func test_shouldDisplayPushAppInForeground_givenMultipleHandlers_expectCombineReturnResults() async throws {
        let push = PushNotificationStub.getPushSentFromCIO()
        var actual: Bool!

        // First, test that `false` is the default return result.

        let handler1 = PushEventHandlerMock()
        handler1.shouldDisplayPushAppInForegroundClosure = { _, onComplete in
            onComplete(false)
        }
        proxy.addPushEventHandler(handler1)

        await waitForAsyncOperation { asyncComplete in
            self.proxy.shouldDisplayPushAppInForeground(push) { value in
                actual = value
                asyncComplete()
            }
        }

        XCTAssertFalse(actual)

        // Next, add another push handler that's return result is `true`.
        // We expect return result to now be `true`, since 1 handler returned `true`.
        class PushEventHandlerMock2: PushEventHandlerMock {}
        let handler2 = PushEventHandlerMock2()
        handler2.shouldDisplayPushAppInForegroundClosure = { _, onComplete in
            onComplete(true)
        }
        proxy.addPushEventHandler(handler2)

        await waitForAsyncOperation { asyncComplete in
            self.proxy.shouldDisplayPushAppInForeground(push) { value in
                actual = value
                asyncComplete()
            }
        }
        XCTAssertTrue(actual)

        // Finally, check that once 1 handler returns `true`, the return result is always `true`.
        class PushEventHandlerMock3: PushEventHandlerMock {}
        let handler3 = PushEventHandlerMock3()
        handler3.shouldDisplayPushAppInForegroundClosure = { _, onComplete in
            onComplete(false)
        }
        proxy.addPushEventHandler(handler3)

        await waitForAsyncOperation { asyncComplete in
            self.proxy.shouldDisplayPushAppInForeground(push) { value in
                actual = value
                asyncComplete()
            }
        }
        XCTAssertTrue(actual)
    }
}
