@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

/// Verifies app-group pending push delivery metrics are flushed when MessagingPush starts (main app launch path).
///
/// The flush is owned by the push module: it loads metrics, sends each via ``DataPipelineTracking/trackDeliveryEvent(token:event:deliveryId:timestamp:)``,
/// then batch-removes them from the store. ``DataPipelineTracking`` is resolved at flush time via the DI
/// graph so the correct store (registered by ``MessagingPush/initialize(withConfig:)``) is always used.
///
/// The flush runs on a detached background task. Each test drains it deterministically via
/// ``MessagingPush/awaitPendingMetricsFlushForTests()`` before asserting, so results never depend on a timeout
/// and a flush can never outlive its test and contaminate the next test's DI overrides.
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

        // Override pipeline mock so it is scoped to this test and cleaned up between tests,
        // preventing a stale Task.detached from a prior test resolving the wrong mock instance.
        diGraphShared.override(value: pipelineMock, forType: DataPipelineTracking.self)
        // Override store so registerPendingPushDeliveryStore() inside initialize() doesn't replace it
        diGraphShared.override(value: pendingStoreMock, forType: PendingPushDeliveryStore.self)

        mockCollection.add(mock: pendingStoreMock)
    }

    override func initializeSDKComponents() -> MessagingPushInstance? {
        // Skip default init — each test calls MessagingPush.initialize() directly to trigger the flush
        nil
    }

    func test_initialize_flushesPendingMetrics_loadAllThenRemoveAllAfterEnqueue() {
        let metric = pendingMetric
        pendingStoreMock.loadAllReturnValue = [metric]
        pendingStoreMock.removeAllReturnValue = true

        MessagingPush.initialize(withConfig: messagingPushConfigOptions)
        // Deterministically drain the scheduled flush instead of racing a 2s timeout.
        MessagingPush.awaitPendingMetricsFlushForTests()

        XCTAssertEqual(pendingStoreMock.loadAllCallsCount, 1, "startup should read pending list from app group store")
        XCTAssertEqual(pendingStoreMock.removeAllCallsCount, 1, "flushed rows should be batch-removed via removeAll(ids:)")
        XCTAssertEqual(pendingStoreMock.removeAllReceivedArguments, Set([metric.id]))
        XCTAssertEqual(pipelineMock.trackDeliveryEventCallsCount, 1, "each pending metric should be forwarded to DataPipeline")
        XCTAssertEqual(pipelineMock.trackDeliveryEventInvocations.first?.deliveryId, metric.deliveryId)
        XCTAssertEqual(pipelineMock.trackDeliveryEventInvocations.first?.token, metric.deviceToken)
        XCTAssertEqual(pipelineMock.trackDeliveryEventInvocations.first?.event, metric.event.rawValue)
    }

    func test_initialize_whenNoPendingMetrics_expectLoadAllOnlyNoRemoves() {
        pendingStoreMock.loadAllReturnValue = []

        MessagingPush.initialize(withConfig: messagingPushConfigOptions)
        // Deterministically drain the scheduled flush so a leaked flush from a prior test cannot land here.
        MessagingPush.awaitPendingMetricsFlushForTests()

        XCTAssertEqual(pendingStoreMock.loadAllCallsCount, 1)
        XCTAssertEqual(pendingStoreMock.removeAllCallsCount, 0, "removeAll should not be called when store is empty")
        XCTAssertEqual(pipelineMock.trackDeliveryEventCallsCount, 0, "no metrics should be forwarded when store is empty")
    }

    func test_initialize_whenDataPipelineNotInitialized_expectLoadAllButNoTracking() {
        // Simulate DataPipeline not being initialized — no DataPipelineTracking registered
        diGraphShared.reset()
        diGraphShared.override(value: pendingStoreMock, forType: PendingPushDeliveryStore.self)

        let metric = pendingMetric
        pendingStoreMock.loadAllReturnValue = [metric]
        pendingStoreMock.removeAllReturnValue = true

        MessagingPush.initialize(withConfig: messagingPushConfigOptions)
        MessagingPush.awaitPendingMetricsFlushForTests()

        XCTAssertEqual(pipelineMock.trackDeliveryEventCallsCount, 0, "no events should be tracked when DataPipeline is absent")
        XCTAssertEqual(pendingStoreMock.removeAllCallsCount, 0, "metrics must be preserved in the store when DataPipeline is absent")
    }

    /// Regression guard for the flaky flush leak (MBL-2202): ``MessagingPush/initialize(withConfig:)`` must
    /// retain the detached flush task so teardown can drain it. Without a retained handle the flush is
    /// un-awaitable and can outlive this test, landing on the next test's freshly-overridden pipeline mock and
    /// forwarding a stray metric (the "1 != 0" flake). Awaiting the handle is also the deterministic replacement
    /// for the old `wait(for:timeout:)` race.
    func test_initialize_retainsFlushTaskHandle_soTeardownCanDrainIt() {
        let metric = pendingMetric
        pendingStoreMock.loadAllReturnValue = [metric]
        pendingStoreMock.removeAllReturnValue = true

        MessagingPush.initialize(withConfig: messagingPushConfigOptions)

        XCTAssertNotNil(
            MessagingPush.pendingMetricsFlushTask,
            "initialize() must retain the detached flush task so teardown can await it instead of leaking it"
        )

        // Deterministically drain to completion; the retained handle makes this exact, not timeout-based.
        MessagingPush.awaitPendingMetricsFlushForTests()

        XCTAssertNil(
            MessagingPush.pendingMetricsFlushTask,
            "draining the flush must clear the handle so no task survives into the next test"
        )
        XCTAssertEqual(
            pipelineMock.trackDeliveryEventCallsCount,
            1,
            "the retained flush should have forwarded the pending metric before teardown returns"
        )
    }
}
