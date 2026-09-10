@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

/// The generation bookkeeping behind event attribution, driven as a sequence rather than by handing
/// a selector its inputs. An earlier version tested the choice in isolation and passed while nothing
/// in the monitor ever populated the previous generation, so every stale event resolved to nil and
/// the guard was inert on the one path it existed for.
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
        // `setMonitoredRegions` releases ownership before re-registering a changed region; the
        // launch path registers straight over the top. Both must retain the old circle.
        if releaseFirst { ledger.retire("1") }
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0.005),
            radius: 300, transitionTypes: [.enter, .exit], at: replacedAt
        )
        ledger.confirm("1", stagedAt: replacedAt, at: replacedAt)
        return (ledger, replacedAt)
    }

    /// The path a geometry change actually takes: ownership is released, then the replacement is
    /// registered. An event the daemon raised before the swap belongs to the circle it crossed.
    @Test
    func circle_givenReleaseThenReRegister_expectTheEventResolvesToTheOldCircle() {
        let (ledger, replacedAt) = ledgerWithReplacement(releaseFirst: true)

        let resolved = ledger.circle(for: "1", raisedAt: replacedAt.addingTimeInterval(-1))

        #expect(resolved?.center.longitude == 0)
    }

    /// Registering straight over a live entry has to behave identically, or the attribution depends
    /// on which caller happened to reach it.
    @Test
    func circle_givenReRegisterWithoutRelease_expectTheEventResolvesToTheOldCircle() {
        let (ledger, replacedAt) = ledgerWithReplacement(releaseFirst: false)

        let resolved = ledger.circle(for: "1", raisedAt: replacedAt.addingTimeInterval(-1))

        #expect(resolved?.center.longitude == 0)
    }

    /// Control: an ordinary event postdates its registration and must resolve to the current
    /// circle, or every exit would be refused as stale.
    @Test
    func circle_givenEventAfterTheReplacement_expectTheCurrentCircle() {
        let (ledger, replacedAt) = ledgerWithReplacement(releaseFirst: true)

        let resolved = ledger.circle(for: "1", raisedAt: replacedAt.addingTimeInterval(1))

        #expect(resolved?.center.longitude == 0.005)
    }

    /// Nothing registered means nothing can be said, and a consumer reads that as "treat as
    /// current" rather than refusing a genuine crossing.
    @Test
    func circle_givenNothingRegistered_expectNil() {
        let ledger = RegisteredConditionLedger()

        #expect(ledger.circle(for: "1", raisedAt: Date()) == nil)
    }

    /// The OS gave the condition up, so a later event must not be attributed to either generation.
    @Test
    func circle_givenForgottenAfterTheOsDroppedIt_expectNil() {
        var (ledger, replacedAt) = ledgerWithReplacement(releaseFirst: true)

        ledger.forget("1")

        #expect(ledger.circle(for: "1", raisedAt: replacedAt.addingTimeInterval(-1)) == nil)
    }

    /// Teardown clears both generations: a belief inherited across sign-out would attribute the
    /// next session's events to the previous one's geometry.
    @Test
    func circle_givenForgetAll_expectNothingRetained() {
        var (ledger, replacedAt) = ledgerWithReplacement(releaseFirst: true)

        ledger.forgetAll()

        #expect(ledger.circle(for: "1", raisedAt: replacedAt.addingTimeInterval(-1)) == nil)
        #expect(ledger.condition(for: "1") == nil)
    }

    /// Adoption stamps `.distantPast` because the condition predates the process. Every event it
    /// will see therefore postdates it and resolves to the adopted circle rather than through nil.
    @Test
    func circle_givenAdoptedCondition_expectEventsResolveToIt() {
        var ledger = RegisteredConditionLedger()
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0),
            radius: 300, transitionTypes: [.enter, .exit], at: .distantPast, liveFrom: .distantPast
        )

        let resolved = ledger.circle(for: "1", raisedAt: Date().addingTimeInterval(-3600))

        #expect(resolved?.center.longitude == 0)
    }

    /// `registeredAt` is excluded from equality on purpose: the baseline heal compares conditions to
    /// ask whether the CIRCLE still matches, and a re-registration of identical geometry must not
    /// read as a change there.
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

    /// The staging→drain window, and the reason `liveFrom` exists. Registration records geometry
    /// synchronously but the OS keeps evaluating the old circle until the queued remove+add drains,
    /// so an event raised in between postdates the new registration yet belongs to the old circle.
    @Test
    func circle_givenEventBetweenStagingAndDrain_expectTheOldCircle() {
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
        let resolved = ledger.circle(for: "1", raisedAt: stagedAt.addingTimeInterval(1))

        #expect(resolved?.center.longitude == 0)
    }

    /// Once the add drains the new circle is the one events belong to.
    @Test
    func circle_givenEventAfterTheDrain_expectTheNewCircle() {
        var ledger = RegisteredConditionLedger()
        let stagedAt = Date()
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0.005),
            radius: 300, transitionTypes: [.enter, .exit], at: stagedAt
        )
        let drainedAt = stagedAt.addingTimeInterval(2)
        ledger.confirm("1", stagedAt: stagedAt, at: drainedAt)

        #expect(ledger.circle(for: "1", raisedAt: drainedAt.addingTimeInterval(1))?.center.longitude == 0.005)
    }

    /// A drain promotes the generation it belongs to, not the newest staged one. Three can be
    /// queued at once, and the queue is serial, so the circle the OS takes next is the oldest
    /// queued — reading the newest instead attributes events to a circle the OS has not reached.
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

        #expect(ledger.circle(for: "1", raisedAt: firstDrainedAt.addingTimeInterval(1))?.center.longitude == 0)

        let secondDrainedAt = Date().addingTimeInterval(-10)
        ledger.confirm("1", stagedAt: secondStagedAt, at: secondDrainedAt)

        #expect(ledger.circle(for: "1", raisedAt: secondDrainedAt.addingTimeInterval(1))?.center.longitude == 0.005)
        // The window between the two drains still belongs to the first circle.
        #expect(ledger.circle(for: "1", raisedAt: secondDrainedAt.addingTimeInterval(-1))?.center.longitude == 0)
    }

    /// Two replacements staged before either add drains — a second refresh landing while the first
    /// is still queued. The OS is on the original circle throughout, so an exit raised in that
    /// window belongs to it. Attributing it to a circle the OS never took gets the exit refused by
    /// the consumer's geometry guard and leaves the device believed inside.
    @Test
    func circle_givenTwoReplacementsStagedBeforeEitherDrains_expectTheCircleTheOsHolds() {
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

        #expect(ledger.circle(for: "1", raisedAt: Date())?.center.longitude == 0)
    }

    /// The split the two kinds of consumer depend on: a sync diffing geometry must see the circle
    /// just staged, while attribution must still see the one the OS is evaluating. Asserted
    /// together because reading either from the other's source is the whole bug class here.
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
        #expect(ledger.circle(for: "1", raisedAt: Date())?.center.longitude == 0)
    }

    /// Retiring drops the claim, so geometry comparisons stop matching, but the OS keeps evaluating
    /// the circle until a queued removal drains and an event already raised can still arrive.
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
        #expect(ledger.circle(for: "1", raisedAt: Date())?.center.longitude == 0)
    }
}
