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
    private var pendingPushDeliveryStoreMock: PendingPushDeliveryStoreMock!
    private var implementation: MessagingPushImplementation!

    override func setUp() {
        super.setUp()

        pushLoggerMock = PushNotificationLoggerMock()
        richPushDeliveryTrackerMock = RichPushDeliveryTrackerMock()
        httpClientMock = HttpClientMock()
        pendingPushDeliveryStoreMock = PendingPushDeliveryStoreMock()
        pendingPushDeliveryStoreMock.appendReturnValue = true
        pendingPushDeliveryStoreMock.removeReturnValue = true

        mockCollection.add(mocks: [pushLoggerMock, richPushDeliveryTrackerMock, httpClientMock, pendingPushDeliveryStoreMock])

        diGraphShared.override(value: pushLoggerMock, forType: PushNotificationLogger.self)
        diGraphShared.override(value: richPushDeliveryTrackerMock, forType: RichPushDeliveryTracker.self)
        diGraphShared.override(value: httpClientMock, forType: HttpClient.self)
        diGraphShared.override(value: pendingPushDeliveryStoreMock, forType: PendingPushDeliveryStore.self)

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

    func test_serviceExtensionTimeWillExpire_whenCoordinatorInFlight_expectContentHandlerCalled() {
        let contentDelivered = expectation(description: "contentHandler after expire")
        // Never complete delivery metric — work stays in flight until `cancel()`.
        richPushDeliveryTrackerMock.trackMetricClosure = { _, _, _, _, _ in }
        let request = makeCIORequest()
        _ = implementation.didReceive(request, withContentHandler: { _ in
            contentDelivered.fulfill()
        })

        // `prepareNotification` runs synchronously in `didReceive`, so expiry can run before `handle` starts.
        implementation.serviceExtensionTimeWillExpire()

        wait(for: [contentDelivered], timeout: 1.0)
    }

    // MARK: - Helpers

    private func makeCIORequest(
        title: String = "Original",
        deliveryID: String = "id",
        deviceToken: String = "token",
        requestIdentifier: String = "id"
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Body"
        content.userInfo = [
            "CIO-Delivery-ID": deliveryID,
            "CIO-Delivery-Token": deviceToken
        ]
        return UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: nil)
    }

    private func makeNonCIORequest() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Other"
        content.body = "Other body"
        content.userInfo = [:]
        return UNNotificationRequest(identifier: "id", content: content, trigger: nil)
    }
}
