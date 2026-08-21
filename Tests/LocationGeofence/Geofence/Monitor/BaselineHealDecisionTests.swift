@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

@Suite("BaselineHealDecision")
struct BaselineHealDecisionTests {
    private func decide(
        distanceFromCenter: Double,
        radius: Double = 1000,
        horizontalAccuracy: Double = 30,
        fixAge: TimeInterval = 5,
        lastState: GeofenceTransition? = .exit
    ) -> GeofenceTransition? {
        BaselineHealDecision.synthesizedTransition(
            distanceFromCenter: distanceFromCenter,
            radius: radius,
            horizontalAccuracy: horizontalAccuracy,
            fixAge: fixAge,
            lastState: lastState
        )
    }

    @Test
    func synthesizedTransition_givenConfidentlyInsideWithExitBaseline_expectEnter() {
        #expect(decide(distanceFromCenter: 350) == .enter)
    }

    @Test
    func synthesizedTransition_givenConfidentlyOutsideWithEnterBaseline_expectExit() {
        #expect(decide(distanceFromCenter: 1500, lastState: .enter) == .exit)
    }

    @Test
    func synthesizedTransition_givenBaselineAgreesWithFix_expectNil() {
        #expect(decide(distanceFromCenter: 350, lastState: .enter) == nil)
        #expect(decide(distanceFromCenter: 1500, lastState: .exit) == nil)
    }

    @Test
    func synthesizedTransition_givenFixInsideAmbiguityBand_expectNil() {
        // 20m inside the edge with 30m accuracy: could be either side.
        #expect(decide(distanceFromCenter: 980) == nil)
        // 25m outside the edge with 30m accuracy, enter baseline: same band.
        #expect(decide(distanceFromCenter: 1025, lastState: .enter) == nil)
    }

    @Test
    func synthesizedTransition_givenOverOptimisticAccuracy_expectFloorApplied() {
        // 15m inside the edge; accuracy claims 5m but the 20m floor rejects the verdict.
        #expect(decide(distanceFromCenter: 985, horizontalAccuracy: 5) == nil)
        // 25m inside the edge clears the floor with the same claimed accuracy.
        #expect(decide(distanceFromCenter: 975, horizontalAccuracy: 5) == .enter)
    }

    @Test
    func synthesizedTransition_givenStaleFix_expectNil() {
        #expect(decide(distanceFromCenter: 350, fixAge: 31) == nil)
    }

    @Test
    func synthesizedTransition_givenFutureTimestampedFix_expectNil() {
        #expect(decide(distanceFromCenter: 350, fixAge: -2) == nil)
    }

    @Test
    func synthesizedTransition_givenInvalidAccuracy_expectNil() {
        #expect(decide(distanceFromCenter: 350, horizontalAccuracy: 0) == nil)
        #expect(decide(distanceFromCenter: 350, horizontalAccuracy: -1) == nil)
    }

    @Test
    func synthesizedTransition_givenNoBaseline_expectNil() {
        #expect(decide(distanceFromCenter: 350, lastState: nil) == nil)
    }
}
