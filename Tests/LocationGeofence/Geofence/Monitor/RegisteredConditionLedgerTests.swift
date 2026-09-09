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
            radius: 300, transitionTypes: [.enter, .exit], at: firstAt
        )
        let replacedAt = Date()
        // `setMonitoredRegions` releases ownership before re-registering a changed region; the
        // launch path registers straight over the top. Both must retain the old circle.
        if releaseFirst { ledger.retire("1") }
        ledger.note(
            identifier: "1", center: LocationData(latitude: 0, longitude: 0.005),
            radius: 300, transitionTypes: [.enter, .exit], at: replacedAt
        )
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
            radius: 300, transitionTypes: [.enter, .exit], at: .distantPast
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
}
