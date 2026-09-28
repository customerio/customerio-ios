@testable import CioLocationGeofence
import Foundation
import Testing

/// The `condition_mirror` comparison, tested as a pure function because `CLMonitor` cannot be
/// instantiated in a unit test without aborting the test process.
///
/// Ownership is deliberately not an input: a later sync mutates it while this sync's OS work is
/// still queued, so an ownership-based comparison would report staged changes as drift.
@Suite("ConditionMirrorDrift")
struct ConditionMirrorDriftTests {
    @Test
    func givenTheOsHoldsWhatTheSyncAskedFor_expectNoDrift() {
        let drift = ConditionMirror.drift(
            desired: ["a", "b", "cio_movement_trigger"],
            atOs: ["a", "b", "cio_movement_trigger"]
        )

        #expect(drift.missing.isEmpty)
        #expect(drift.extra.isEmpty)
        #expect(drift.atOsCount == 3)
    }

    @Test
    func givenTheOsDoesNotListOne_expectItNamedInMissing() {
        let drift = ConditionMirror.drift(desired: ["a", "b"], atOs: ["a"])

        #expect(drift.missing == ["b"])
        #expect(drift.extra.isEmpty)
    }

    /// A later sync's add draining before this record runs shows as `extra`, and must not
    /// leak into `missing`.
    @Test
    func givenTheOsListsSomethingThisSyncDidNotWant_expectExtraOnly() {
        let drift = ConditionMirror.drift(desired: ["a", "b"], atOs: ["a", "b", "c"])

        #expect(drift.missing.isEmpty)
        #expect(drift.extra == ["c"])
    }

    /// Sorted so a capture diffs cleanly across passes.
    @Test
    func givenDriftBothWays_expectBothNamedAndSorted() {
        let drift = ConditionMirror.drift(
            desired: ["b", "a", "d"], atOs: ["a", "z", "m"]
        )

        #expect(drift.missing == ["b", "d"])
        #expect(drift.extra == ["m", "z"])
    }

    /// Tokens are literals rather than raw values so a case rename cannot change what captures
    /// grep for.
    @Test
    func occasion_expectTheTokensStayWhatCapturesGrepFor() {
        #expect(ConditionMirrorOccasion.sync.token == "sync")
        #expect(ConditionMirrorOccasion.poll.token == "poll")
    }

    /// A zero count keeps the `refused` field absent instead of printing `refused=0` on every
    /// healthy sync.
    @Test
    func target_givenEverythingAccepted_expectNothingCountedRefused() {
        let target = ConditionMirror.target(desired: ["a", "b"], owned: ["a", "b"])

        #expect(target.accepted == ["a", "b"])
        #expect(target.refused == 0)
    }

    /// `startMonitoring` returns before taking ownership when permission is blocked or the
    /// coordinates are unusable, so that identifier was never asked of the OS and must not read
    /// as drift. The raw desired set is asserted too, to show the false reading scoping prevents.
    @Test
    func accepted_givenOneRegistrationRefused_expectItIsNotReportedMissing() {
        let requested: Set = ["kept", "refused"]
        // Ownership is the record of acceptance, and the refused identifier never enters it.
        let owned: Set = ["kept"]
        let atOs: Set = ["kept"]

        let target = ConditionMirror.target(desired: requested, owned: owned)

        #expect(target.accepted == ["kept"])
        #expect(ConditionMirror.drift(desired: target.accepted, atOs: atOs).missing.isEmpty)
        #expect(ConditionMirror.drift(desired: requested, atOs: atOs).missing == ["refused"])
        // Counted, not just excluded: no other record states how many were refused.
        #expect(target.refused == 1)
    }
}
