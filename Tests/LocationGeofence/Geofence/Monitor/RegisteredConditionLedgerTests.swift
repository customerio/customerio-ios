@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

/// Driven as sequences, not selector inputs: the selector can pass while nothing populates the old
/// generation.
@Suite("RegisteredConditionLedger")
struct RegisteredConditionLedgerTests {
    private func ledgerWithReplacement(
        releaseFirst: Bool
    ) -> (ledger: RegisteredConditionLedger, replacedAt: Date) {
        var ledger = RegisteredConditionLedger()
        let firstAt = Date().addingTimeInterval(-60)
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0),
            radius: 300, transitionTypes: [.enter, .exit], at: firstAt, liveFrom: firstAt
        )
        let replacedAt = Date()
        // Geometry changes release first; the launch path registers over the top. Both keep the old
        // circle.
        if releaseFirst { ledger.retire("1") }
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0.005),
            radius: 300, transitionTypes: [.enter, .exit], at: replacedAt
        )
        ledger.confirm("1", stagedAt: replacedAt, at: replacedAt)
        return (ledger, replacedAt)
    }

    @Test
    func attribution_givenReleaseThenReRegister_expectTheEventResolvesToTheOldCircle() {
        let (ledger, replacedAt) = ledgerWithReplacement(releaseFirst: true)

        let resolved = generation(ledger, at: replacedAt.addingTimeInterval(-1))

        #expect(resolved?.center.longitude == 0)
    }

    @Test
    func attribution_givenReRegisterWithoutRelease_expectTheEventResolvesToTheOldCircle() {
        let (ledger, replacedAt) = ledgerWithReplacement(releaseFirst: false)

        let resolved = generation(ledger, at: replacedAt.addingTimeInterval(-1))

        #expect(resolved?.center.longitude == 0)
    }

    @Test
    func attribution_givenEventAfterTheReplacement_expectTheCurrentCircle() {
        let (ledger, replacedAt) = ledgerWithReplacement(releaseFirst: true)

        let resolved = generation(ledger, at: replacedAt.addingTimeInterval(1))

        #expect(resolved?.center.longitude == 0.005)
    }

    @Test
    func attribution_givenNothingRegistered_expectNoneHeld() {
        let ledger = RegisteredConditionLedger()

        #expect(ledger.attribution(for: "1", raisedAt: Date()) == .noneHeld)
    }

    @Test
    func attribution_givenForgottenAfterTheOsDroppedIt_expectNoneHeld() {
        var (ledger, replacedAt) = ledgerWithReplacement(releaseFirst: true)

        ledger.forget("1")

        // Not `expired`: the entry is gone, so the ledger has no basis to call anything stale.
        #expect(ledger.attribution(for: "1", raisedAt: replacedAt.addingTimeInterval(-1)) == .noneHeld)
    }

    @Test
    func attribution_givenForgetAll_expectNothingRetained() {
        var (ledger, replacedAt) = ledgerWithReplacement(releaseFirst: true)

        ledger.forgetAll()

        #expect(ledger.attribution(for: "1", raisedAt: replacedAt.addingTimeInterval(-1)) == .noneHeld)
        #expect(ledger.condition(for: "1") == nil)
    }

    /// Adoption stamps `.distantPast`: the condition predates the process.
    @Test
    func attribution_givenAdoptedCondition_expectEventsResolveToIt() {
        var ledger = RegisteredConditionLedger()
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0),
            radius: 300, transitionTypes: [.enter, .exit], at: .distantPast, liveFrom: .distantPast
        )

        let resolved = generation(ledger, at: Date().addingTimeInterval(-3600))

        #expect(resolved?.center.longitude == 0)
    }

    /// `registeredAt` is excluded from equality on purpose: identical geometry must not read as a
    /// change.
    @Test
    func equality_givenSameGeometryDifferentRegistrationTime_expectEqual() {
        let a = RegisteredCondition(
            center: LocationData(latitude: 0, longitude: 0), radius: 300,
            transitionTypes: [.enter, .exit], registeredAt: Date()
        )
        let b = RegisteredCondition(
            center: LocationData(latitude: 0, longitude: 0), radius: 300,
            transitionTypes: [.enter, .exit], registeredAt: Date().addingTimeInterval(-500)
        )

        #expect(a == b)
    }

    @Test
    func attribution_givenEventBetweenStagingAndDrain_expectTheOldCircle() {
        var ledger = RegisteredConditionLedger()
        let firstAt = Date().addingTimeInterval(-60)
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0),
            radius: 300, transitionTypes: [.enter, .exit], at: firstAt, liveFrom: firstAt
        )
        let stagedAt = Date()
        ledger.retire("1")
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0.005),
            radius: 300, transitionTypes: [.enter, .exit], at: stagedAt
        )

        // Staged but not drained: the OS is still on the old circle.
        let resolved = generation(ledger, at: stagedAt.addingTimeInterval(1))

        #expect(resolved?.center.longitude == 0)
    }

    @Test
    func attribution_givenEventAfterTheDrain_expectTheNewCircle() {
        var ledger = RegisteredConditionLedger()
        let stagedAt = Date()
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0.005),
            radius: 300, transitionTypes: [.enter, .exit], at: stagedAt
        )
        let drainedAt = stagedAt.addingTimeInterval(2)
        ledger.confirm("1", stagedAt: stagedAt, at: drainedAt)

        #expect(generation(ledger, at: drainedAt.addingTimeInterval(1))?.center.longitude == 0.005)
    }

    /// A drain promotes the oldest staged generation: the queue is serial.
    @Test
    func confirm_givenThreeStagedAndTheyDrainInTurn_expectEachBecomesLiveInOrder() {
        var ledger = RegisteredConditionLedger()
        let firstStagedAt = Date().addingTimeInterval(-40)
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0),
            radius: 300, transitionTypes: [.enter, .exit], at: firstStagedAt
        )
        let secondStagedAt = Date().addingTimeInterval(-35)
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0.005),
            radius: 300, transitionTypes: [.enter, .exit], at: secondStagedAt
        )
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0.01),
            radius: 300, transitionTypes: [.enter, .exit], at: Date().addingTimeInterval(-30)
        )

        let firstDrainedAt = Date().addingTimeInterval(-20)
        ledger.confirm("1", stagedAt: firstStagedAt, at: firstDrainedAt)

        #expect(generation(ledger, at: firstDrainedAt.addingTimeInterval(1))?.center.longitude == 0)

        let secondDrainedAt = Date().addingTimeInterval(-10)
        ledger.confirm("1", stagedAt: secondStagedAt, at: secondDrainedAt)

        #expect(generation(ledger, at: secondDrainedAt.addingTimeInterval(1))?.center.longitude == 0.005)
        // The window between the two drains still belongs to the first circle.
        #expect(generation(ledger, at: secondDrainedAt.addingTimeInterval(-1))?.center.longitude == 0)
    }

    @Test
    func attribution_givenTwoReplacementsStagedBeforeEitherDrains_expectTheCircleTheOsHolds() {
        var ledger = RegisteredConditionLedger()
        let liveAt = Date().addingTimeInterval(-60)
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0),
            radius: 300, transitionTypes: [.enter, .exit], at: liveAt, liveFrom: liveAt
        )
        ledger.retire("1")
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0.005),
            radius: 300, transitionTypes: [.enter, .exit], at: Date().addingTimeInterval(-30)
        )
        ledger.retire("1")
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0.01),
            radius: 300, transitionTypes: [.enter, .exit], at: Date().addingTimeInterval(-10)
        )

        #expect(generation(ledger, at: Date())?.center.longitude == 0)
    }

    @Test
    func stagedAndLive_givenAReplacementNotYetDrained_expectEachReadsItsOwnGeneration() {
        var ledger = RegisteredConditionLedger()
        let liveAt = Date().addingTimeInterval(-60)
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0),
            radius: 300, transitionTypes: [.enter, .exit], at: liveAt, liveFrom: liveAt
        )
        ledger.retire("1")
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0.005),
            radius: 300, transitionTypes: [.enter, .exit], at: Date().addingTimeInterval(-10)
        )

        #expect(ledger.condition(for: "1")?.center.longitude == 0.005)
        #expect(generation(ledger, at: Date())?.center.longitude == 0)
    }

    @Test
    func retire_expectClaimDroppedAndAttributionKept() {
        var ledger = RegisteredConditionLedger()
        let liveAt = Date().addingTimeInterval(-60)
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0),
            radius: 300, transitionTypes: [.enter, .exit], at: liveAt, liveFrom: liveAt
        )

        ledger.retire("1")

        #expect(ledger.condition(for: "1") == nil)
        #expect(generation(ledger, at: Date())?.center.longitude == 0)
    }

    /// `expired`, not `noneHeld`: consumers take `noneHeld` as current, which would let a stale exit
    /// store `outside`.
    @Test
    func attribution_givenAnEventOlderThanEveryHeldGeneration_expectExpired() {
        var ledger = RegisteredConditionLedger()
        let firstLiveAt = Date().addingTimeInterval(-60)
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0),
            radius: 300, transitionTypes: [.enter, .exit], at: firstLiveAt, liveFrom: firstLiveAt
        )
        let secondStagedAt = Date().addingTimeInterval(-30)
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0.005),
            radius: 300, transitionTypes: [.enter, .exit], at: secondStagedAt
        )
        ledger.confirm("1", stagedAt: secondStagedAt, at: Date().addingTimeInterval(-20))

        #expect(generation(ledger, at: firstLiveAt.addingTimeInterval(1))?.center.longitude == 0)
        #expect(ledger.attribution(for: "1", raisedAt: firstLiveAt.addingTimeInterval(-1)) == .expired)
    }

    /// Not expired before the FIRST add: the OS may already hold the same circle. Expiry needs a
    /// replacement.
    @Test
    func attribution_givenAFirstAddAndAnEventBeforeItWasIssued_expectNoneHeld() {
        var ledger = RegisteredConditionLedger()
        let stagedAt = Date().addingTimeInterval(-60)
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0),
            radius: 300, transitionTypes: [.enter, .exit], at: stagedAt
        )
        let liveFrom = stagedAt.addingTimeInterval(2)
        ledger.confirm("1", stagedAt: stagedAt, at: liveFrom)

        #expect(ledger.attribution(for: "1", raisedAt: liveFrom.addingTimeInterval(-1)) == .noneHeld)
    }

    @Test
    func attribution_givenStagedButNeverDrained_expectNoneHeld() {
        var ledger = RegisteredConditionLedger()
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0),
            radius: 300, transitionTypes: [.enter, .exit], at: Date().addingTimeInterval(-60)
        )

        #expect(ledger.attribution(for: "1", raisedAt: Date()) == .noneHeld)
    }

    /// The OS dates an add's corrective event as the add lands, so an event AT `liveFrom` is the
    /// new generation.
    @Test
    func attribution_givenAnEventAtTheInstantTheAddWasIssued_expectTheNewGeneration() {
        var ledger = RegisteredConditionLedger()
        let firstLiveAt = Date().addingTimeInterval(-60)
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0),
            radius: 300, transitionTypes: [.enter, .exit], at: firstLiveAt, liveFrom: firstLiveAt
        )
        let stagedAt = Date().addingTimeInterval(-30)
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0.01),
            radius: 300, transitionTypes: [.enter, .exit], at: stagedAt
        )
        let liveFrom = Date().addingTimeInterval(-20)
        ledger.confirm("1", stagedAt: stagedAt, at: liveFrom)

        #expect(generation(ledger, at: liveFrom)?.center.longitude == 0.01)
        #expect(generation(ledger, at: liveFrom.addingTimeInterval(-0.001))?.center.longitude == 0)
    }

    /// `confirm` is keyed on staging time, so a forgotten generation's confirm matches nothing.
    @Test
    func confirm_givenTheIdentifierWasForgottenBeforeTheDrain_expectTheReplacementStaysQueued() {
        var ledger = RegisteredConditionLedger()
        let firstStagedAt = Date().addingTimeInterval(-60)
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0),
            radius: 300, transitionTypes: [.enter, .exit], at: firstStagedAt
        )
        ledger.forget("1")
        let secondStagedAt = Date().addingTimeInterval(-30)
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0.005),
            radius: 300, transitionTypes: [.enter, .exit], at: secondStagedAt
        )

        ledger.confirm("1", stagedAt: firstStagedAt, at: Date().addingTimeInterval(-10))

        #expect(ledger.attribution(for: "1", raisedAt: Date()) == .noneHeld)
        #expect(ledger.condition(for: "1")?.center.longitude == 0.005)
    }

    /// Read by the diagnostics sampler; keyed on live generations, a removed fence would read as
    /// missing.
    @Test
    func stagedIdentifiers_givenOneRetiredAndOneUnconfirmed_expectOnlyTheWantedOnesListed() {
        var ledger = RegisteredConditionLedger()
        let at = Date()
        for identifier in ["1", "2"] {
            ledger.note(
                identifier: identifier, center: LocationData(latitude: 0, longitude: 0),
                radius: 300, transitionTypes: [.enter, .exit], at: at, liveFrom: at
            )
        }
        #expect(ledger.stagedIdentifiers == ["1", "2"])

        ledger.retire("1")

        #expect(ledger.stagedIdentifiers == ["2"])
        // The live generation outlives the claim, which is why `staged` is the field to read.
        #expect(ledger.attribution(for: "1", raisedAt: at) != .noneHeld)

        ledger.note(
            identifier: "3", center: LocationData(latitude: 0, longitude: 0),
            radius: 300, transitionTypes: [.enter, .exit], at: at
        )

        #expect(ledger.stagedIdentifiers == ["2", "3"])
        #expect(ledger.attribution(for: "3", raisedAt: at) == .noneHeld)
    }

    private func generation(_ ledger: RegisteredConditionLedger, at raisedAt: Date) -> RegisteredCondition? {
        guard case .generation(let condition) = ledger.attribution(for: "1", raisedAt: raisedAt) else { return nil }
        return condition
    }
}
