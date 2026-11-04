@testable import CioMessagingPush
@_spi(Internal) @testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioMessagingPushMocks
import Foundation
import XCTest

class BackgroundPushTest: UnitTest {
    private var receiptStore: PendingPushDeliveryStore!

    func test_beforeInitialization_returnsDataUsingDefaultConfigWithoutCrashing() {
        MessagingPush.resetTestEnvironment()
        XCTAssertFalse(MessagingPush.shared.hasBeenInitialized)
        XCTAssertTrue(MessagingPush.moduleConfig.autoTrackPushEvents)

        guard case .received(let payload) = MessagingPush.shared.handleBackgroundPush(userInfo: userInfo()) else {
            return XCTFail("An uninitialized receipt tracker must not hide background data")
        }
        XCTAssertEqual(payload.deliveryID, "dlv_123")
    }

    func test_goEncodedAPNsAndFCMFixtures_returnUnchangedDataWithTransportMetadataRemoved() async throws {
        for (json, fcm) in [(BackgroundPushFixtures.apns, false), (BackgroundPushFixtures.fcm, true)] {
            let mock = installMock()
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
            var userInfo: [String: Any]
            if fcm {
                let message = try XCTUnwrap(object["message"] as? [String: Any])
                let apns = try XCTUnwrap(message["apns"] as? [String: Any])
                userInfo = try XCTUnwrap(apns["payload"] as? [String: Any])
                // FCM adds transport metadata when delivering this payload.
                userInfo["gcm.message_id"] = "provider-message"
                userInfo["google.c.a.e"] = 1
            } else {
                userInfo = object
            }
            guard case .received(let payload) = MessagingPush.shared.handleBackgroundPush(userInfo: userInfo) else {
                return XCTFail("The Go-encoded payload must be accepted unchanged")
            }
            XCTAssertEqual(payload.deliveryID, "fixture-delivery-1")
            XCTAssertEqual(payload.data, ["title": "Order shipped", "order_id": "A-1001", "note": "line one\nsays \"hi\" <b>&</b> ✓", "cıo-x": "dotless"])
            XCTAssertEqual(payload.deliveryToken, fcm ? "fixture-fcm-token-1" : "fixture-apns-token-1")
            XCTAssertEqual(receiptStore.loadAll().first?.deviceToken, payload.deliveryToken)
            XCTAssertEqual(mock.trackMetricCallsCount, 0)
            await MessagingPush.backgroundPushReceiptSender?.waitUntilIdle()
        }
    }

    private func userInfo() -> [AnyHashable: Any] {
        [
            "aps": ["content-available": 1],
            "CIO-Background-Version": "1",
            "CIO-Background-Delivery-ID": "dlv_123",
            "CIO-Background-Delivery-Token": "tok_abc",
            "title": "Order shipped", "body": "", "order_id": "42"
        ]
    }

    private func installMock(autoTrack: Bool = true) -> MessagingPushInstanceMock {
        let mock = MessagingPushInstanceMock()
        mockCollection.add(mock: mock)
        MessagingPush.setUpSharedInstanceForUnitTest(
            implementation: mock,
            diGraphShared: diGraphShared,
            config: MessagingPushConfigBuilder().autoTrackPushEvents(autoTrack).build()
        )
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("receipts.json")
        receiptStore = CioAppGroupPendingPushDeliveryStore(privateFileURL: file, logger: log)
        let client = BackgroundDeliveryHttpClientMock()
        client.sendTrackEventClosure = { _, completion in completion(.failure(.transport)) }
        MessagingPush.backgroundPushReceiptSender = BackgroundPushReceiptSender(store: receiptStore, httpClient: client, taskRunner: NoBackgroundTaskRunner(), logger: log)
        addTeardownBlock { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        return mock
    }

    func test_validBackgroundPush_tracksOnlyDeliveredWithItsOwnReceiptToken() {
        let mock = installMock()
        var payload = userInfo()
        payload["gcm.message_id"] = "provider-metadata"
        guard case .received(let received) = MessagingPush.shared.handleBackgroundPush(userInfo: payload) else {
            return XCTFail("Expected background data")
        }
        XCTAssertNil(received.data["gcm.message_id"])
        XCTAssertEqual(mock.trackMetricCallsCount, 0)
        XCTAssertEqual(receiptStore.loadAll().count, 1)
        XCTAssertEqual(receiptStore.loadAll().first?.deliveryId, "dlv_123")
        XCTAssertEqual(receiptStore.loadAll().first?.deviceToken, "tok_abc")
        XCTAssertEqual(receiptStore.loadAll().first?.event, .delivered)
    }

    func test_autoTrackingDisabled_stillReturnsDataWithoutTracking() {
        let mock = installMock(autoTrack: false)
        guard case .received(let payload) = MessagingPush.shared.handleBackgroundPush(userInfo: userInfo()) else {
            return XCTFail("Automatic metrics must not gate business data")
        }
        XCTAssertEqual(payload.deliveryToken, "tok_abc")
        XCTAssertTrue(receiptStore.loadAll().isEmpty)
        XCTAssertEqual(mock.trackMetricCallsCount, 0)
    }

    func test_repeatedBackgroundPush_requestsReceiptForEachInvocation() {
        let mock = installMock()

        for _ in 0 ..< 2 {
            guard case .received = MessagingPush.shared.handleBackgroundPush(userInfo: userInfo()) else {
                return XCTFail("A repeated delivery must remain available to the host")
            }
        }

        XCTAssertEqual(mock.trackMetricCallsCount, 0)
        XCTAssertEqual(receiptStore.loadAll().map(\.deliveryId), ["dlv_123", "dlv_123"])
    }

    func test_invalidMarkedPayloads_areUnsupportedWithoutMetrics() {
        let mock = installMock()
        let invalidChanges: [(String, Any?)] = [
            ("CIO-Background-Version", "2"),
            ("CIO-Background-Version", nil),
            ("CIO-Background-Delivery-Token", nil),
            ("CIO-Background-Delivery-ID", " "),
            ("CIO-Delivery-ID", "legacy"),
            ("CIO-Delivery-Token", "legacy"),
            ("CIO-Background-Unknown", "future"),
            ("order_id", 42),
            ("aps", ["content-available": 1, "alert": "visible"]),
            ("aps", ["content-available": 1, "sound": "default"]),
            ("aps", ["content-available": 1, "badge": 1]),
            ("aps", ["content-available": true]),
            ("aps", ["content-available": 1.1]),
            ("aps", nil)
        ]
        for (key, value) in invalidChanges {
            var payload = userInfo()
            payload[key] = value
            XCTAssertEqual(MessagingPush.shared.handleBackgroundPush(userInfo: payload), .unsupported, "Invalid field: \(key)")
        }
        XCTAssertEqual(mock.trackMetricCallsCount, 0)
        XCTAssertTrue(receiptStore.loadAll().isEmpty)
    }

    func test_legacyAndForeignPushes_remainAvailableToExistingHandlers() {
        let mock = installMock()
        for payload: [AnyHashable: Any] in [[:], ["CIO-Delivery-ID": "old", "CIO-Delivery-Token": "old"], ["order_id": "42"]] {
            XCTAssertEqual(MessagingPush.shared.handleBackgroundPush(userInfo: payload), .notBackground)
        }
        XCTAssertEqual(mock.trackMetricCallsCount, 0)
        XCTAssertTrue(receiptStore.loadAll().isEmpty)
    }

    func test_legacyBusinessKeys_includingBackgroundMetadata_remainAvailableToExistingHandlers() {
        let mock = installMock()
        for key in ["CIO-Background-Version", "CIO-Background-Delivery-ID", "CIO-Background-Delivery-Token", "CIO-Background-sync", "cio-background-version", "CIO-Background-Delivery-ID-extra"] {
            let payload: [AnyHashable: Any] = [
                "CIO-Delivery-ID": "old", "CIO-Delivery-Token": "old", key: "existing business data"
            ]
            XCTAssertEqual(MessagingPush.shared.handleBackgroundPush(userInfo: payload), .notBackground, key)
        }
        XCTAssertEqual(mock.trackMetricCallsCount, 0)
        XCTAssertTrue(receiptStore.loadAll().isEmpty)
    }

    func test_legacyTrackingPair_takesPrecedenceOverBackgroundMetadata() {
        let mock = installMock()
        var payload = userInfo()
        payload["CIO-Delivery-ID"] = "legacy-delivery"
        payload["CIO-Delivery-Token"] = "legacy-token"
        payload["CIO-Background-Version"] = "2"

        XCTAssertEqual(MessagingPush.shared.handleBackgroundPush(userInfo: payload), .notBackground)
        XCTAssertEqual(mock.trackMetricCallsCount, 0)
        XCTAssertTrue(receiptStore.loadAll().isEmpty)
    }

    func test_validBackgroundPush_returnsBusinessDataIncludingTitleAndBody() {
        let result = MessagingPush.shared.handleBackgroundPush(userInfo: [
            "aps": ["content-available": 1],
            "CIO-Background-Version": "1",
            "CIO-Background-Delivery-ID": "dlv_123",
            "CIO-Background-Delivery-Token": "tok_abc",
            "title": "Order shipped",
            "body": "",
            "order_id": "42"
        ])

        guard case .received(let payload) = result else {
            return XCTFail("A valid background push must reach the host")
        }
        XCTAssertEqual(payload.deliveryID, "dlv_123")
        XCTAssertEqual(payload.data, ["title": "Order shipped", "body": "", "order_id": "42"])
    }
}
