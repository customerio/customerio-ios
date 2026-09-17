@testable import CioLocationGeofence
import Foundation
import Testing

/// The `condition_mirror` comparison, tested as a pure function because `CLMonitor` cannot be
/// instantiated in a unit test without aborting the test process.
///
/// Note what is NOT an input: ownership. That is the whole fix for the two-sync overlap — a later
/// sync mutates ownership synchronously while its OS work is still queued, and reconcile unions
/// persisted identifiers into it, so any ownership-based comparison reports staged changes as
/// drift. Scoping to the sync's own `desired` set removes the variable rather than compensating
/// for it, which is why there is no overlap case to test here: it cannot be expressed.
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

    /// The case the record exists for: this sync asked for a condition and the OS does not list it.
    @Test
    func givenTheOsDoesNotListOne_expectItNamedInMissing() {
        let drift = ConditionMirror.drift(desired: ["a", "b"], atOs: ["a"])

        #expect(drift.missing == ["b"])
        #expect(drift.extra.isEmpty)
    }

    /// A later sync's add draining before this record runs shows as `extra`, and must not
    /// contaminate `missing` — the field the investigation turns on.
    @Test
    func givenTheOsListsSomethingThisSyncDidNotWant_expectExtraOnly() {
        let drift = ConditionMirror.drift(desired: ["a", "b"], atOs: ["a", "b", "c"])

        #expect(drift.missing.isEmpty)
        #expect(drift.extra == ["c"])
    }

    /// Both directions at once, and sorted, so a capture diffs cleanly across passes.
    @Test
    func givenDriftBothWays_expectBothNamedAndSorted() {
        let drift = ConditionMirror.drift(
            desired: ["b", "a", "d"], atOs: ["a", "z", "m"]
        )

        #expect(drift.missing == ["b", "d"])
        #expect(drift.extra == ["m", "z"])
    }

    /// A registration the SDK itself refused must not be reported as OS drift. `startMonitoring`
    /// removes the condition and returns before taking ownership when permission is blocked or
    /// the coordinates are unusable, so the identifier is in the caller's desired set and was
    /// never asked of the OS. Both halves are asserted: the scoped set clears it, and the raw
    /// desired set is shown to produce exactly the false reading this exists to prevent.
    @Test
    func accepted_givenOneRegistrationRefused_expectItIsNotReportedMissing() {
        let requested: Set = ["kept", "refused"]
        // Ownership is the record of acceptance, and the refused identifier never enters it.
        let owned: Set = ["kept"]
        let atOs: Set = ["kept"]

        let accepted = ConditionMirror.accepted(desired: requested, owned: owned)

        #expect(accepted == ["kept"])
        #expect(ConditionMirror.drift(desired: accepted, atOs: atOs).missing.isEmpty)
        #expect(ConditionMirror.drift(desired: requested, atOs: atOs).missing == ["refused"])
    }
}
