@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

/// The gate is `synthesizedTransition` with `lastState` set to the incoming OS transition; non-nil
/// means refuse.
@Suite("ContradictionGateDecision")
struct ContradictionGateDecisionTests {
    /// Mirrors the gate's call in `CLMonitorGeofenceMonitor.isEventContradictedByFreshFix`.
    private func refuses(
        incoming: GeofenceTransition,
        distanceFromCenter: Double,
        radius: Double = 500,
        horizontalAccuracy: Double = 10,
        fixAge: TimeInterval = 2
    ) -> Bool {
        BaselineHealDecision.synthesizedTransition(
            distanceFromCenter: distanceFromCenter,
            radius: radius,
            horizontalAccuracy: horizontalAccuracy,
            fixAge: fixAge,
            lastState: incoming
        ) != nil
    }

    // MARK: - Confident contradictions refuse

    @Test
    func gate_givenEnterWithFixFarOutside_expectRefusal() {
        #expect(refuses(incoming: .enter, distanceFromCenter: 7787))
    }

    @Test
    func gate_givenExitWithFixDeepInside_expectRefusal() {
        #expect(refuses(incoming: .exit, distanceFromCenter: 0))
    }

    @Test
    func gate_givenEnterJustBeyondMargin_expectRefusal() {
        // Edge distance 31 m outside with margin max(10, 20) = 20 → confident contradiction.
        #expect(refuses(incoming: .enter, distanceFromCenter: 531))
    }

    // MARK: - Agreement and ambiguity deliver

    @Test
    func gate_givenEnterWithFixInside_expectDelivery() {
        #expect(!refuses(incoming: .enter, distanceFromCenter: 100))
    }

    @Test
    func gate_givenExitWithFixOutside_expectDelivery() {
        #expect(!refuses(incoming: .exit, distanceFromCenter: 1200))
    }

    @Test
    func gate_givenFixWithinMarginBand_expectDelivery() {
        #expect(!refuses(incoming: .enter, distanceFromCenter: 515))
        #expect(!refuses(incoming: .exit, distanceFromCenter: 485))
    }

    @Test
    func gate_givenAccuracyWiderThanDiscrepancy_expectDelivery() {
        #expect(!refuses(incoming: .enter, distanceFromCenter: 580, horizontalAccuracy: 100))
    }

    // MARK: - Untrustworthy fixes fail open

    @Test
    func gate_givenStaleFix_expectDelivery() {
        #expect(!refuses(incoming: .enter, distanceFromCenter: 7787, fixAge: GeofenceConstants.movementFixMaxAge + 1))
    }

    @Test
    func gate_givenFutureTimestampedFix_expectDelivery() {
        #expect(!refuses(incoming: .enter, distanceFromCenter: 7787, fixAge: -1))
    }

    @Test
    func gate_givenInvalidAccuracy_expectDelivery() {
        #expect(!refuses(incoming: .enter, distanceFromCenter: 7787, horizontalAccuracy: -1))
        #expect(!refuses(incoming: .enter, distanceFromCenter: 7787, horizontalAccuracy: 0))
    }

    // MARK: - Replay window bounds (which events the gate vets at all)

    @available(iOS 17.0, *)
    private func makeReadd(start: Date, added: Date) -> CLMonitorGeofenceMonitor.ConditionReadd {
        CLMonitorGeofenceMonitor.ConditionReadd(
            start: start,
            added: added,
            center: LocationData(latitude: 0, longitude: 0),
            radius: 500
        )
    }

    @available(iOS 17.0, *)
    @Test
    func replayWindow_givenEventDatedBeforeReaddStart_expectNotCovered() {
        let start = Date()
        let readd = makeReadd(start: start, added: start.addingTimeInterval(0.05))
        #expect(!readd.replayWindowCovers(start.addingTimeInterval(-0.001)))
        #expect(!readd.replayWindowCovers(start.addingTimeInterval(-3600)))
    }

    @available(iOS 17.0, *)
    @Test
    func replayWindow_givenEventDatedInsideRemoveAddGap_expectCovered() {
        // Replays can be stamped before `add` returns, so the window opens at the remove, not at
        // `added`.
        let start = Date()
        let readd = makeReadd(start: start, added: start.addingTimeInterval(0.05))
        #expect(readd.replayWindowCovers(start))
        #expect(readd.replayWindowCovers(start.addingTimeInterval(0.02)))
    }

    @available(iOS 17.0, *)
    @Test
    func replayWindow_givenEventWithinWindowAfterAdd_expectCovered() {
        let start = Date()
        let added = start.addingTimeInterval(0.05)
        let readd = makeReadd(start: start, added: added)
        #expect(readd.replayWindowCovers(added.addingTimeInterval(3.3)))
        #expect(readd.replayWindowCovers(added.addingTimeInterval(GeofenceConstants.contradictionGateReplayWindow)))
    }

    @available(iOS 17.0, *)
    @Test
    func replayWindow_givenEventBeyondWindow_expectNotCovered() {
        let start = Date()
        let added = start.addingTimeInterval(0.05)
        let readd = makeReadd(start: start, added: added)
        #expect(!readd.replayWindowCovers(added.addingTimeInterval(GeofenceConstants.contradictionGateReplayWindow + 0.1)))
    }

    // MARK: - Gate-fix request cooldown (one attempt per burst)

    @available(iOS 17.0, *)
    @Test
    func gateFixRequest_givenRecentFailedAttempt_expectBlocked() {
        let failedAt = Date()
        #expect(CLMonitorGeofenceMonitor.gateFixRequestBlocked(failedAt: failedAt, now: failedAt.addingTimeInterval(1)))
        #expect(CLMonitorGeofenceMonitor.gateFixRequestBlocked(
            failedAt: failedAt,
            now: failedAt.addingTimeInterval(GeofenceConstants.movementFixMaxAge - 1)
        ))
    }

    @available(iOS 17.0, *)
    @Test
    func gateFixRequest_givenNoOrExpiredFailure_expectAllowed() {
        let failedAt = Date()
        #expect(!CLMonitorGeofenceMonitor.gateFixRequestBlocked(failedAt: nil, now: failedAt))
        #expect(!CLMonitorGeofenceMonitor.gateFixRequestBlocked(
            failedAt: failedAt,
            now: failedAt.addingTimeInterval(GeofenceConstants.movementFixMaxAge)
        ))
    }
}
