@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

@Suite("GeofenceStorage polygon membership")
struct PolygonMembershipStorageTests {
    /// Registers the ids first: a belief is only created for a polygon in the registered set, so a
    /// bare storage would suppress every write as `.suppressedUnmonitored`.
    private func makeStorage(registering ids: Set<String> = ["1"]) async -> GeofenceStorage {
        let storage = GeofenceStorage(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: ids)
        return storage
    }

    /// A polygon with no record is undecided, not outside — so the first decisive fix placing the
    /// device inside is a genuine enter. This is the polygon counterpart of enter-when-inside.
    @Test
    func recordPolygonMembership_givenNoRecordAndInside_expectEnterDelivered() async {
        let storage = await makeStorage()
        let outcome = await storage.recordPolygonMembership(.inside, forIdentifier: "1")
        #expect(outcome == .deliver(.enter))
    }

    /// Establishing "outside" for the first time is not a crossing — nothing was entered to leave.
    @Test
    func recordPolygonMembership_givenNoRecordAndOutside_expectSuppressed() async {
        let storage = await makeStorage()
        let outcome = await storage.recordPolygonMembership(.outside, forIdentifier: "1")
        #expect(outcome == .suppressedInitialOutside)
        #expect(await storage.getPolygonMembership()["1"]?.membership == .outside)
    }

    @Test
    func recordPolygonMembership_givenUnchangedBelief_expectSuppressed() async {
        let storage = await makeStorage()
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")
        let outcome = await storage.recordPolygonMembership(.inside, forIdentifier: "1")
        #expect(outcome == .suppressedNoChange)
    }

    @Test
    func recordPolygonMembership_givenBeliefFlips_expectExitDelivered() async {
        let storage = await makeStorage()
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")
        let outcome = await storage.recordPolygonMembership(.outside, forIdentifier: "1")
        #expect(outcome == .deliver(.exit))
        #expect(await storage.getPolygonMembership()["1"]?.membership == .outside)
    }

    /// An evaluation whose fix predates the stored belief must not overwrite it with an older
    /// reading — the same protection `recordMonitorEvent` gives the baseline heal.
    @Test
    func recordPolygonMembership_givenEvidenceOlderThanBelief_expectSuppressed() async {
        let storage = await makeStorage()
        let beliefWrittenAt = Date()
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1", now: beliefWrittenAt)

        let outcome = await storage.recordPolygonMembership(
            .outside,
            forIdentifier: "1",
            onlyIfBeliefPredates: beliefWrittenAt.addingTimeInterval(-10)
        )

        #expect(outcome == .suppressedNewerDecision)
        #expect(await storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    @Test
    func recordPolygonMembership_givenEvidenceNewerThanBelief_expectDelivered() async {
        let storage = await makeStorage()
        let beliefWrittenAt = Date()
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1", now: beliefWrittenAt)

        let outcome = await storage.recordPolygonMembership(
            .outside,
            forIdentifier: "1",
            onlyIfBeliefPredates: beliefWrittenAt.addingTimeInterval(10)
        )

        #expect(outcome == .deliver(.exit))
    }

    /// Membership survives re-registration, which is what keeps a wholesale re-register silent
    /// without needing the registered-ids diff the circle path uses.
    @Test
    func recordPolygonMembership_givenRegistrationRetainsGeofence_expectBeliefPreserved() async {
        let storage = await makeStorage()
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await storage.recordRegistration(center: LocationData(latitude: 1, longitude: 1), businessIds: ["1"])

        #expect(await storage.getPolygonMembership()["1"]?.membership == .inside)
        #expect(await storage.recordPolygonMembership(.inside, forIdentifier: "1") == .suppressedNoChange)
    }

    /// A polygon dropped from the registered set stops being evaluated, so a retained belief would
    /// go stale and suppress the enter owed when the device comes back to it.
    @Test
    func recordPolygonMembership_givenGeofenceLeavesRegisteredSet_expectBeliefPruned() async {
        let storage = await makeStorage()
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await storage.recordRegistration(center: LocationData(latitude: 1, longitude: 1), businessIds: ["2"])
        #expect(await storage.getPolygonMembership()["1"] == nil)

        // Coming back means being registered again; the pruned belief is what makes it an enter
        // rather than a no-change.
        await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: ["1"])
        #expect(await storage.recordPolygonMembership(.inside, forIdentifier: "1") == .deliver(.enter))
    }

    /// The OS reporting the covering circle unmonitored reseeds the circle baseline; the polygon
    /// belief has to go with it. Kept, it would suppress the next real enter as no-change if the
    /// device left the polygon while nothing was watching.
    @Test
    func clearMonitorRegionRecord_expectPolygonBeliefClearedToo() async {
        let storage = await makeStorage()
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await storage.clearMonitorRegionRecord(identifier: "1")

        #expect(await storage.getPolygonMembership()["1"] == nil)
        #expect(await storage.recordPolygonMembership(.inside, forIdentifier: "1") == .deliver(.enter))
    }

    /// The deferred clear can be skipped when a re-registration overtakes it, and then `forceReseed`
    /// is the only thing standing between an unmonitored gap and a swallowed enter. It reseeds the
    /// circle baseline, so it has to reseed the belief too.
    @Test
    func recordMonitorRegistration_givenForceReseed_expectPolygonBeliefCleared() async {
        let storage = await makeStorage()
        let center = LocationData(latitude: 0, longitude: 0)
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await storage.recordMonitorRegistration(
            identifier: "1", transitionTypes: [.enter, .exit], initialState: .exit,
            center: center, radius: 100, forceReseed: true
        )

        #expect(await storage.getPolygonMembership()["1"] == nil)
        #expect(await storage.recordPolygonMembership(.inside, forIdentifier: "1") == .deliver(.enter))
    }

    /// The ordinary sync path re-registers every identifier. Dropping belief there would re-fire an
    /// enter on every sync for a device that never moved.
    @Test
    func recordMonitorRegistration_givenRoutineReregistration_expectPolygonBeliefKept() async {
        let storage = await makeStorage()
        let center = LocationData(latitude: 0, longitude: 0)
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await storage.recordMonitorRegistration(
            identifier: "1", transitionTypes: [.enter, .exit], initialState: .exit,
            center: center, radius: 100
        )

        #expect(await storage.getPolygonMembership()["1"]?.membership == .inside)
        #expect(await storage.recordPolygonMembership(.inside, forIdentifier: "1") == .suppressedNoChange)
    }

    /// The ordering guard compares the stored time against the incoming evidence, so the stored one
    /// has to BE evidence. Storing the write time instead made every record instantly "newer" than
    /// the fix that justified it, rejecting a later verdict whose own fix was genuinely newer.
    @Test
    func recordPolygonMembership_givenEvidenceNewerThanPriorEvidence_expectAccepted() async {
        let storage = await makeStorage()
        let firstFix = Date(timeIntervalSince1970: 1000)
        let secondFix = Date(timeIntervalSince1970: 1005)
        // A write lands well after the fix that justified it — the gap the old code stored.
        _ = await storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfBeliefPredates: firstFix,
            now: Date(timeIntervalSince1970: 1060)
        )

        let outcome = await storage.recordPolygonMembership(
            .outside, forIdentifier: "1", onlyIfBeliefPredates: secondFix,
            now: Date(timeIntervalSince1970: 1065)
        )

        #expect(outcome == .deliver(.exit))
    }

    /// A confirming evaluation is newer evidence for the belief it re-proves. Left unrecorded, an
    /// evaluation carrying OLDER opposite evidence — a foreground pass holding a pre-crossing fix,
    /// resuming after a wake already decided — clears the ordering guard and delivers a crossing
    /// the newer fix had just disproved.
    @Test
    func recordPolygonMembership_givenBeliefConfirmedByNewerEvidence_expectOlderOppositeSuppressed() async {
        let storage = await makeStorage()
        let established = Date(timeIntervalSince1970: 1000)
        let stalePassFix = Date(timeIntervalSince1970: 1003)
        let confirmingFix = Date(timeIntervalSince1970: 1005)
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1", onlyIfBeliefPredates: established)
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1", onlyIfBeliefPredates: confirmingFix)

        let outcome = await storage.recordPolygonMembership(
            .outside, forIdentifier: "1", onlyIfBeliefPredates: stalePassFix
        )

        #expect(outcome == .suppressedNewerDecision)
        #expect(await storage.getPolygonMembership()["1"]?.membership == .inside)
        #expect(await storage.getPolygonMembership()["1"]?.lastChangedAt == confirmingFix)
    }

    @Test
    func clearUserScopedState_expectMembershipCleared() async {
        let storage = await makeStorage()
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await storage.clearUserScopedState()

        #expect(await storage.getPolygonMembership().isEmpty)
    }

    /// An evaluation still in flight when the polygon is pruned must not resurrect it: creating a
    /// belief there would deliver an enter for a fence the OS is no longer watching.
    @Test
    func recordPolygonMembership_givenIdNotRegistered_expectSuppressedAndNoRecord() async {
        let storage = await makeStorage(registering: ["other"])
        let outcome = await storage.recordPolygonMembership(.inside, forIdentifier: "1")
        #expect(outcome == .suppressedUnmonitored)
        #expect(await storage.getPolygonMembership()["1"] == nil)
    }
}
