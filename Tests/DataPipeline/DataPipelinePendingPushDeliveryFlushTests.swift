@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
@testable import SharedTests
import XCTest

/// Verifies app-group pending push delivery metrics are flushed when Data Pipeline starts (main app launch path).
final class DataPipelinePendingPushFlushTests: IntegrationTest {
    private var pendingStoreMock: PendingPushDeliveryStoreMock!
    private var loadAllExpectation: XCTestExpectation!
    private var removeExpectation: XCTestExpectation!
    private let pendingMetric = PendingPushDeliveryMetric(
        deliveryId: "pend-launch-1",
        deviceToken: "device-tok-1",
        event: .delivered,
        timestamp: Date()
    )

    override func setUpDependencies() {
        super.setUpDependencies()
        pendingStoreMock = PendingPushDeliveryStoreMock()
        pendingStoreMock.removeReturnValue = true
        pendingStoreMock.underlyingAppGroupSuiteName = "group.test.app.cio"

        loadAllExpectation = expectation(description: "pending store loadAll during Data Pipeline flush")
        removeExpectation = expectation(description: "pending store remove(id:) after each flushed metric")
        let metric = pendingMetric
        pendingStoreMock.loadAllClosure = { [weak self] in
            self?.loadAllExpectation.fulfill()
            return [metric]
        }
        pendingStoreMock.removeClosure = { [weak self] id in
            if id == metric.id {
                self?.removeExpectation.fulfill()
            }
            return true
        }

        diGraphShared.override(value: pendingStoreMock, forType: PendingPushDeliveryStore.self)
        mockCollection.add(mock: pendingStoreMock)
    }

    func test_initialize_flushesPendingMetrics_loadAllThenRemoveEachIdAfterEnqueue() {
        wait(for: [loadAllExpectation, removeExpectation], timeout: 2.0)
        XCTAssertEqual(pendingStoreMock.loadAllCallsCount, 1, "startup should read pending list from app group store")
        XCTAssertEqual(pendingStoreMock.removeCallsCount, 1, "each flushed row should be removed by id")
        XCTAssertEqual(pendingStoreMock.removeReceivedArguments, pendingMetric.id)
    }
}

final class DataPipelineEmptyPushFlushTests: IntegrationTest {
    private var pendingStoreMock: PendingPushDeliveryStoreMock!
    private var loadAllExpectation: XCTestExpectation!

    override func setUpDependencies() {
        super.setUpDependencies()
        pendingStoreMock = PendingPushDeliveryStoreMock()
        pendingStoreMock.underlyingAppGroupSuiteName = "group.test.app.cio"

        loadAllExpectation = expectation(description: "pending store loadAll during Data Pipeline flush (empty file)")
        pendingStoreMock.loadAllClosure = { [weak self] in
            self?.loadAllExpectation.fulfill()
            return []
        }

        diGraphShared.override(value: pendingStoreMock, forType: PendingPushDeliveryStore.self)
        mockCollection.add(mock: pendingStoreMock)
    }

    func test_initialize_whenNoPendingMetrics_expectLoadAllOnlyNoRemoves() {
        wait(for: [loadAllExpectation], timeout: 2.0)
        XCTAssertEqual(pendingStoreMock.loadAllCallsCount, 1)
        XCTAssertEqual(pendingStoreMock.removeCallsCount, 0)
    }
}
