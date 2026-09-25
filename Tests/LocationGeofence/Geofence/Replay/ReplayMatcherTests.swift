@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

/// A green replay is worthless until it has been shown to go red for the right reason. Each of
/// these breaks one thing and asserts the matcher notices *that* thing.
///
/// These run against a small synthetic scenario rather than a recorded drive, so they keep working
/// when the drives are not on the machine, and so a failure names one rule rather than one drive.
@Suite("Replay matcher")
struct ReplayMatcherTests {
    private func scenario(_ lines: String) throws -> Scenario {
        try ScenarioLoader.parse("""
        {"k":"scenario","v":1,"name":"synthetic","platform":"ios","t0":"t"}
        \(lines)
        """)
    }

    private let drove: [[String: String]] = [
        ["ev": "transition.accepted", "id": "A", "t": "enter"],
        ["ev": "os.callback.dropped", "id": "A", "why": "no_state_change"]
    ]

    @Test
    func compare_givenIdenticalRun_expectNoMismatch() throws {
        let expected = try scenario("""
        {"k":"then","at":1.0,"ev":"transition.accepted","id":"A","t":"enter"}
        {"k":"then","at":1.1,"ev":"os.callback.dropped","id":"A","why":"no_state_change"}
        """).then
        #expect(ReplayMatcher.compare(expected: expected, actual: drove).isEmpty)
    }

    @Test
    func compare_givenDecisionNoLongerEmitted_expectMissing() throws {
        let expected = try scenario("""
        {"k":"then","at":1.0,"ev":"transition.accepted","id":"A","t":"enter"}
        {"k":"then","at":1.1,"ev":"os.callback.dropped","id":"A","why":"no_state_change"}
        """).then
        // The dedup stops firing — the exact regression `os.callback.dropped` was mapped to catch.
        let actual = Array(drove.prefix(1))
        let found = ReplayMatcher.compare(expected: expected, actual: actual)
        #expect(found.contains { "\($0)".contains("expectation #1 never arrived") })
    }

    @Test
    func compare_givenChangedReason_expectFieldDiff() throws {
        let expected = try scenario("""
        {"k":"then","at":1.1,"ev":"os.callback.dropped","id":"A","why":"no_state_change"}
        """).then
        let actual = [["ev": "os.callback.dropped", "id": "A", "why": "cooldown"]]
        let found = ReplayMatcher.compare(expected: expected, actual: actual)
        #expect(found.contains { "\($0)".contains("why expected no_state_change, got cooldown") })
    }

    /// The case ordered-subsequence matching alone would miss: everything the drive recorded is
    /// still there, in order, plus a duplicate. Without the per-`ev` count rule this passes.
    @Test
    func compare_givenDuplicateEmission_expectCountDiff() throws {
        let expected = try scenario("""
        {"k":"then","at":1.0,"ev":"transition.accepted","id":"A","t":"enter"}
        """).then
        let actual = [drove[0], drove[0]]
        let found = ReplayMatcher.compare(expected: expected, actual: actual)
        #expect(found.contains { "\($0)".contains("transition.accepted: drive emitted 1, replay emitted 2") })
    }

    /// Emissions the scenario does not mention must not fail it, or every new diagnostic line
    /// turns every recorded drive red.
    @Test
    func compare_givenUnrelatedNewLogLine_expectNoMismatch() throws {
        let expected = try scenario("""
        {"k":"then","at":1.0,"ev":"transition.accepted","id":"A","t":"enter"}
        """).then
        let actual = [["ev": "rank.evaluated", "n": "14"], drove[0], ["ev": "sync.completed"]]
        #expect(ReplayMatcher.compare(expected: expected, actual: actual).isEmpty)
    }

    // MARK: - Ordering within a stimulus window

    /// Two decisions from one stimulus may arrive in either order.
    ///
    /// This is the rule the whole matcher exists for, and until now nothing tested it: every other
    /// case leaves `stimuli` empty, which collapses grouping to one expectation per group and makes
    /// matching strictly sequential. The rule is load-bearing because `GeofenceMonitorBinder` fires
    /// the tracker and the coordinator as concurrent `Task`s, so which of the two logs first is not
    /// something the SDK promises — only that both happen before the next stimulus.
    @Test
    func compare_givenTwoDecisionsFromOneStimulusSwapped_expectMatch() throws {
        let expected = try scenario("""
        {"k":"then","at":1.0,"ev":"transition.accepted","id":"A","t":"enter"}
        {"k":"then","at":1.1,"ev":"transition.accepted","id":"B","t":"enter"}
        """).then
        // One stimulus at t=0; both decisions belong to its window.
        let swapped: [[String: String]] = [
            ["ev": "transition.accepted", "id": "B", "t": "enter"],
            ["ev": "transition.accepted", "id": "A", "t": "enter"]
        ]
        #expect(
            ReplayMatcher.compare(expected: expected, actual: swapped, stimuli: [0]).isEmpty,
            "decisions from one stimulus were graded in order, so a concurrent pair reads as a regression"
        )
    }

    /// The same swap across a stimulus boundary is a real mismatch.
    ///
    /// The counterpart to the case above: unordered *within* a window must not mean unordered
    /// everywhere, or the matcher would stop noticing that a decision moved to a different cause.
    @Test
    func compare_givenDecisionsSwappedAcrossStimuli_expectMismatch() throws {
        let expected = try scenario("""
        {"k":"then","at":1.0,"ev":"transition.accepted","id":"A","t":"enter"}
        {"k":"then","at":9.0,"ev":"transition.accepted","id":"B","t":"enter"}
        """).then
        let swapped: [[String: String]] = [
            ["ev": "transition.accepted", "id": "B", "t": "enter"],
            ["ev": "transition.accepted", "id": "A", "t": "enter"]
        ]
        #expect(
            !ReplayMatcher.compare(expected: expected, actual: swapped, stimuli: [0, 5]).isEmpty,
            "a decision attributed to the wrong stimulus was graded as a match"
        )
    }
}
