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
    func attribution_givenReleaseThenReRegister_expectTheEventResolvesToTheOldCircle() {
        let (ledger, replacedAt) = ledgerWithReplacement(releaseFirst: true)

        let resolved = generation(ledger, at: replacedAt.addingTimeInterval(-1))

        #expect(resolved?.center.longitude == 0)
    }

    /// Registering straight over a live entry has to behave identically, or the attribution depends
    /// on which caller happened to reach it.
    @Test
    func attribution_givenReRegisterWithoutRelease_expectTheEventResolvesToTheOldCircle() {
        let (ledger, replacedAt) = ledgerWithReplacement(releaseFirst: false)

        let resolved = generation(ledger, at: replacedAt.addingTimeInterval(-1))

        #expect(resolved?.center.longitude == 0)
    }

    /// Control: an ordinary event postdates its registration and must resolve to the current
    /// circle, or every exit would be refused as stale.
    @Test
    func attribution_givenEventAfterTheReplacement_expectTheCurrentCircle() {
        let (ledger, replacedAt) = ledgerWithReplacement(releaseFirst: true)

        let resolved = generation(ledger, at: replacedAt.addingTimeInterval(1))

        #expect(resolved?.center.longitude == 0.005)
    }

    /// Nothing registered means nothing can be said, and a consumer reads that as "treat as
    /// current" rather than refusing a genuine crossing.
    @Test
    func attribution_givenNothingRegistered_expectNoneHeld() {
        let ledger = RegisteredConditionLedger()

        #expect(ledger.attribution(for: "1", raisedAt: Date()) == .noneHeld)
    }

    /// The OS gave the condition up, so a later event must not be attributed to either generation.
    @Test
    func attribution_givenForgottenAfterTheOsDroppedIt_expectNoneHeld() {
        var (ledger, replacedAt) = ledgerWithReplacement(releaseFirst: true)

        ledger.forget("1")

        // Not `expired`: the entry is gone, so the ledger has no basis to call anything stale.
        #expect(ledger.attribution(for: "1", raisedAt: replacedAt.addingTimeInterval(-1)) == .noneHeld)
    }

    /// Teardown clears both generations: a belief inherited across sign-out would attribute the
    /// next session's events to the previous one's geometry.
    @Test
    func attribution_givenForgetAll_expectNothingRetained() {
        var (ledger, replacedAt) = ledgerWithReplacement(releaseFirst: true)

        ledger.forgetAll()

        #expect(ledger.attribution(for: "1", raisedAt: replacedAt.addingTimeInterval(-1)) == .noneHeld)
        #expect(ledger.condition(for: "1") == nil)
    }

    /// Adoption stamps `.distantPast` because the condition predates the process. Every event it
    /// will see therefore postdates it and resolves to the adopted circle rather than through nil.
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
    /// synchronously but the OS keeps evaluating the old circle until the queued add is issued, so
    /// an event raised in between postdates the new registration yet belongs to the old circle.
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

    /// Once the add drains the new circle is the one events belong to.
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

        #expect(generation(ledger, at: firstDrainedAt.addingTimeInterval(1))?.center.longitude == 0)

        let secondDrainedAt = Date().addingTimeInterval(-10)
        ledger.confirm("1", stagedAt: secondStagedAt, at: secondDrainedAt)

        #expect(generation(ledger, at: secondDrainedAt.addingTimeInterval(1))?.center.longitude == 0.005)
        // The window between the two drains still belongs to the first circle.
        #expect(generation(ledger, at: secondDrainedAt.addingTimeInterval(-1))?.center.longitude == 0)
    }

    /// Two replacements staged before either add drains — a second refresh landing while the first
    /// is still queued. The OS is on the original circle throughout, so an exit raised in that
    /// window belongs to it. Attributing it to a circle the OS never took gets the exit refused by
    /// the consumer's geometry guard and leaves the device believed inside.
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
        #expect(generation(ledger, at: Date())?.center.longitude == 0)
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
        #expect(generation(ledger, at: Date())?.center.longitude == 0)
    }

    /// An event older than BOTH held generations belongs to a circle this ledger no longer has.
    ///
    /// Reported as `expired`, NOT as `noneHeld`. The two look alike here and must not behave alike:
    /// `noneHeld` is a cold wake, where the only safe reading is to take the event as current,
    /// while this event is one the ledger knows is stale. Collapsing them let a stale covering-exit
    /// through the consumer's geometry guard untested, storing `outside` for a device standing
    /// inside the polygon that replaced the one it was raised against.
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

        // Between the two generations resolves to the first, which WAS live then.
        #expect(generation(ledger, at: firstLiveAt.addingTimeInterval(1))?.center.longitude == 0)
        // Before either went live, the ledger knows it cannot answer AND that the event is stale.
        #expect(ledger.attribution(for: "1", raisedAt: firstLiveAt.addingTimeInterval(-1)) == .expired)
    }

    /// The first-add boundary, which must NOT expire. `liveFrom` is stamped just before the OS add
    /// is issued, so an event dated earlier than it was raised before this process registered
    /// anything — a condition the OS already held. Its circle may well be the same one, so
    /// refusing it would lose a genuine crossing; the honest answer is that nothing held covers it.
    /// Expiry needs a generation to have been REPLACED, which is what separates an event this
    /// ledger knows is stale from one it simply never saw the circle for.
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

    /// Staged but never drained: nothing has gone live, so the ledger has never known what the OS
    /// holds and must not call the event stale. `noneHeld`, and the consumer takes it as current.
    @Test
    func attribution_givenStagedButNeverDrained_expectNoneHeld() {
        var ledger = RegisteredConditionLedger()
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0),
            radius: 300, transitionTypes: [.enter, .exit], at: Date().addingTimeInterval(-60)
        )

        #expect(ledger.attribution(for: "1", raisedAt: Date()) == .noneHeld)
    }

    /// The corrective event the OS raises for an add is dated as the add lands, so it arrives at
    /// the earliest instant the new circle can be live. `liveFrom` is stamped just before the add
    /// for that reason, and this pins the boundary the stamp relies on: an event AT `liveFrom`
    /// belongs to the generation that add created, not to the one it replaced. Attributing it
    /// backwards hands the consumer the old circle, whose geometry no longer matches the fence, and
    /// the corrective crossing is refused — the loss the staged `assuming:` snapshot exists to
    /// prevent.
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
        // One instant earlier still belongs to the circle being replaced.
        #expect(generation(ledger, at: liveFrom.addingTimeInterval(-0.001))?.center.longitude == 0)
    }

    /// A confirmation for a generation the identifier no longer holds must not promote whatever
    /// replaced it. The OS gives the id up, a new registration stages under the same id, and the
    /// dropped generation's add drains after that — `confirm` is keyed on staging time, so it
    /// matches nothing and the replacement waits for its own drain instead of being marked live by
    /// someone else's callback.
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

        // Nothing is live: the replacement's own add has not drained.
        #expect(ledger.attribution(for: "1", raisedAt: Date()) == .noneHeld)
        // ...and it is still what a sync diffs its geometry against.
        #expect(ledger.condition(for: "1")?.center.longitude == 0.005)
    }

    /// The condition an attribution names, for assertions that only care about which circle.
    /// The `noneHeld` / `expired` split is asserted directly by the tests that turn on it.
    private func generation(_ ledger: RegisteredConditionLedger, at raisedAt: Date) -> RegisteredCondition? {
        guard case .generation(let condition) = ledger.attribution(for: "1", raisedAt: raisedAt) else { return nil }
        return condition
    }
}
