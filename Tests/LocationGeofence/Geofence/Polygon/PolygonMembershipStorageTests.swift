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

    /// The OS reporting the covering circle unmonitored reseeds the CIRCLE baseline only. Dropping
    /// the belief too would make a device that never moved look like a brand-new polygon, and a
    /// brand-new polygon found inside delivers an enter — a second one the customer already had.
    @Test
    func clearMonitorRegionRecord_expectPolygonBeliefKept() async {
        let storage = await makeStorage()
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await storage.clearMonitorRegionRecord(identifier: "1")

        #expect(await storage.getPolygonMembership()["1"]?.membership == .inside)
        // The circle baseline really was reseeded — this is not a no-op that happens to keep belief.
        #expect(await storage.getMonitorRegionRecords()["1"] == nil)
    }

    /// Column 1 of the eviction trade: the device never left. The belief survives, so the
    /// re-evaluation after re-registration is a no-change and no duplicate enter is delivered.
    @Test
    func clearMonitorRegionRecord_givenDeviceStillInside_expectNoDuplicateEnter() async {
        let storage = await makeStorage()
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await storage.clearMonitorRegionRecord(identifier: "1")

        #expect(await storage.recordPolygonMembership(.inside, forIdentifier: "1") == .suppressedNoChange)
    }

    /// Column 2: the device left during the gap. The retained `inside` belief is what makes the
    /// verdict a change, so the exit is delivered. Dropped, this became `.suppressedInitialOutside`
    /// and the customer kept an enter with no exit.
    @Test
    func clearMonitorRegionRecord_givenDeviceLeftDuringGap_expectExitDelivered() async {
        let storage = await makeStorage()
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await storage.clearMonitorRegionRecord(identifier: "1")

        #expect(await storage.recordPolygonMembership(.outside, forIdentifier: "1") == .deliver(.exit))
    }

    /// Column 3, the case this trade gives up and the one the #1244 review asked for: the device
    /// left and came back while nothing was watching. Both edges are missed. Pinned deliberately so
    /// the loss is visible rather than discovered in the field.
    @Test
    func clearMonitorRegionRecord_givenDeviceLeftAndReturnedDuringGap_expectBothEdgesMissed() async {
        let storage = await makeStorage()
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await storage.clearMonitorRegionRecord(identifier: "1")

        // Nothing observed the departure or the return; the next verdict simply agrees with belief.
        #expect(await storage.recordPolygonMembership(.inside, forIdentifier: "1") == .suppressedNoChange)
    }

    /// `forceReseed` reseeds the circle baseline for the same eviction, and parts company with the
    /// belief for the same reason `clearMonitorRegionRecord` does.
    @Test
    func recordMonitorRegistration_givenForceReseed_expectPolygonBeliefKept() async {
        let storage = await makeStorage()
        let center = LocationData(latitude: 0, longitude: 0)
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await storage.recordMonitorRegistration(
            identifier: "1", transitionTypes: [.enter, .exit], initialState: .exit,
            center: center, radius: 100, forceReseed: true
        )

        #expect(await storage.getPolygonMembership()["1"]?.membership == .inside)
        #expect(await storage.recordPolygonMembership(.inside, forIdentifier: "1") == .suppressedNoChange)
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

    // MARK: - Geometry boundary on the write

    private static let ringA = [
        LocationData(latitude: 0, longitude: 0),
        LocationData(latitude: 0, longitude: 1),
        LocationData(latitude: 1, longitude: 1)
    ]
    private static let ringB = [
        LocationData(latitude: 5, longitude: 5),
        LocationData(latitude: 5, longitude: 6),
        LocationData(latitude: 6, longitude: 6)
    ]

    private func polygon(
        id: String = "1", ring: [LocationData], latitude: Double = 0, longitude: Double = 0,
        radius: Double = 300
    ) -> Geofence {
        Geofence(
            id: id, latitude: latitude, longitude: longitude, radius: radius, name: nil,
            transitionTypes: [.enter, .exit], lastUpdated: Date(), vertices: ring
        )
    }

    private func circle(latitude: Double = 0, longitude: Double = 0, radius: Double = 300) -> MonitoredCircle {
        MonitoredCircle(
            center: LocationData(latitude: latitude, longitude: longitude),
            radius: radius, maximumRadius: 1000
        )
    }

    /// The evaluation re-reads the ring after its location request, but it then decides on the main
    /// actor and hops back here to write — a refresh can replace the fence under the same id in
    /// that gap. The verdict belongs to the ring it was computed from, so the write is refused.
    @Test
    func recordPolygonMembership_givenTheRingReplacedSinceEvaluation_expectSuppressedAndNoBelief() async {
        let storage = await makeStorage()
        await storage.setCachedGeofences([polygon(ring: Self.ringB)])

        let outcome = await storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfRingMatches: Self.ringA
        )

        #expect(outcome == .suppressedGeometryChanged)
        #expect(await storage.getPolygonMembership()["1"] == nil)
    }

    /// Control: the same call against an unchanged catalog must still deliver, or the guard above
    /// would be indistinguishable from one that refuses everything.
    @Test
    func recordPolygonMembership_givenTheRingUnchanged_expectEnterDelivered() async {
        let storage = await makeStorage()
        await storage.setCachedGeofences([polygon(ring: Self.ringA)])

        let outcome = await storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfRingMatches: Self.ringA
        )

        #expect(outcome == .deliver(.enter))
    }

    /// A fence dropped from the cache entirely is the same failure as a replaced one: there is no
    /// current ring for the verdict to belong to.
    @Test
    func recordPolygonMembership_givenTheFenceLeftTheCacheSinceEvaluation_expectSuppressed() async {
        let storage = await makeStorage()

        let outcome = await storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfRingMatches: Self.ringA
        )

        #expect(outcome == .suppressedGeometryChanged)
    }

    /// Supplying no ring states the verdict does not rest on one, so it gets no ring check. The
    /// covering exit is the caller that does this, and is gated on its circle instead.
    @Test
    func recordPolygonMembership_givenNoRingSuppliedAndTheRingReplaced_expectTheGeometryCheckSkipped() async {
        let storage = await makeStorage()
        await storage.setCachedGeofences([polygon(ring: Self.ringA)])
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1", onlyIfRingMatches: Self.ringA)
        await storage.setCachedGeofences([polygon(ring: Self.ringB)])

        let outcome = await storage.recordPolygonMembership(.outside, forIdentifier: "1")

        #expect(outcome == .deliver(.exit))
    }

    /// The covering exit's window, and why the circle is compared inside the write rather than
    /// before the hop: the resolver matched the event's circle against the fence it loaded, then a
    /// refresh replaced ring and circle together before the store landed. Recording `outside` here
    /// would assert the device left a polygon it may be standing inside, stamped with a date no
    /// older fix can then correct.
    @Test
    func recordPolygonMembership_givenTheCircleReplacedSinceTheEventWasRaised_expectSuppressed() async {
        let storage = await makeStorage()
        await storage.setCachedGeofences([polygon(ring: Self.ringA)])
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")
        await storage.setCachedGeofences([polygon(ring: Self.ringB, longitude: 0.005)])

        let outcome = await storage.recordPolygonMembership(
            .outside, forIdentifier: "1", onlyIfCircleMatches: circle()
        )

        #expect(outcome == .suppressedGeometryChanged)
        #expect(await storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    /// Control: the circle the fence still has is the case the containment argument covers and must
    /// deliver, or the guard above is indistinguishable from one that refuses every exit.
    @Test
    func recordPolygonMembership_givenTheCircleUnchanged_expectExitDelivered() async {
        let storage = await makeStorage()
        await storage.setCachedGeofences([polygon(ring: Self.ringA)])
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")

        let outcome = await storage.recordPolygonMembership(
            .outside, forIdentifier: "1", onlyIfCircleMatches: circle()
        )

        #expect(outcome == .deliver(.exit))
    }

    /// A fence gone from the cache has no circle for the event to still match, so the exit is
    /// refused on the same rule rather than falling through the guard.
    @Test
    func recordPolygonMembership_givenTheFenceLeftTheCacheAndACircleSupplied_expectSuppressed() async {
        let storage = await makeStorage()
        await storage.setCachedGeofences([polygon(ring: Self.ringA)])
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")
        await storage.setCachedGeofences([])

        let outcome = await storage.recordPolygonMembership(
            .outside, forIdentifier: "1", onlyIfCircleMatches: circle()
        )

        #expect(outcome == .suppressedGeometryChanged)
    }

    /// An over-cap fence is monitored by `min(radius, cap)`, so comparing the event against the
    /// fence's declared radius would read it as replaced and refuse its exits for good.
    @Test
    func recordPolygonMembership_givenAnOverCapFenceAndItsClampedCircle_expectExitDelivered() async {
        let storage = await makeStorage()
        await storage.setCachedGeofences([polygon(ring: Self.ringA, radius: 5000)])
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")

        let outcome = await storage.recordPolygonMembership(
            .outside, forIdentifier: "1", onlyIfCircleMatches: circle(radius: 1000)
        )

        #expect(outcome == .deliver(.exit))
    }
}
