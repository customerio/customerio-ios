@testable import CioLocationGeofence
import Foundation
import Testing

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

    @Test
    func givenTheOsListsSomethingThisSyncDidNotWant_expectExtraOnly() {
        let drift = ConditionMirror.drift(desired: ["a", "b"], atOs: ["a", "b", "c"])

        #expect(drift.missing.isEmpty)
        #expect(drift.extra == ["c"])
    }

    @Test
    func givenDriftBothWays_expectBothNamedAndSorted() {
        let drift = ConditionMirror.drift(
            desired: ["b", "a", "d"], atOs: ["a", "z", "m"]
        )

        #expect(drift.missing == ["b", "d"])
        #expect(drift.extra == ["m", "z"])
    }

    /// Literals, not raw values: a case rename must not change what captures grep for.
    @Test
    func occasion_expectTheTokensStayWhatCapturesGrepFor() {
        #expect(ConditionMirrorOccasion.sync.token == "sync")
        #expect(ConditionMirrorOccasion.poll.token == "poll")
    }

    @Test
    func target_givenEverythingAccepted_expectNothingCountedRefused() {
        let target = ConditionMirror.target(desired: ["a", "b"], owned: ["a", "b"])

        #expect(target.accepted == ["a", "b"])
        #expect(target.refused == 0)
    }

    /// The last drift check shows the false `missing` that scoping to accepted prevents.
    @Test
    func accepted_givenOneRegistrationRefused_expectItIsNotReportedMissing() {
        let requested: Set = ["kept", "refused"]
        let owned: Set = ["kept"]
        let atOs: Set = ["kept"]

        let target = ConditionMirror.target(desired: requested, owned: owned)

        #expect(target.accepted == ["kept"])
        #expect(ConditionMirror.drift(desired: target.accepted, atOs: atOs).missing.isEmpty)
        #expect(ConditionMirror.drift(desired: requested, atOs: atOs).missing == ["refused"])
        #expect(target.refused == 1)
    }
}
