@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

@Suite("GeofenceStorage polygon membership")
struct PolygonMembershipStorageTests {
    private func makeStorage() -> GeofenceStorage {
        GeofenceStorage(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
    }

    /// A polygon with no record is undecided, not outside — so the first decisive fix placing the
    /// device inside is a genuine enter. This is the polygon counterpart of enter-when-inside.
    @Test
    func recordPolygonMembership_givenNoRecordAndInside_expectEnterDelivered() async {
        let storage = makeStorage()
        let outcome = await storage.recordPolygonMembership(.inside, forIdentifier: "1")
        #expect(outcome == .deliver(.enter))
    }

    /// Establishing "outside" for the first time is not a crossing — nothing was entered to leave.
    @Test
    func recordPolygonMembership_givenNoRecordAndOutside_expectSuppressed() async {
        let storage = makeStorage()
        let outcome = await storage.recordPolygonMembership(.outside, forIdentifier: "1")
        #expect(outcome == .suppressedInitialOutside)
        #expect(await storage.getPolygonMembership()["1"]?.membership == .outside)
    }

    @Test
    func recordPolygonMembership_givenUnchangedBelief_expectSuppressed() async {
        let storage = makeStorage()
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")
        let outcome = await storage.recordPolygonMembership(.inside, forIdentifier: "1")
        #expect(outcome == .suppressedNoChange)
    }

    @Test
    func recordPolygonMembership_givenBeliefFlips_expectExitDelivered() async {
        let storage = makeStorage()
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")
        let outcome = await storage.recordPolygonMembership(.outside, forIdentifier: "1")
        #expect(outcome == .deliver(.exit))
        #expect(await storage.getPolygonMembership()["1"]?.membership == .outside)
    }

    /// An evaluation whose fix predates the stored belief must not overwrite it with an older
    /// reading — the same protection `recordMonitorEvent` gives the baseline heal.
    @Test
    func recordPolygonMembership_givenEvidenceOlderThanBelief_expectSuppressed() async {
        let storage = makeStorage()
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
        let storage = makeStorage()
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
        let storage = makeStorage()
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await storage.recordRegistration(center: LocationData(latitude: 1, longitude: 1), businessIds: ["1"])

        #expect(await storage.getPolygonMembership()["1"]?.membership == .inside)
        #expect(await storage.recordPolygonMembership(.inside, forIdentifier: "1") == .suppressedNoChange)
    }

    /// A polygon dropped from the registered set stops being evaluated, so a retained belief would
    /// go stale and suppress the enter owed when the device comes back to it.
    @Test
    func recordPolygonMembership_givenGeofenceLeavesRegisteredSet_expectBeliefPruned() async {
        let storage = makeStorage()
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await storage.recordRegistration(center: LocationData(latitude: 1, longitude: 1), businessIds: ["2"])

        #expect(await storage.getPolygonMembership()["1"] == nil)
        #expect(await storage.recordPolygonMembership(.inside, forIdentifier: "1") == .deliver(.enter))
    }

    @Test
    func clearUserScopedState_expectMembershipCleared() async {
        let storage = makeStorage()
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await storage.clearUserScopedState()

        #expect(await storage.getPolygonMembership().isEmpty)
    }
}
