@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

/// Pins the contradiction gate's decision semantics. The gate reuses
/// `BaselineHealDecision.synthesizedTransition` with `lastState` set to the INCOMING OS
/// transition: a non-nil result means a fresh gated fix unambiguously says the opposite of what
/// the OS delivered, so the event is refused before the dedup baseline advances. These tests
/// document that reuse from the gate's perspective — refusal must trigger only on confident
/// geometric contradiction, and every undecidable input must fail open (deliver).
@Suite("ContradictionGateDecision")
struct ContradictionGateDecisionTests {
    /// Mirrors the gate's call in `CLMonitorGeofenceMonitor.process(event:)`.
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

    // MARK: - Confident contradictions refuse (the two field-observed damage classes)

    @Test
    func gate_givenEnterWithFixFarOutside_expectRefusal() {
        // The Saleem/Baba-Sweets class: stale daemon belief replays an enter kilometres away.
        #expect(refuses(incoming: .enter, distanceFromCenter: 7787))
    }

    @Test
    func gate_givenExitWithFixDeepInside_expectRefusal() {
        // The login-inside-fences class: default-unsatisfied belief replays an exit at the center.
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
        // Legitimate corrective (rearm/wedged-crossing recovery): fix agrees with the event.
        #expect(!refuses(incoming: .enter, distanceFromCenter: 100))
    }

    @Test
    func gate_givenExitWithFixOutside_expectDelivery() {
        #expect(!refuses(incoming: .exit, distanceFromCenter: 1200))
    }

    @Test
    func gate_givenFixWithinMarginBand_expectDelivery() {
        // A boundary crossing sits within accuracy of the edge — never refused.
        #expect(!refuses(incoming: .enter, distanceFromCenter: 515))
        #expect(!refuses(incoming: .exit, distanceFromCenter: 485))
    }

    @Test
    func gate_givenAccuracyWiderThanDiscrepancy_expectDelivery() {
        // 80 m outside the edge but a 100 m-accuracy fix cannot contradict confidently.
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
        // A catch-up buffered in `pendingEvents` across the re-add predates it — provably not this
        // add's replay, and must never be judged against the geometry this add imposed.
        let start = Date()
        let readd = makeReadd(start: start, added: start.addingTimeInterval(0.05))
        #expect(!readd.replayWindowCovers(start.addingTimeInterval(-0.001)))
        #expect(!readd.replayWindowCovers(start.addingTimeInterval(-3600)))
    }

    @available(iOS 17.0, *)
    @Test
    func replayWindow_givenEventDatedInsideRemoveAddGap_expectCovered() {
        // A replay can be stamped before `add` returns, so the window opens at the remove, not at
        // the add's return — a bare non-negative check against `added` would leak these.
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
        // A burst with no fix obtainable must pay at most one request timeout, not one per event —
        // the events loop is serial, so repeated requests would stall it for their sum.
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
