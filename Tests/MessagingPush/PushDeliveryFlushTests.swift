@testable import CioInternalCommon
@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

/// Verifies app-group pending push delivery metrics are flushed when MessagingPush starts (main app launch path).
///
/// The flush is owned by the push module: it loads metrics, sends each via ``DataPipelineTracking/trackDeliveryEvent(token:event:deliveryId:timestamp:)``,
/// then batch-removes them from the store. ``DataPipelineTracking`` is resolved at flush time via the DI
/// graph so the correct store (registered by ``MessagingPush/initialize(withConfig:)``) is always used.
final class MessagingPushPendingPushFlushTests: UnitTest {
    private var pendingStoreMock: PendingPushDeliveryStoreMock!
    private var pipelineMock: DataPipelineTrackingMock!

    private let pendingMetric = PendingPushDeliveryMetric(
        deliveryId: "pend-launch-1",
        deviceToken: "device-tok-1",
        event: .delivered,
        timestamp: Date()
    )

    override func setUp() {
        // Disable autoTrackPushEvents to skip automaticPushClickHandling.start() during MessagingPush.initialize()
        setUp(modifyModuleConfig: { $0.autoTrackPushEvents(false) })
    }

    override func setUpDependencies() {
        super.setUpDependencies()

        pendingStoreMock = PendingPushDeliveryStoreMock()
        pendingStoreMock.underlyingAppGroupSuiteName = "group.test.app.cio"
        pipelineMock = DataPipelineTrackingMock()

        // Register pipeline mock before initialize() so getOptional(DataPipelineTracking.self) returns it
        diGraphShared.register(pipelineMock, forType: DataPipelineTracking.self)
        // Override store so registerPendingPushDeliveryStore() inside initialize() doesn't replace it
        diGraphShared.override(value: pendingStoreMock, forType: PendingPushDeliveryStore.self)

        mockCollection.add(mock: pendingStoreMock)
    }

    override func initializeSDKComponents() -> MessagingPushInstance? {
        // Skip default init — each test calls MessagingPush.initialize() directly to trigger the flush
        nil
    }

    func test_initialize_flushesPendingMetrics_loadAllThenRemoveAllAfterEnqueue() {
        let loadExpectation = expectation(description: "pending store loadAll during MessagingPush flush")
        let removeExpectation = expectation(description: "pending store removeAll(ids:) after flushed metrics")
        let metric = pendingMetric
        pendingStoreMock.loadAllClosure = {
            loadExpectation.fulfill()
            return [metric]
        }
        pendingStoreMock.removeAllClosure = { ids in
            if ids.contains(metric.id) {
                removeExpectation.fulfill()
            }
            return true
        }

        MessagingPush.initialize(withConfig: messagingPushConfigOptions)

        wait(for: [loadExpectation, removeExpectation], timeout: 2.0)
        XCTAssertEqual(pendingStoreMock.loadAllCallsCount, 1, "startup should read pending list from app group store")
        XCTAssertEqual(pendingStoreMock.removeAllCallsCount, 1, "flushed rows should be batch-removed via removeAll(ids:)")
        XCTAssertEqual(pendingStoreMock.removeAllReceivedArguments, Set([metric.id]))
        XCTAssertEqual(pipelineMock.trackDeliveryEventCallsCount, 1, "each pending metric should be forwarded to DataPipeline")
        XCTAssertEqual(pipelineMock.trackDeliveryEventInvocations.first?.deliveryId, metric.deliveryId)
        XCTAssertEqual(pipelineMock.trackDeliveryEventInvocations.first?.token, metric.deviceToken)
        XCTAssertEqual(pipelineMock.trackDeliveryEventInvocations.first?.event, metric.event.rawValue)
    }

    func test_initialize_whenNoPendingMetrics_expectLoadAllOnlyNoRemoves() {
        let loadExpectation = expectation(description: "pending store loadAll during MessagingPush flush (empty store)")
        pendingStoreMock.loadAllClosure = {
            loadExpectation.fulfill()
            return []
        }

        MessagingPush.initialize(withConfig: messagingPushConfigOptions)

        wait(for: [loadExpectation], timeout: 2.0)
        XCTAssertEqual(pendingStoreMock.loadAllCallsCount, 1)
        XCTAssertEqual(pendingStoreMock.removeAllCallsCount, 0, "removeAll should not be called when store is empty")
        XCTAssertEqual(pipelineMock.trackDeliveryEventCallsCount, 0, "no metrics should be forwarded when store is empty")
    }

    func test_initialize_whenDataPipelineNotInitialized_expectLoadAllButNoTracking() {
        // Simulate DataPipeline not being initialized — no DataPipelineTracking registered
        diGraphShared.reset()
        diGraphShared.override(value: pendingStoreMock, forType: PendingPushDeliveryStore.self)

        let loadExpectation = expectation(description: "pending store loadAll called even without DataPipeline")
        let metric = pendingMetric
        pendingStoreMock.loadAllClosure = {
            loadExpectation.fulfill()
            return [metric]
        }
        pendingStoreMock.removeAllReturnValue = true

        MessagingPush.initialize(withConfig: messagingPushConfigOptions)

        wait(for: [loadExpectation], timeout: 2.0)
        XCTAssertEqual(pipelineMock.trackDeliveryEventCallsCount, 0, "no events should be tracked when DataPipeline is absent")
        XCTAssertEqual(pendingStoreMock.removeAllCallsCount, 0, "metrics must be preserved in the store when DataPipeline is absent")
    }
}
