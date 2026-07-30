import CioLiveActivities_Attributes
import Foundation
import Testing

@testable import CioLiveActivities

struct LiveActivityPendingOpensTests {
    @Test func drain_returnsInArrivalOrder() {
        let pending = LiveActivityPendingOpens()
        pending.append(CIOLiveActivityMetadata(deliveryId: "d-1"))
        pending.append(CIOLiveActivityMetadata(deliveryId: "d-2"))

        #expect(pending.drain().map(\.deliveryId) == ["d-1", "d-2"])
    }

    @Test func drain_emptiesBuffer_soAnOpenIsNeverReportedTwice() {
        let pending = LiveActivityPendingOpens()
        pending.append(CIOLiveActivityMetadata(deliveryId: "d-1"))

        #expect(pending.drain().count == 1)
        #expect(pending.drain().isEmpty)
    }

    @Test func drain_whenNothingBuffered_isEmpty() {
        #expect(LiveActivityPendingOpens().drain().isEmpty)
    }

    @Test func append_pastLimit_dropsOldest() {
        let pending = LiveActivityPendingOpens(limit: 2)
        pending.append(CIOLiveActivityMetadata(deliveryId: "d-1"))
        pending.append(CIOLiveActivityMetadata(deliveryId: "d-2"))
        pending.append(CIOLiveActivityMetadata(deliveryId: "d-3"))

        #expect(pending.drain().map(\.deliveryId) == ["d-2", "d-3"])
    }

    @Test func append_duplicateDeliveryIds_areKept() {
        let pending = LiveActivityPendingOpens()
        pending.append(CIOLiveActivityMetadata(deliveryId: "d-1"))
        pending.append(CIOLiveActivityMetadata(deliveryId: "d-1"))

        #expect(pending.drain().count == 2)
    }
}
