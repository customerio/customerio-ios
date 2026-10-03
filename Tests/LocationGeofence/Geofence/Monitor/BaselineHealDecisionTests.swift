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
        // 980 and 1025 are within the 30m accuracy of the 1000m edge.
        #expect(decide(distanceFromCenter: 980) == nil)
        #expect(decide(distanceFromCenter: 1025, lastState: .enter) == nil)
    }

    @Test
    func synthesizedTransition_givenOverOptimisticAccuracy_expectFloorApplied() {
        // Claimed 5m accuracy is floored to 20m: 15m inside is ambiguous, 25m inside is not.
        #expect(decide(distanceFromCenter: 985, horizontalAccuracy: 5) == nil)
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
