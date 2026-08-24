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

    // MARK: - Regression: detached flush must not leak across tests (MBL-2202)

    /// Regression for the flaky cross-test contamination: `initialize()` schedules the flush on a
    /// detached task. Before the fix that task was not retained, so teardown could not await it and a
    /// flush started by one test resolved the next test's freshly-overridden pipeline mock, forwarding
    /// a phantom metric onto an "empty store" test.
    ///
    /// This test proves `resetTestEnvironment()` drains the in-flight flush to completion before it
    /// returns. Determinism comes from a rendezvous (the flush parks inside `loadAll` on a semaphore
    /// until the test releases it) plus an await-to-completion on the retained handle -- no sleeps and
    /// no timeout-based race on the drain itself.
    func test_resetTestEnvironment_drainsInFlightFlushToCompletion() {
        let flushStarted = DispatchSemaphore(value: 0)
        let releaseFlush = DispatchSemaphore(value: 0)
        let metric = pendingMetric

        pendingStoreMock.loadAllClosure = {
            // Signal the flush is executing, then park it so it is guaranteed in-flight at reset.
            flushStarted.signal()
            releaseFlush.wait()
            return [metric]
        }
        pendingStoreMock.removeAllReturnValue = true

        MessagingPush.initialize(withConfig: messagingPushConfigOptions)

        // Deterministic rendezvous: proceed only once the detached flush is actually running.
        XCTAssertEqual(flushStarted.wait(timeout: .now() + 5.0), .success, "detached flush task should start")

        let inFlightTask = MessagingPush.pendingMetricsFlushTask
        XCTAssertNotNil(inFlightTask, "initialize must retain the flush task handle so reset can drain it")

        // Let the parked flush run to completion once reset awaits it, then drain via reset.
        releaseFlush.signal()
        MessagingPush.resetTestEnvironment()

        // reset() cancels the retained handle and awaits it to completion.
        XCTAssertTrue(inFlightTask?.isCancelled ?? false, "reset should cancel the retained flush task")
        // Awaiting a settled task returns immediately; this asserts the drain fully completed.
        let settled = expectation(description: "flush task fully settled after reset")
        Task {
            await inFlightTask?.value
            settled.fulfill()
        }
        wait(for: [settled], timeout: 5.0)
        XCTAssertEqual(pendingStoreMock.loadAllCallsCount, 1)
    }

    /// Regression for the exact contamination semantics: a flush scheduled by "test A" must never
    /// forward a metric onto the pipeline mock that "test B" registers afterwards. With the drain in
    /// place, test A's teardown awaits the flush to completion (forwarding onto test A's own pipeline),
    /// so a mock registered after the drain is guaranteed to observe zero forwarded metrics.
    func test_resetTestEnvironment_preventsFlushFromLeakingOntoNextTestPipeline() {
        let flushStarted = DispatchSemaphore(value: 0)
        let releaseFlush = DispatchSemaphore(value: 0)
        let metric = pendingMetric

        pendingStoreMock.loadAllClosure = {
            flushStarted.signal()
            releaseFlush.wait()
            return [metric]
        }
        pendingStoreMock.removeAllReturnValue = true

        let pipelineForTestA = pipelineMock!

        MessagingPush.initialize(withConfig: messagingPushConfigOptions)
        XCTAssertEqual(flushStarted.wait(timeout: .now() + 5.0), .success, "detached flush task should start")

        // "Test A" teardown: release the parked flush and drain it deterministically.
        releaseFlush.signal()
        MessagingPush.resetTestEnvironment()

        // "Test B": register a fresh pipeline mock AFTER the drain has completed.
        let pipelineForTestB = DataPipelineTrackingMock()
        diGraphShared.override(value: pipelineForTestB, forType: DataPipelineTracking.self)

        XCTAssertEqual(
            pipelineForTestB.trackDeliveryEventCallsCount, 0,
            "a drained flush from a prior test must never forward metrics onto the next test's pipeline mock"
        )
        XCTAssertEqual(
            pipelineForTestA.trackDeliveryEventCallsCount, 1,
            "the flush should have completed against the pipeline registered while it ran"
        )
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
