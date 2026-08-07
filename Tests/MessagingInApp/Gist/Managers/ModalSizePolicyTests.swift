@testable import CioMessagingInApp
import CoreGraphics
import SharedTests
import XCTest

/// Mirrors `ModalSizePolicyTest` on Android so the two SDKs cannot drift apart.
class ModalSizePolicyTests: UnitTest {
    private func armedPolicy() -> ModalSizePolicy {
        let policy = ModalSizePolicy()
        policy.arm()
        return policy
    }

    private func report(_ policy: ModalSizePolicy, _ heights: [CGFloat]) -> [ModalSizeVerdict] {
        heights.map { policy.onHeightReported($0) }
    }

    func test_onHeightReported_whenNotArmed_expectHeightAlwaysApplied() {
        let policy = ModalSizePolicy()

        // Zero heights while the message is still loading must not be judged.
        let verdicts = report(policy, [0, 0, 0, 0, 0, 0])

        for verdict in verdicts {
            XCTAssertEqual(verdict, .apply(height: 0))
        }
    }

    func test_onHeightReported_whenCollapsedAtZero_expectDegenerateOnceSampleCountReached() {
        let policy = armedPolicy()

        let verdicts = report(policy, [0, 0, 0, 0])

        for verdict in verdicts.prefix(ModalSizePolicy.sampleCount - 1) {
            XCTAssertEqual(verdict, .apply(height: 0))
        }
        XCTAssertEqual(verdicts.last, .degenerate)
    }

    func test_onHeightReported_whenCollapsedAtCollapsedMargin_expectDegenerate() {
        let policy = armedPolicy()

        // iOS reported 8.0 in the field: a body margin left over from an otherwise empty document.
        let verdicts = report(policy, [8, 8, 8, 8])

        XCTAssertEqual(verdicts.last, .degenerate)
    }

    func test_onHeightReported_whenStaysCollapsed_expectDegenerateReportedOnlyOnce() {
        let policy = armedPolicy()

        let verdicts = report(policy, [0, 0, 0, 0, 0, 0, 0])

        XCTAssertEqual(verdicts.filter { $0 == .degenerate }.count, 1)
    }

    func test_onHeightReported_whenCollapsedThenResolves_expectNoDegenerate() {
        let policy = armedPolicy()

        // A couple of empty measurements before the content settles is normal.
        let verdicts = report(policy, [0, 0, 380, 380])

        XCTAssertFalse(verdicts.contains(.degenerate))
        XCTAssertEqual(verdicts.last, .apply(height: 380))
    }

    func test_onHeightReported_whenConstantGrowth_expectViewportDependentWithDelta() {
        let policy = armedPolicy()

        // Observed on device: the height climbs by the body padding on every report.
        let verdicts = report(policy, [704, 736, 768, 800])

        XCTAssertEqual(verdicts.last, .viewportDependent(height: 800, delta: 32))
    }

    func test_onHeightReported_whenConstantGrowthContinues_expectViewportDependentReportedOnlyOnce() {
        let policy = armedPolicy()

        let verdicts = report(policy, [704, 736, 768, 800, 832, 864, 896])

        let flagged = verdicts.filter { verdict in
            if case .viewportDependent = verdict { return true }
            return false
        }
        XCTAssertEqual(flagged.count, 1)
    }

    func test_onHeightReported_whenTallConstantHeight_expectAppliedAndNotFlagged() {
        let policy = armedPolicy()

        // A message legitimately taller than the screen reports a constant height; the container
        // clamps it. That must not be mistaken for a runaway.
        let verdicts = report(policy, [1200, 1200, 1200, 1200, 1200])

        for verdict in verdicts {
            XCTAssertEqual(verdict, .apply(height: 1200))
        }
    }

    func test_onHeightReported_whenIrregularGrowthWhileLoading_expectAppliedAndNotFlagged() {
        let policy = armedPolicy()

        // Images and fonts settling produce uneven growth, which is not a runaway.
        let verdicts = report(policy, [200, 300, 380, 382, 382])

        let flagged = verdicts.contains { verdict in
            if case .viewportDependent = verdict { return true }
            return false
        }
        XCTAssertFalse(flagged)
        XCTAssertEqual(verdicts.last, .apply(height: 382))
    }

    func test_onHeightReported_whenNormalStableHeight_expectAppliedVerbatim() {
        let policy = armedPolicy()

        let verdicts = report(policy, [382, 382, 382, 382])

        for verdict in verdicts {
            XCTAssertEqual(verdict, .apply(height: 382))
        }
    }

    func test_onHeightReported_whenShrinkingHeight_expectAppliedAndNotFlagged() {
        let policy = armedPolicy()

        // Going back to a shorter step is a normal multi step transition.
        let verdicts = report(policy, [500, 468, 436, 404])

        XCTAssertEqual(verdicts.last, .apply(height: 404))
        XCTAssertFalse(verdicts.contains(.degenerate))
    }

    func test_arm_whenRearmed_expectEarlierSamplesDiscarded() {
        let policy = armedPolicy()
        _ = report(policy, [0, 0, 0])

        policy.arm()
        let verdict = policy.onHeightReported(0)

        // Only one sample since re-arming, so no verdict can be reached yet.
        XCTAssertEqual(verdict, .apply(height: 0))
    }
}
