@testable import CioInternalCommon
@testable import CioMessagingPush
import Foundation
import SharedTests
import UserNotifications
import XCTest

@available(iOS 13.0, *)
class NSEPushCoordinatorTests: UnitTest {
    private var contentHandlerInvocations: [UNNotificationContent]!
    private var deliveryTrackingMock: RichPushDeliveryTrackingMock!
    private var richPushDeliveryTrackerMock: RichPushDeliveryTrackerMock!
    private var pushLoggerMock: PushNotificationLoggerMock!
    private var loggerMock: LoggerMock!
    private var richPushHandlerMock: RichPushRequestHandlingMock!
    private var httpClientMock: HttpClientMock!
    private var pendingPushDeliveryStoreMock: PendingPushDeliveryStoreMock!

    override func setUp() {
        super.setUp()
        contentHandlerInvocations = []
        deliveryTrackingMock = RichPushDeliveryTrackingMock()
        richPushDeliveryTrackerMock = RichPushDeliveryTrackerMock()
        pushLoggerMock = PushNotificationLoggerMock()
        loggerMock = LoggerMock()
        richPushHandlerMock = RichPushRequestHandlingMock()
        httpClientMock = HttpClientMock()
        pendingPushDeliveryStoreMock = PendingPushDeliveryStoreMock()
        pendingPushDeliveryStoreMock.appendReturnValue = true
        pendingPushDeliveryStoreMock.removeReturnValue = true
        pendingPushDeliveryStoreMock.underlyingAppGroupSuiteName = "group.test.app.cio"
        mockCollection.add(mocks: [
            richPushDeliveryTrackerMock,
            pushLoggerMock,
            pendingPushDeliveryStoreMock,
            loggerMock
        ])
    }

    /// Production-like adapter so delivery metric success/failure updates `PushNotificationLogger`.
    private func makeDeliveryTrackingAdapter() -> RichPushDeliveryTracking {
        RichPushNSEDeliveryTracking(tracker: richPushDeliveryTrackerMock, pushLogger: pushLoggerMock)
    }

    private func makeCoordinator(
        deliveryTracker: RichPushDeliveryTracking? = nil,
        pushLogger: PushNotificationLogger? = nil,
        logger: Logger? = nil,
        richPushHandler: RichPushRequestHandling? = nil,
        httpClient: HttpClient? = nil,
        pendingPushDeliveryStore: PendingPushDeliveryStore? = nil
    ) -> NSEPushCoordinator {
        NSEPushCoordinator(
            deliveryTracker: deliveryTracker ?? deliveryTrackingMock,
            pushLogger: pushLogger ?? pushLoggerMock,
            logger: logger ?? loggerMock,
            richPushHandler: richPushHandler ?? richPushHandlerMock,
            httpClient: httpClient ?? httpClientMock,
            pendingPushDeliveryStore: pendingPushDeliveryStore ?? pendingPushDeliveryStoreMock
        )
    }

    /// Request with CIO delivery info so coordinator does not early-return.
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

    private func contentHandlerForTests() -> (UNNotificationContent) -> Void {
        { [weak self] content in
            self?.contentHandlerInvocations.append(content)
        }
    }

    private func richContent(title: String) -> UNNotificationContent {
        UNNotificationWrapper(notificationRequest: makeCIORequest(title: title)).notificationContent
    }

    // MARK: - Non-CIO push

    func test_handle_whenNonCIOPush_expectContentHandlerCalledOnceWithRequestContent() async {
        let coordinator = makeCoordinator()
        let request = makeNonCIORequest()

        await coordinator.handle(
            request: request,
            withContentHandler: contentHandlerForTests(),
            autoTrackDelivery: true
        )

        XCTAssertEqual(contentHandlerInvocations.count, 1)
        XCTAssertEqual(contentHandlerInvocations.first?.title, "Other")
        XCTAssertEqual(deliveryTrackingMock.trackMetricCallsCount, 0)
        XCTAssertEqual(richPushHandlerMock.startCallsCount, 0)
        XCTAssertEqual(pendingPushDeliveryStoreMock.appendCallsCount, 0)
    }

    // MARK: - Pending delivery storage (app group)

    func test_handle_whenAutoTrackDeliveryFalse_expectNoPendingAppend() async {
        richPushHandlerMock.startClosure = { _, completion in
            completion(.success(self.richContent(title: "Original")))
        }

        let coordinator = makeCoordinator()
        await coordinator.handle(
            request: makeCIORequest(),
            withContentHandler: contentHandlerForTests(),
            autoTrackDelivery: false
        )

        XCTAssertEqual(pendingPushDeliveryStoreMock.appendCallsCount, 0)
        XCTAssertEqual(pendingPushDeliveryStoreMock.removeCallsCount, 0)
    }

    func test_handle_whenDeliverySucceeds_expectPendingRemovedWithAppendedId() async {
        var appendedId: UUID?
        pendingPushDeliveryStoreMock.appendClosure = { metric in
            appendedId = metric.id
            return true
        }

        deliveryTrackingMock.trackMetricClosure = { _, _, completion in
            completion(.success(()))
        }
        richPushHandlerMock.startClosure = { _, completion in
            completion(.success(self.richContent(title: "Original")))
        }

        let coordinator = makeCoordinator()
        await coordinator.handle(
            request: makeCIORequest(deliveryID: "d-rem", deviceToken: "tok-rem"),
            withContentHandler: contentHandlerForTests(),
            autoTrackDelivery: true
        )

        XCTAssertEqual(pendingPushDeliveryStoreMock.appendCallsCount, 1)
        XCTAssertEqual(pendingPushDeliveryStoreMock.appendReceivedInvocations.first?.deliveryId, "d-rem")
        XCTAssertEqual(pendingPushDeliveryStoreMock.appendReceivedInvocations.first?.deviceToken, "tok-rem")
        XCTAssertEqual(pendingPushDeliveryStoreMock.appendReceivedInvocations.first?.event, .delivered)
        XCTAssertEqual(pendingPushDeliveryStoreMock.removeCallsCount, 1)
        XCTAssertEqual(pendingPushDeliveryStoreMock.removeReceivedInvocations.first, appendedId)
    }

    func test_handle_whenDeliveryFails_expectPendingNotRemoved() async {
        pendingPushDeliveryStoreMock.appendClosure = { _ in true }

        deliveryTrackingMock.trackMetricClosure = { _, _, completion in
            completion(.failure(HttpRequestError.noRequestMade(nil)))
        }
        richPushHandlerMock.startClosure = { _, completion in
            completion(.success(self.richContent(title: "Original")))
        }

        let coordinator = makeCoordinator()
        await coordinator.handle(
            request: makeCIORequest(),
            withContentHandler: contentHandlerForTests(),
            autoTrackDelivery: true
        )

        XCTAssertEqual(pendingPushDeliveryStoreMock.appendCallsCount, 1)
        XCTAssertEqual(pendingPushDeliveryStoreMock.removeCallsCount, 0)
    }

    func test_handle_whenAppendFails_expectDebugLoggedAndDeliveryStillRuns() async {
        pendingPushDeliveryStoreMock.appendReturnValue = false

        deliveryTrackingMock.trackMetricClosure = { _, _, completion in
            completion(.success(()))
        }
        richPushHandlerMock.startClosure = { _, completion in
            completion(.success(self.richContent(title: "Original")))
        }

        let coordinator = makeCoordinator()
        await coordinator.handle(
            request: makeCIORequest(deliveryID: "d-err"),
            withContentHandler: contentHandlerForTests(),
            autoTrackDelivery: true
        )

        let appendFailDebugs = loggerMock.debugReceivedInvocations.filter {
            $0.message.contains("could not persist pending metric")
        }
        XCTAssertEqual(appendFailDebugs.count, 1)
        XCTAssertTrue(appendFailDebugs.first?.message.contains("d-err") ?? false)
        XCTAssertEqual(deliveryTrackingMock.trackMetricCallsCount, 1)
        XCTAssertEqual(pendingPushDeliveryStoreMock.removeCallsCount, 0)
    }

    // MARK: - CIO push, parallel run

    func test_handle_whenCIOPush_autoTrackDeliveryTrue_expectDeliveryAndRichPushRunInParallel() async {
        var deliveryResume: (() -> Void)?
        var richPushResume: ((Result<UNNotificationContent, Error>) -> Void)?
        var handleTask: Task<Void, Never>?

        await withCheckedContinuation { (bothStarted: CheckedContinuation<Void, Never>) in
            var startedCount = 0
            func signalBothPathsEntered() {
                startedCount += 1
                if startedCount == 2 {
                    bothStarted.resume()
                }
            }

            deliveryTrackingMock.trackMetricClosure = { _, _, completion in
                deliveryResume = { completion(.success(())) }
                signalBothPathsEntered()
            }
            richPushHandlerMock.startClosure = { _, completion in
                richPushResume = { result in completion(result) }
                signalBothPathsEntered()
            }

            let coordinator = makeCoordinator()
            let request = makeCIORequest()

            handleTask = Task {
                await coordinator.handle(
                    request: request,
                    withContentHandler: contentHandlerForTests(),
                    autoTrackDelivery: true
                )
            }
        }

        richPushResume?(.success(richContent(title: "Rich")))
        deliveryResume?()
        await handleTask!.value

        XCTAssertEqual(contentHandlerInvocations.count, 1)
        XCTAssertEqual(contentHandlerInvocations.first?.title, "Rich")
        XCTAssertEqual(deliveryTrackingMock.trackMetricCallsCount, 1)
        XCTAssertEqual(richPushHandlerMock.startCallsCount, 1)
        XCTAssertEqual(pendingPushDeliveryStoreMock.appendCallsCount, 1)
    }

    func test_handle_whenCIOPush_autoTrackDeliveryFalse_expectDeliveryNotRun() async {
        richPushHandlerMock.startClosure = { _, completion in
            completion(.success(self.richContent(title: "Original")))
        }

        let coordinator = makeCoordinator()
        let request = makeCIORequest()

        await coordinator.handle(
            request: request,
            withContentHandler: contentHandlerForTests(),
            autoTrackDelivery: false
        )

        XCTAssertEqual(deliveryTrackingMock.trackMetricCallsCount, 0)
        XCTAssertEqual(contentHandlerInvocations.count, 1)
        XCTAssertEqual(contentHandlerInvocations.first?.title, "Original")
        XCTAssertEqual(pendingPushDeliveryStoreMock.appendCallsCount, 0)
    }

    func test_handle_whenRichPushReturnsSamePush_expectContentHandlerWithOriginalContent() async {
        let request = makeCIORequest(title: "Original")
        richPushHandlerMock.startClosure = { req, completion in
            let content = UNNotificationWrapper(notificationRequest: req).notificationContent
            completion(.success(content))
        }

        let coordinator = makeCoordinator()
        await coordinator.handle(
            request: request,
            withContentHandler: contentHandlerForTests(),
            autoTrackDelivery: false
        )

        XCTAssertEqual(contentHandlerInvocations.count, 1)
        XCTAssertEqual(contentHandlerInvocations.first?.title, "Original")
    }

    // MARK: - Delivery logging

    func test_handle_whenDeliverySucceeds_expectLogPushMetricTracked() async {
        richPushDeliveryTrackerMock.trackMetricClosure = { _, _, _, _, completion in
            completion(.success(()))
        }
        richPushHandlerMock.startClosure = { _, completion in
            completion(.success(self.richContent(title: "Original")))
        }

        let coordinator = makeCoordinator(deliveryTracker: makeDeliveryTrackingAdapter())
        let request = makeCIORequest(deliveryID: "del-1", deviceToken: "tok-1")

        await coordinator.handle(
            request: request,
            withContentHandler: contentHandlerForTests(),
            autoTrackDelivery: true
        )

        XCTAssertEqual(pushLoggerMock.logPushMetricTrackedCallsCount, 1)
        XCTAssertEqual(pushLoggerMock.logPushMetricTrackedReceivedInvocations.first?.deliveryId, "del-1")
        XCTAssertEqual(pushLoggerMock.logPushMetricTrackedReceivedInvocations.first?.event, Metric.delivered.rawValue)
        XCTAssertEqual(pushLoggerMock.logPushMetricTrackingFailedCallsCount, 0)
        XCTAssertEqual(pendingPushDeliveryStoreMock.appendCallsCount, 1)
        XCTAssertEqual(pendingPushDeliveryStoreMock.removeCallsCount, 1)
    }

    func test_handle_whenDeliveryFails_expectLogPushMetricTrackingFailed() async {
        let testError = HttpRequestError.noRequestMade(nil)
        richPushDeliveryTrackerMock.trackMetricClosure = { _, _, _, _, completion in
            completion(.failure(testError))
        }
        richPushHandlerMock.startClosure = { _, completion in
            completion(.success(self.richContent(title: "Original")))
        }

        let coordinator = makeCoordinator(deliveryTracker: makeDeliveryTrackingAdapter())
        let request = makeCIORequest(deliveryID: "del-1")

        await coordinator.handle(
            request: request,
            withContentHandler: contentHandlerForTests(),
            autoTrackDelivery: true
        )

        XCTAssertEqual(pushLoggerMock.logPushMetricTrackingFailedCallsCount, 1)
        XCTAssertEqual(pushLoggerMock.logPushMetricTrackingFailedReceivedInvocations.first?.deliveryId, "del-1")
        XCTAssertEqual(pushLoggerMock.logPushMetricTrackedCallsCount, 0)
        XCTAssertEqual(pendingPushDeliveryStoreMock.appendCallsCount, 1)
        XCTAssertEqual(pendingPushDeliveryStoreMock.removeCallsCount, 0)
    }

    // MARK: - Cancel

    func test_cancel_beforeHandleCompletes_expectContentHandlerCalledOnceWithAvailableContent() async {
        var handleTask: Task<Void, Never>?
        let coordinator = makeCoordinator()
        let request = makeCIORequest()

        await withCheckedContinuation { (richPushEntered: CheckedContinuation<Void, Never>) in
            richPushHandlerMock.startClosure = { _, _ in
                richPushEntered.resume()
            }
            deliveryTrackingMock.trackMetricClosure = { _, _, _ in }

            handleTask = Task {
                await coordinator.handle(
                    request: request,
                    withContentHandler: contentHandlerForTests(),
                    autoTrackDelivery: true
                )
            }
        }
        coordinator.cancel()

        _ = handleTask

        XCTAssertEqual(contentHandlerInvocations.count, 1)
        XCTAssertEqual(richPushHandlerMock.stopAllCallsCount, 1)
        XCTAssertEqual(httpClientMock.cancelCallsCount, 1)
        XCTAssertEqual(httpClientMock.cancelReceivedInvocations.first, false)
        XCTAssertEqual(pendingPushDeliveryStoreMock.removeCallsCount, 0)
    }

    func test_cancel_whenCalledTwice_expectContentHandlerOnlyCalledOnce() async {
        var handleTask: Task<Void, Never>?
        var richPushResume: ((Result<UNNotificationContent, Error>) -> Void)?
        let coordinator = makeCoordinator()
        let request = makeCIORequest()

        await withCheckedContinuation { (richPushEntered: CheckedContinuation<Void, Never>) in
            richPushHandlerMock.startClosure = { _, completion in
                richPushResume = { result in completion(result) }
                richPushEntered.resume()
            }
            deliveryTrackingMock.trackMetricClosure = { _, _, completion in
                completion(.success(()))
            }

            handleTask = Task {
                await coordinator.handle(
                    request: request,
                    withContentHandler: contentHandlerForTests(),
                    autoTrackDelivery: true
                )
            }
        }
        coordinator.cancel()
        coordinator.cancel()
        richPushResume?(.success(richContent(title: "Rich")))

        _ = handleTask

        XCTAssertEqual(contentHandlerInvocations.count, 1)
        XCTAssertEqual(richPushHandlerMock.stopAllCallsCount, 1)
    }

    func test_cancel_whenInvokedFromOutside_expectContentHandlerAndStopAllCalled() async {
        var handleTask: Task<Void, Never>?
        let coordinator = makeCoordinator()
        let request = makeCIORequest()

        await withCheckedContinuation { (richPushEntered: CheckedContinuation<Void, Never>) in
            richPushHandlerMock.startClosure = { _, _ in
                richPushEntered.resume()
            }
            deliveryTrackingMock.trackMetricClosure = { _, _, _ in }

            handleTask = Task {
                await coordinator.handle(
                    request: request,
                    withContentHandler: contentHandlerForTests(),
                    autoTrackDelivery: true
                )
            }
        }
        coordinator.cancel()

        _ = handleTask

        XCTAssertEqual(contentHandlerInvocations.count, 1)
        XCTAssertEqual(richPushHandlerMock.stopAllCallsCount, 1)
    }
}

// MARK: - Mocks

private final class RichPushDeliveryTrackingMock: RichPushDeliveryTracking {
    var trackMetricCallsCount = 0
    var trackMetricClosure: ((UNNotificationRequest, RichPushDeliveryEvent, @escaping (Result<Void, Error>) -> Void) -> Void)?

    func trackMetric(
        request: UNNotificationRequest,
        event: RichPushDeliveryEvent,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        trackMetricCallsCount += 1
        trackMetricClosure?(request, event, completion)
    }
}

private final class RichPushRequestHandlingMock: RichPushRequestHandling {
    var startCallsCount = 0
    var startClosure: ((UNNotificationRequest, @escaping (Result<UNNotificationContent, Error>) -> Void) -> Void)?

    func start(
        request: UNNotificationRequest,
        completion: @escaping (Result<UNNotificationContent, Error>) -> Void
    ) {
        startCallsCount += 1
        startClosure?(request, completion)
    }

    var stopAllCallsCount = 0
    func stopAll() {
        stopAllCallsCount += 1
    }
}
