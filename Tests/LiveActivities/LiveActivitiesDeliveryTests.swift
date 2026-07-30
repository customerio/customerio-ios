import CioInternalCommon
import CioLiveActivities_Attributes
import Foundation
import Testing

@testable import CioLiveActivities

struct LiveActivitiesDeliveryTests {
    /// One metric the tracker posted to the shared event bus.
    private struct RecordedMetric: Sendable {
        let deliveryId: String
        let event: String
        let deliveryToken: String
    }

    /// Captures the metrics the tracker would post to the shared event bus.
    private final class MetricCapture: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var metrics: [RecordedMetric] = []
        func record(_ deliveryId: String, _ event: String, _ deliveryToken: String) {
            lock.withLock { metrics.append(RecordedMetric(deliveryId: deliveryId, event: event, deliveryToken: deliveryToken)) }
        }
    }

    private struct Harness {
        let cap: MetricCapture
        let store: FakeTokenStore
        let tracker: LiveActivityDeliveryTracker
    }

    private func makeHarness() -> Harness {
        let cap = MetricCapture()
        let store = FakeTokenStore()
        let tracker = LiveActivityDeliveryTracker(
            postMetric: { id, event, token in cap.record(id, event, token) },
            store: store,
            logger: NoopLogger()
        )
        return Harness(cap: cap, store: store, tracker: tracker)
    }

    @Test func delivered_reportsOnce_perDeliveryId() {
        let h = makeHarness()
        h.tracker.reportDelivered(metadata: .init(deliveryId: "d1", deliveryToken: "t1"))
        h.tracker.reportDelivered(metadata: .init(deliveryId: "d1", deliveryToken: "t1")) // re-emit / snapshot replay
        #expect(h.cap.metrics.count == 1)
        #expect(h.cap.metrics[0].deliveryId == "d1")
        #expect(h.cap.metrics[0].event == Metric.delivered.rawValue)
        #expect(h.cap.metrics[0].deliveryToken == "t1")
    }

    @Test func delivered_distinctIds_eachReported() {
        let h = makeHarness()
        h.tracker.reportDelivered(metadata: .init(deliveryId: "d1"))
        h.tracker.reportDelivered(metadata: .init(deliveryId: "d2"))
        #expect(h.cap.metrics.count == 2)
        // Missing delivery token defaults to empty (matches push's optional token handling).
        #expect(h.cap.metrics[0].deliveryToken.isEmpty)
    }

    @Test func delivered_noDeliveryId_isNoOp() {
        let h = makeHarness()
        h.tracker.reportDelivered(metadata: .init(deepLink: "app://x")) // no id ⇒ local/no push
        h.tracker.reportDelivered(metadata: .init(deliveryId: "")) // empty id
        #expect(h.cap.metrics.isEmpty)
    }

    @Test func delivered_dedupPersists_acrossTrackerInstances() {
        // A shared store simulates persistence across launches: a cold-launch snapshot must not
        // re-report `delivered` for an id already reported in a prior process.
        let cap = MetricCapture()
        let store = FakeTokenStore()
        func makeTracker() -> LiveActivityDeliveryTracker {
            LiveActivityDeliveryTracker(postMetric: { id, e, t in cap.record(id, e, t) }, store: store, logger: NoopLogger())
        }
        makeTracker().reportDelivered(metadata: .init(deliveryId: "d1"))
        makeTracker().reportDelivered(metadata: .init(deliveryId: "d1")) // fresh "process", same store
        #expect(cap.metrics.count == 1)
    }

    @Test func delivered_expiredMarker_reReports() {
        // A dedup marker older than the 7-day TTL must not suppress a (practically impossible)
        // re-report: the stale marker is ignored and the delivery is reported again.
        let h = makeHarness()
        h.store.setDeliveredMarker("d1", at: Date(timeIntervalSinceNow: -(7 * 24 * 60 * 60 + 60)))
        h.tracker.reportDelivered(metadata: .init(deliveryId: "d1", deliveryToken: "t1"))
        #expect(h.cap.metrics.count == 1)
        // …and the refreshed marker now dedups again.
        h.tracker.reportDelivered(metadata: .init(deliveryId: "d1", deliveryToken: "t1"))
        #expect(h.cap.metrics.count == 1)
    }

    @Test func opened_reportsEachTap_notDeduped() {
        let h = makeHarness()
        h.tracker.reportOpened(metadata: .init(deliveryId: "d1", deliveryToken: "t1"))
        h.tracker.reportOpened(metadata: .init(deliveryId: "d1", deliveryToken: "t1"))
        #expect(h.cap.metrics.count == 2)
        #expect(h.cap.metrics.allSatisfy { $0.event == Metric.opened.rawValue })
    }

    @Test func opened_noDeliveryId_isNoOp() {
        let h = makeHarness()
        h.tracker.reportOpened(metadata: .init(deepLink: "app://x"))
        #expect(h.cap.metrics.isEmpty)
    }
}
