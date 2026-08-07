@testable import CioMessagingInApp
import CoreGraphics
import Foundation
import SharedTests
import XCTest

/// Mirrors `ModalSizePolicyTest` on Android so the two SDKs cannot drift apart.
class ModalSizePolicyTests: UnitTest {
    /// Lets tests advance time without sleeping.
    private class FakeClock {
        var now: TimeInterval = 0
    }

    private func makePolicy(
        _ clock: FakeClock,
        sampleCount: Int = ModalSizePolicy.sampleCount
    ) -> ModalSizePolicy {
        ModalSizePolicy(sampleCount: sampleCount, now: { clock.now })
    }

    private func armedPolicy(_ clock: FakeClock) -> ModalSizePolicy {
        let policy = makePolicy(clock)
        policy.arm()
        return policy
    }

    /// Reports each height, advancing the clock by `step` between reports.
    private func report(
        _ policy: ModalSizePolicy,
        _ clock: FakeClock,
        _ heights: [CGFloat],
        step: TimeInterval = 1.0
    ) -> [ModalSizeVerdict] {
        heights.enumerated().map { index, height in
            if index > 0 { clock.now += step }
            return policy.onHeightReported(height)
        }
    }

    func test_onHeightReported_whenNotArmed_expectHeightAlwaysApplied() {
        let clock = FakeClock()
        let policy = makePolicy(clock)

        let verdicts = report(policy, clock, [0, 0, 0, 0, 0, 0])

        for verdict in verdicts {
            XCTAssertEqual(verdict, .apply)
        }
    }

    func test_onHeightReported_whenCollapsedAtZeroOverTime_expectDegenerate() {
        let clock = FakeClock()
        let policy = armedPolicy(clock)

        let verdicts = report(policy, clock, [0, 0, 0, 0])

        for verdict in verdicts.prefix(ModalSizePolicy.sampleCount - 1) {
            XCTAssertEqual(verdict, .apply)
        }
        XCTAssertEqual(verdicts.last, .degenerate)
    }

    func test_onHeightReported_whenCollapsedAtCollapsedMargin_expectDegenerate() {
        let clock = FakeClock()
        let policy = armedPolicy(clock)

        // iOS reported 8.0 in the field: a body margin left over from an otherwise empty document.
        let verdicts = report(policy, clock, [8, 8, 8, 8])

        XCTAssertEqual(verdicts.last, .degenerate)
    }

    func test_onHeightReported_whenCollapsedBurstWithinMilliseconds_expectNoDegenerate() {
        let clock = FakeClock()
        let policy = armedPolicy(clock)

        // sizeChanged arrives in bursts (it also fires on every window resize), so a healthy message
        // still being laid out can emit several collapsed reports back to back.
        let verdicts = report(policy, clock, [0, 0, 0, 0, 0, 0], step: 0.005)

        for verdict in verdicts {
            XCTAssertEqual(verdict, .apply)
        }
    }

    func test_onHeightReported_whenDegenerateNotHandled_expectVerdictRepeated() {
        let clock = FakeClock()
        let policy = armedPolicy(clock)

        // The caller may be unable to act yet; the guard must not disable itself.
        let verdicts = report(policy, clock, [0, 0, 0, 0, 0, 0])

        XCTAssertEqual(verdicts.filter { $0 == .degenerate }.count, 3)
    }

    func test_onHeightReported_whenDegenerateHandled_expectNotReportedAgain() {
        let clock = FakeClock()
        let policy = armedPolicy(clock)
        _ = report(policy, clock, [0, 0, 0, 0])

        policy.onDegenerateHandled()
        let verdicts = report(policy, clock, [0, 0, 0])

        XCTAssertFalse(verdicts.contains(.degenerate))
    }

    func test_onHeightReported_whenCollapsedThenResolves_expectNoDegenerate() {
        let clock = FakeClock()
        let policy = armedPolicy(clock)

        let verdicts = report(policy, clock, [0, 0, 380, 380])

        XCTAssertFalse(verdicts.contains(.degenerate))
        XCTAssertEqual(verdicts.last, .apply)
    }

    func test_onHeightReported_whenConstantGrowth_expectViewportDependentWithDelta() {
        let clock = FakeClock()
        let policy = armedPolicy(clock)

        // Observed on device: the height climbs by the body padding on every report.
        let verdicts = report(policy, clock, [704, 736, 768, 800])

        XCTAssertEqual(verdicts.last, .viewportDependent(delta: 32))
    }

    func test_onHeightReported_whenViewportDependentHandled_expectNotReportedAgain() {
        let clock = FakeClock()
        let policy = armedPolicy(clock)
        _ = report(policy, clock, [704, 736, 768, 800])

        policy.onViewportDependentHandled()
        let verdicts = report(policy, clock, [832, 864, 896])

        let flagged = verdicts.contains { verdict in
            if case .viewportDependent = verdict { return true }
            return false
        }
        XCTAssertFalse(flagged)
    }

    func test_onHeightReported_whenTallConstantHeight_expectAppliedAndNotFlagged() {
        let clock = FakeClock()
        let policy = armedPolicy(clock)

        // A message legitimately taller than the screen reports a constant height. That must not be
        // mistaken for a runaway.
        let verdicts = report(policy, clock, [1200, 1200, 1200, 1200, 1200])

        for verdict in verdicts {
            XCTAssertEqual(verdict, .apply)
        }
    }

    func test_onHeightReported_whenIrregularGrowthWhileLoading_expectAppliedAndNotFlagged() {
        let clock = FakeClock()
        let policy = armedPolicy(clock)

        // Images and fonts settling produce uneven growth, which is not a runaway.
        let verdicts = report(policy, clock, [200, 300, 380, 382, 382])

        for verdict in verdicts {
            XCTAssertEqual(verdict, .apply)
        }
    }

    func test_onHeightReported_whenNormalStableHeight_expectAppliedVerbatim() {
        let clock = FakeClock()
        let policy = armedPolicy(clock)

        let verdicts = report(policy, clock, [382, 382, 382, 382])

        for verdict in verdicts {
            XCTAssertEqual(verdict, .apply)
        }
    }

    func test_onHeightReported_whenShrinkingHeight_expectAppliedAndNotFlagged() {
        let clock = FakeClock()
        let policy = armedPolicy(clock)

        // Going back to a shorter step is a normal multi step transition.
        let verdicts = report(policy, clock, [500, 468, 436, 404])

        for verdict in verdicts {
            XCTAssertEqual(verdict, .apply)
        }
    }

    func test_arm_whenCalledRepeatedly_expectProgressPreserved() {
        let clock = FakeClock()
        let policy = armedPolicy(clock)

        // Callers arm on every display state emission. Re-arming must not discard samples, or the
        // guard could be reset forever and never reach a verdict.
        var verdicts: [ModalSizeVerdict] = []
        for (index, height) in [CGFloat(0), 0, 0, 0].enumerated() {
            if index > 0 { clock.now += 1.0 }
            policy.arm()
            verdicts.append(policy.onHeightReported(height))
        }

        XCTAssertEqual(verdicts.last, .degenerate)
    }

    func test_arm_whenCalledAfterHandling_expectLatchNotSilentlyReset() {
        let clock = FakeClock()
        let policy = armedPolicy(clock)
        _ = report(policy, clock, [0, 0, 0, 0])
        policy.onDegenerateHandled()

        policy.arm()
        let verdicts = report(policy, clock, [0, 0, 0])

        // Already handled, so it stays handled: no duplicate failures for the same message.
        XCTAssertFalse(verdicts.contains(.degenerate))
    }

    func test_onHeightReported_whenSampleCountOfOne_expectNoCrash() {
        let clock = FakeClock()
        let policy = makePolicy(clock, sampleCount: 1)
        policy.arm()

        // Computing a growth delta needs two samples; a single sample must not index out of bounds.
        let verdicts = report(policy, clock, [500, 600])

        XCTAssertEqual(verdicts.count, 2)
    }
}
