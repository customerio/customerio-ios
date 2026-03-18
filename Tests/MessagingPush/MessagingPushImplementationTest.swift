@testable import CioInternalCommon
@testable import CioMessagingPush
import Foundation
import SharedTests
import UserNotifications
import XCTest

class MessagingPushImplementationTest: UnitTest {
    private var pushLoggerMock: PushNotificationLoggerMock!
    private var richPushDeliveryTrackerMock: RichPushDeliveryTrackerMock!
    private var httpClientMock: HttpClientMock!
    private var implementation: MessagingPushImplementation!

    override func setUp() {
        super.setUp()

        pushLoggerMock = PushNotificationLoggerMock()
        richPushDeliveryTrackerMock = RichPushDeliveryTrackerMock()
        httpClientMock = HttpClientMock()

        mockCollection.add(mocks: [pushLoggerMock, richPushDeliveryTrackerMock, httpClientMock])

        diGraphShared.override(value: pushLoggerMock, forType: PushNotificationLogger.self)
        diGraphShared.override(value: richPushDeliveryTrackerMock, forType: RichPushDeliveryTracker.self)
        diGraphShared.override(value: httpClientMock, forType: HttpClient.self)

        implementation = MessagingPushImplementation(
            diGraph: diGraphShared,
            moduleConfig: MessagingPushConfigBuilder().build()
        )
    }

    // MARK: - NSE didReceive / coordinator

    func test_didReceive_whenNonCIOPush_returnsFalse() {
        let request = makeNonCIORequest()

        let result = implementation.didReceive(request, withContentHandler: { _ in })

        XCTAssertFalse(result)
    }

    func test_didReceive_whenCIOPush_returnsTrue() {
        richPushDeliveryTrackerMock.trackMetricClosure = { _, _, _, _, completion in
            completion(.success(()))
        }
        let request = makeCIORequest()

        let result = implementation.didReceive(request, withContentHandler: { _ in })

        XCTAssertTrue(result)
    }

    func test_didReceive_whenCIOPush_expectCoordinatorHandleRunsAndContentHandlerCalled() {
        let contentHandlerCalled = expectation(description: "contentHandler called")
        richPushDeliveryTrackerMock.trackMetricClosure = { _, _, _, _, completion in
            completion(.success(()))
        }
        let request = makeCIORequest(title: "CIO Title")

        _ = implementation.didReceive(request) { content in
            XCTAssertEqual(content.title, "CIO Title")
            contentHandlerCalled.fulfill()
        }

        wait(for: [contentHandlerCalled], timeout: 1.0)
    }

    func test_didReceive_whenCalledTwiceBeforeCompletion_expectBothStartDeliveryTracking() {
        // Never complete delivery so each coordinator stays in flight; both should still invoke delivery tracking.
        let bothDeliveryMetricsStarted = expectation(description: "trackMetric invoked for both notifications")
        bothDeliveryMetricsStarted.expectedFulfillmentCount = 2
        richPushDeliveryTrackerMock.trackMetricClosure = { _, _, _, _, _ in
            bothDeliveryMetricsStarted.fulfill()
        }
        let request1 = makeCIORequest(deliveryID: "d1")
        let request2 = makeCIORequest(deliveryID: "d2")

        _ = implementation.didReceive(request1, withContentHandler: { _ in })
        _ = implementation.didReceive(request2, withContentHandler: { _ in })

        wait(for: [bothDeliveryMetricsStarted], timeout: 1.0)
        XCTAssertEqual(richPushDeliveryTrackerMock.trackMetricCallsCount, 2)
    }

    func test_serviceExtensionTimeWillExpire_whenCoordinatorInFlight_expectContentHandlerCalled() {
        let contentDelivered = expectation(description: "contentHandler after expire")
        // `didReceive` returns before the `Task` runs `handle`. Expire only after delivery work has
        // started so coordinator state (contentHandler) exists; otherwise `cancel()` is a no-op.
        let coordinatorHandlingStarted = expectation(description: "handle started delivery metric")
        richPushDeliveryTrackerMock.trackMetricClosure = { _, _, _, _, _ in
            coordinatorHandlingStarted.fulfill()
            // Intentionally never invoke completion — delivery stays in flight until cancel().
        }
        let request = makeCIORequest()
        _ = implementation.didReceive(request, withContentHandler: { _ in
            contentDelivered.fulfill()
        })

        wait(for: [coordinatorHandlingStarted], timeout: 1.0)
        implementation.serviceExtensionTimeWillExpire()

        wait(for: [contentDelivered], timeout: 1.0)
    }

    // MARK: - Helpers

    private func makeCIORequest(
        title: String = "Original",
        deliveryID: String = "id",
        deviceToken: String = "token"
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Body"
        content.userInfo = [
            "CIO-Delivery-ID": deliveryID,
            "CIO-Delivery-Token": deviceToken
        ]
        return UNNotificationRequest(identifier: "id", content: content, trigger: nil)
    }

    private func makeNonCIORequest() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Other"
        content.body = "Other body"
        content.userInfo = [:]
        return UNNotificationRequest(identifier: "id", content: content, trigger: nil)
    }
}
