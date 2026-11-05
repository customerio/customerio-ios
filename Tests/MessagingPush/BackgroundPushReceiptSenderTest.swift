@_spi(Internal) @testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioMessagingPush
import Foundation
import XCTest

final class BackgroundPushReceiptSenderTest: XCTestCase {
    private func makeStore() -> CioAppGroupPendingPushDeliveryStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return CioAppGroupPendingPushDeliveryStore(privateFileURL: directory.appendingPathComponent("receipts.json"), logger: LoggerMock())
    }

    /// Holds the first request open until the test completes it. Later requests succeed.
    private final class HeldFirstRequest {
        let inFlight: XCTestExpectation
        let deliveryIDs = Synchronized<[String]>([])
        let completion = Synchronized<((Result<Void, BackgroundDeliveryHttpError>) -> Void)?>(nil)

        init(inFlight: XCTestExpectation) {
            self.inFlight = inFlight
        }

        func complete(_ result: Result<Void, BackgroundDeliveryHttpError>) {
            completion.wrappedValue?(result)
        }
    }

    private func holdFirstRequest(of client: BackgroundDeliveryHttpClientMock) -> HeldFirstRequest {
        let held = HeldFirstRequest(inFlight: expectation(description: "First request paused"))
        client.sendTrackEventClosure = { request, done in
            let first = held.deliveryIDs.mutating { ids -> Bool in
                ids.append(request.anonymousId ?? "")
                return ids.count == 1
            }
            if first {
                held.completion.wrappedValue = done
                held.inFlight.fulfill()
            } else {
                done(.success(()))
            }
        }
        return held
    }

    /// A sender as `MessagingPush.initialize` leaves it: started, with automatic tracking on.
    /// Its clock stands still, so a slow run never reaches the drain deadline.
    private func makeSender(
        store: PendingPushDeliveryStore,
        client: BackgroundDeliveryHttpClient,
        uptime: @escaping @Sendable () -> TimeInterval = { 0 }
    ) -> BackgroundPushReceiptSender {
        let sender = BackgroundPushReceiptSender(store: store, httpClient: client, taskRunner: NoBackgroundTaskRunner(), logger: LoggerMock(), uptime: uptime)
        sender.start(autoTrackPushEvents: true)
        return sender
    }

    func test_persistsBeforeReturningAndRemovesOnlyAfterAcceptance() async {
        let store = makeStore()
        let client = BackgroundDeliveryHttpClientMock()
        let inFlight = expectation(description: "HTTP request in flight")
        let completion = Synchronized<((Result<Void, BackgroundDeliveryHttpError>) -> Void)?>(nil)
        client.sendTrackEventClosure = { _, done in completion.wrappedValue = done
            inFlight.fulfill()
        }
        let sender = makeSender(store: store, client: client)
        let receivedAt = Date(timeIntervalSince1970: 1700000000)
        sender.enqueue(deliveryID: "delivery", deviceToken: "original-target", receivedAt: receivedAt)
        XCTAssertEqual(store.loadAll().first?.deliveryId, "delivery")
        XCTAssertEqual(store.loadAll().first?.deviceToken, "original-target")
        XCTAssertEqual(store.loadAll().first?.timestamp, receivedAt)
        await fulfillment(of: [inFlight], timeout: 2)
        XCTAssertEqual(client.sendTrackEventReceivedArguments?.request.anonymousId, "delivery")
        XCTAssertEqual(client.sendTrackEventReceivedArguments?.request.properties["metric"] as? String, "delivered")
        completion.wrappedValue?(.success(()))
        await sender.waitUntilIdle()
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func test_retryableErrorsSurviveAHostRestartWithOriginalTimestamp() async {
        for error: BackgroundDeliveryHttpError in [.transport, .missingCdpApiKey, .missingApiHost, .invalidRequest, .http(statusCode: 401), .http(statusCode: 403), .http(statusCode: 408), .http(statusCode: 429), .http(statusCode: 500)] {
            let store = makeStore()
            let failed = BackgroundDeliveryHttpClientMock()
            failed.sendTrackEventClosure = { _, done in done(.failure(error)) }
            let first = makeSender(store: store, client: failed)
            let receivedAt = Date(timeIntervalSince1970: 1700000000)
            first.enqueue(deliveryID: "delivery", deviceToken: "original-target", receivedAt: receivedAt)
            await first.waitUntilIdle()
            XCTAssertEqual(store.loadAll().count, 1, "\(error)")
            let recovered = BackgroundDeliveryHttpClientMock()
            recovered.sendTrackEventClosure = { _, done in done(.success(())) }
            let nextLaunch = makeSender(store: store, client: recovered)
            nextLaunch.scheduleDrain()
            await nextLaunch.waitUntilIdle()
            XCTAssertEqual(recovered.sendTrackEventReceivedArguments?.request.timestamp, receivedAt)
            XCTAssertEqual(recovered.sendTrackEventReceivedArguments?.request.properties["recipient"] as? String, "original-target")
            XCTAssertTrue(store.loadAll().isEmpty)
        }
    }

    func test_deliveryAlreadySentThisLaunch_isNotSentAgain() async {
        let store = makeStore()
        let client = BackgroundDeliveryHttpClientMock()
        client.sendTrackEventClosure = { _, done in done(.success(())) }
        let sender = makeSender(store: store, client: client)

        sender.enqueue(deliveryID: "delivery", deviceToken: "target", receivedAt: Date())
        await sender.waitUntilIdle()
        sender.enqueue(deliveryID: "delivery", deviceToken: "target", receivedAt: Date())
        await sender.waitUntilIdle()

        XCTAssertEqual(client.sendTrackEventCallsCount, 1)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func test_deliverySentFromAnEarlierLaunchsRow_isNotRecordedAgainThisLaunch() async {
        let store = makeStore()
        XCTAssertTrue(store.append(PendingPushDeliveryMetric(deliveryId: "delivery", deviceToken: "target", event: .delivered, timestamp: Date())))
        let client = BackgroundDeliveryHttpClientMock()
        client.sendTrackEventClosure = { _, done in done(.success(())) }
        let sender = makeSender(store: store, client: client)
        await sender.waitUntilIdle()
        XCTAssertEqual(client.sendTrackEventCallsCount, 1)

        // The same push again, for example from an app handler that runs after the wrapper recorded it.
        sender.enqueue(deliveryID: "delivery", deviceToken: "target", receivedAt: Date())
        await sender.waitUntilIdle()

        XCTAssertEqual(client.sendTrackEventCallsCount, 1)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func test_deliveryStillPendingFromAnEarlierLaunch_isSavedOnce() async {
        let store = makeStore()
        let receivedAt = Date(timeIntervalSince1970: 1700000000)
        XCTAssertTrue(store.append(PendingPushDeliveryMetric(deliveryId: "delivery", deviceToken: "target", event: .delivered, timestamp: receivedAt)))
        let client = BackgroundDeliveryHttpClientMock()
        client.sendTrackEventClosure = { _, done in done(.failure(.transport)) }
        let nextLaunch = makeSender(store: store, client: client)

        nextLaunch.enqueue(deliveryID: "delivery", deviceToken: "target", receivedAt: Date())
        await nextLaunch.waitUntilIdle()

        XCTAssertEqual(store.loadAll().map(\.deliveryId), ["delivery"])
        XCTAssertEqual(store.loadAll().first?.timestamp, receivedAt)
    }

    func test_duplicateArrivingAfterAFailedSend_retriesTheSavedReceipt() async {
        let store = makeStore()
        let client = BackgroundDeliveryHttpClientMock()
        let online = Synchronized(false)
        client.sendTrackEventClosure = { _, done in done(online.wrappedValue ? .success(()) : .failure(.transport)) }
        let sender = makeSender(store: store, client: client)
        let receivedAt = Date(timeIntervalSince1970: 1700000000)

        sender.enqueue(deliveryID: "delivery", deviceToken: "target", receivedAt: receivedAt)
        await sender.waitUntilIdle()
        XCTAssertEqual(store.loadAll().count, 1)
        online.wrappedValue = true
        sender.enqueue(deliveryID: "delivery", deviceToken: "target", receivedAt: Date())
        await sender.waitUntilIdle()

        XCTAssertEqual(client.sendTrackEventCallsCount, 2)
        XCTAssertEqual(client.sendTrackEventReceivedArguments?.request.timestamp, receivedAt)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func test_receiptsSavedBeforeStart_waitForStartAndAreSent() async {
        let store = makeStore()
        let client = BackgroundDeliveryHttpClientMock()
        client.sendTrackEventClosure = { _, done in done(.success(())) }
        let sender = BackgroundPushReceiptSender(store: store, httpClient: client, taskRunner: NoBackgroundTaskRunner(), logger: LoggerMock())

        sender.enqueue(deliveryID: "early", deviceToken: "target", receivedAt: Date())
        await sender.waitUntilIdle()
        XCTAssertEqual(client.sendTrackEventCallsCount, 0)
        XCTAssertEqual(store.loadAll().map(\.deliveryId), ["early"])

        sender.start(autoTrackPushEvents: true)
        await sender.waitUntilIdle()
        XCTAssertEqual(client.sendTrackEventCallsCount, 1)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func test_receiptsSavedBeforeStart_withAutoTrackingOff_areRemovedUnsent() async {
        let store = makeStore()
        let receivedAt = Date(timeIntervalSince1970: 1700000000)
        // Saved by an earlier launch, which had automatic tracking on.
        XCTAssertTrue(store.append(PendingPushDeliveryMetric(deliveryId: "earlier-launch", deviceToken: "target", event: .delivered, timestamp: receivedAt)))
        let client = BackgroundDeliveryHttpClientMock()
        client.sendTrackEventClosure = { _, done in done(.failure(.transport)) }
        let sender = BackgroundPushReceiptSender(store: store, httpClient: client, taskRunner: NoBackgroundTaskRunner(), logger: LoggerMock())

        sender.enqueue(deliveryID: "early", deviceToken: "target", receivedAt: Date())
        sender.start(autoTrackPushEvents: false)
        await sender.waitUntilIdle()

        XCTAssertEqual(store.loadAll().map(\.deliveryId), ["earlier-launch"])
        XCTAssertFalse(client.sendTrackEventReceivedInvocations.contains { $0.request.anonymousId == "early" })
    }

    func test_concurrentDuplicates_saveOneReceipt() async {
        let store = makeStore()
        let client = BackgroundDeliveryHttpClientMock()
        client.sendTrackEventClosure = { _, done in done(.failure(.transport)) }
        let sender = makeSender(store: store, client: client)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 20 {
                group.addTask { sender.enqueue(deliveryID: "delivery", deviceToken: "target", receivedAt: Date()) }
            }
        }
        await sender.waitUntilIdle()

        XCTAssertEqual(store.loadAll().map(\.deliveryId), ["delivery"])
    }

    func test_permanentHTTP400LeavesNoRetry() async {
        let store = makeStore()
        let client = BackgroundDeliveryHttpClientMock()
        client.sendTrackEventClosure = { _, done in done(.failure(.http(statusCode: 400))) }
        let sender = makeSender(store: store, client: client)
        sender.enqueue(deliveryID: "delivery", deviceToken: "target", receivedAt: Date())
        await sender.waitUntilIdle()
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func test_unavailableFileStillSendsFromMemory() async {
        let store = CioAppGroupPendingPushDeliveryStore(privateFileURL: nil, logger: LoggerMock())
        let client = BackgroundDeliveryHttpClientMock()
        client.sendTrackEventClosure = { _, done in done(.success(())) }
        let sender = makeSender(store: store, client: client)
        sender.enqueue(deliveryID: "delivery", deviceToken: "target", receivedAt: Date())
        await sender.waitUntilIdle()
        sender.scheduleDrain()
        await sender.waitUntilIdle()
        XCTAssertEqual(client.sendTrackEventCallsCount, 1)
    }

    func test_newReceiptsWhileSendingDrainWithoutConcurrentHTTPRequests() async {
        let store = makeStore()
        let client = BackgroundDeliveryHttpClientMock()
        let firstRequest = holdFirstRequest(of: client)
        let sender = makeSender(store: store, client: client)
        sender.enqueue(deliveryID: "first", deviceToken: "target", receivedAt: Date())
        await fulfillment(of: [firstRequest.inFlight], timeout: 2)
        sender.enqueue(deliveryID: "second", deviceToken: "target", receivedAt: Date())
        sender.enqueue(deliveryID: "third", deviceToken: "target", receivedAt: Date())
        XCTAssertEqual(firstRequest.deliveryIDs.wrappedValue, ["first"])
        firstRequest.complete(.success(()))
        await sender.waitUntilIdle()
        XCTAssertEqual(firstRequest.deliveryIDs.wrappedValue, ["first", "second", "third"])
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func test_newReceiptDuringAFailedSendGetsAnotherAttemptWithoutWaitingForLaunch() async {
        let store = makeStore()
        let client = BackgroundDeliveryHttpClientMock()
        let firstRequest = holdFirstRequest(of: client)
        let sender = makeSender(store: store, client: client)
        sender.enqueue(deliveryID: "first", deviceToken: "target", receivedAt: Date())
        await fulfillment(of: [firstRequest.inFlight], timeout: 2)
        sender.enqueue(deliveryID: "second", deviceToken: "target", receivedAt: Date())
        firstRequest.complete(.failure(.transport))
        await sender.waitUntilIdle()
        XCTAssertEqual(firstRequest.deliveryIDs.wrappedValue, ["first", "first", "second"])
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func test_permanentlyRejectedRowCannotBlockTheNextReceipt() async {
        let store = makeStore()
        let now = Date()
        XCTAssertTrue(store.append(PendingPushDeliveryMetric(deliveryId: "invalid", deviceToken: "target", event: .delivered, timestamp: now)))
        XCTAssertTrue(store.append(PendingPushDeliveryMetric(deliveryId: "valid", deviceToken: "target", event: .delivered, timestamp: now)))
        let client = BackgroundDeliveryHttpClientMock()
        client.sendTrackEventClosure = { request, done in
            done(request.anonymousId == "invalid" ? .failure(.http(statusCode: 422)) : .success(()))
        }
        let sender = makeSender(store: store, client: client)
        sender.scheduleDrain()
        await sender.waitUntilIdle()
        XCTAssertEqual(client.sendTrackEventCallsCount, 2)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func test_drainReachingItsDeadline_leavesTheRestSaved() async {
        let store = makeStore()
        for id in ["first", "second", "third"] {
            XCTAssertTrue(store.append(PendingPushDeliveryMetric(deliveryId: id, deviceToken: "target", event: .delivered, timestamp: Date())))
        }
        let client = BackgroundDeliveryHttpClientMock()
        client.sendTrackEventClosure = { _, done in done(.success(())) }
        // Two seconds pass on every reading, so the five-second deadline arrives before the third send.
        let clock = Synchronized<TimeInterval>(0)
        let sender = makeSender(store: store, client: client, uptime: {
            clock.mutating { now in
                defer { now += 2 }
                return now
            }
        })
        await sender.waitUntilIdle()
        XCTAssertEqual(client.sendTrackEventCallsCount, 2)
        XCTAssertEqual(store.loadAll().map(\.deliveryId), ["third"])
    }

    func test_concurrentEnqueuesAndAcknowledgementsKeepEveryReceipt() async {
        let store = makeStore()
        let client = BackgroundDeliveryHttpClientMock()
        let sent = Synchronized<Set<String>>([])
        client.sendTrackEventClosure = { request, done in
            _ = sent.mutating { $0.insert(request.anonymousId ?? "") }
            done(.success(()))
        }
        let sender = makeSender(store: store, client: client)
        await withTaskGroup(of: Void.self) { group in
            for id in 0 ..< 100 {
                group.addTask { sender.enqueue(deliveryID: String(id), deviceToken: "target", receivedAt: Date()) }
            }
        }
        await sender.waitUntilIdle()
        XCTAssertEqual(sent.wrappedValue, Set((0 ..< 100).map(String.init)))
        XCTAssertEqual(store.read(), .rows([]))
    }
}
