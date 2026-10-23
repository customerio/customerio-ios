@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import SharedTests
import Testing

/// One native EXIT callback, delivered twice while its first routing is still pending, on either
/// side of a wall-clock step and its rollback. The first delivery, noted while the clock read 1000 s
/// ahead, cannot be ordered against the stay by date, so by processing order it ends it; the copy,
/// noted after the clock was set back, is dated 10 s before the stay began. The copy must not
/// weaken what the first showed. Driven at the coordinator with the binder's exact
/// `noteExitCallback` call; internal chronology, not physical callback acceptance. Storage,
/// tracker, outbox and the fresh circle fix are real (`GeofenceDwellFollowupTests.Rig`).
@Suite("GeofenceDwellPendingExitStep", .serialized)
@MainActor
struct GeofenceDwellPendingExitStepTests {
    /// The rig's circle with a 300 s dwell.
    private static let circle = Geofence(
        id: "circle", latitude: 1, longitude: 2, radius: 150, name: "circle",
        transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1),
        dwellThresholdSeconds: 300
    )

    /// ENTER at 0. At 200 s the wall clock jumps 1000 s ahead and the EXIT (dated 10 s before the
    /// entry) is noted; at 300 s the clock is set back and its copy is noted. A fresh inside fix at
    /// 300 s must neither queue nor reserve the stay's DWELL. Once both routings are done the
    /// recorded EXIT, read on the restored clock, predates the stay, so it qualifies: deferred.
    @Test
    func copyNotedAfterTheClockIsSetBack_expectTheEarlierDeliveryStillHolds() async throws {
        let rig = await Self.rig()
        let enteredAt = rig.clock.wall
        let stay = try await Self.enter(rig)
        let exitDate = enteredAt.addingTimeInterval(-10)
        rig.advance(200)
        rig.stepWall(1000)
        rig.dwell.noteExitCallback(geofenceId: Self.circle.id, occurredAt: exitDate)
        rig.advance(100)
        rig.stepWall(-1000)
        rig.dwell.noteExitCallback(geofenceId: Self.circle.id, occurredAt: exitDate)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        #expect(await rig.dwellRows().isEmpty)
        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id)?.dwellReservation == nil)
        for _ in 0 ..< 2 {
            await rig.dwell.handleBoundary(geofence: Self.circle, transition: .exit, occurredAt: exitDate, expectedUserId: "user-1")
            rig.dwell.exitCallbackRouted(geofenceId: Self.circle.id, occurredAt: exitDate)
        }
        #expect(rig.dwell.pendingExitCallbacks.isEmpty)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)
        #expect(await rig.dwellRows().map(\.visitId) == [stay.visitId])
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// Control: the same EXIT, 10 s before the stay, noted on one clock: a stale callback holds
    /// nothing back, and the stay qualifies at 300 s while it is still pending.
    @Test
    func staleCallbackOnOneClock_expectTheStayToQualify() async throws {
        let rig = await Self.rig()
        let enteredAt = rig.clock.wall
        let stay = try await Self.enter(rig)
        rig.advance(200)
        rig.dwell.noteExitCallback(geofenceId: Self.circle.id, occurredAt: enteredAt.addingTimeInterval(-10))
        rig.advance(100)
        rig.dwell.noteExitCallback(geofenceId: Self.circle.id, occurredAt: enteredAt.addingTimeInterval(-10))
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        #expect(await rig.dwellRows().map(\.visitId) == [stay.visitId])
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    // MARK: - Helpers

    /// Every fix is fresh and inside; a CDP key, so a flush keeps rows in the outbox.
    private static func rig() async -> GeofenceDwellFollowupTests.Rig {
        let rig = await GeofenceDwellFollowupTests.Rig.make(insideFixAlways: true)
        rig.contextStore.setCdpApiKey("test-key")
        await rig.cacheCircle(threshold: 300)
        return rig
    }

    private static func enter(_ rig: GeofenceDwellFollowupTests.Rig) async throws -> GeofenceDwellVisit {
        await rig.dwell.handleBoundary(geofence: circle, transition: .enter, occurredAt: rig.clock.wall)
        let visit = try #require(await rig.storage.getDwellVisit(geofenceId: circle.id))
        rig.dwell.cancelEvidence(for: circle.id)
        return visit
    }
}
