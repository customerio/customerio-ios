@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

@Suite("GeofenceStorage polygon membership")
struct PolygonMembershipStorageTests {
    /// Registers the ids first; otherwise every write is `.suppressedUnmonitored`.
    private func makeStorage(registering ids: Set<String> = ["1"]) async -> GeofenceStorage {
        let storage = GeofenceStorage(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: ids)
        return storage
    }

    /// A polygon with no record is undecided, not outside — so the first decisive fix placing the
    /// device inside still owes an enter (the polygon counterpart of enter-when-inside). It is
    /// discovery, not a crossing: the device was never seen outside, so the stay's start is unknown.
    @Test
    func recordPolygonMembership_givenNoRecordAndInside_expectDiscoveredInsideDeliveringEnter() async {
        let storage = await makeStorage()
        let outcome = await storage.recordPolygonMembership(.inside, forIdentifier: "1")
        #expect(outcome == .discoveredInside)
        #expect(outcome.deliveredTransition == .enter)
    }

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

    @Test
    func recordPolygonMembership_givenEvidenceInTheFuture_expectLaterEvidenceStillDecides() async {
        let storage = await makeStorage()
        let writtenAt = Date()
        _ = await storage.recordPolygonMembership(
            .inside,
            forIdentifier: "1",
            onlyIfBeliefPredates: writtenAt.addingTimeInterval(3600),
            now: writtenAt
        )

        let outcome = await storage.recordPolygonMembership(
            .outside,
            forIdentifier: "1",
            onlyIfBeliefPredates: writtenAt.addingTimeInterval(1),
            now: writtenAt.addingTimeInterval(1)
        )

        #expect(outcome == .deliver(.exit))
        #expect(await storage.getPolygonMembership()["1"]?.membership == .outside)
    }

    @Test
    func recordPolygonMembership_givenPersistedBeliefStampedInTheFuture_expectLaterFixStillDecides() async {
        let storage = await makeStorage()
        let now = Date()
        var state = await storage.loadFromDisk() ?? GeofenceState()
        state.polygonMembership = [
            "1": PolygonMembershipRecord(membership: .inside, lastChangedAt: now.addingTimeInterval(3600))
        ]
        await storage.saveToDisk(state)

        let outcome = await storage.recordPolygonMembership(
            .outside, forIdentifier: "1", onlyIfBeliefPredates: now, now: now
        )

        #expect(outcome == .deliver(.exit))
        #expect(await storage.getPolygonMembership()["1"]?.membership == .outside)
    }

    /// A real fix is always a little behind `now`, so recovery must discard the future stamp, not
    /// cap it.
    @Test
    func recordPolygonMembership_givenPersistedFutureStampAndAFixWithRealAge_expectRecovery() async {
        let storage = await makeStorage()
        let now = Date()
        var state = await storage.loadFromDisk() ?? GeofenceState()
        state.polygonMembership = [
            "1": PolygonMembershipRecord(membership: .inside, lastChangedAt: now.addingTimeInterval(3600))
        ]
        await storage.saveToDisk(state)

        let outcome = await storage.recordPolygonMembership(
            .outside, forIdentifier: "1", onlyIfBeliefPredates: now.addingTimeInterval(-5), now: now
        )

        #expect(outcome == .deliver(.exit))
    }

    @Test
    func recordPolygonMembership_givenRegistrationRetainsGeofence_expectBeliefPreserved() async {
        let storage = await makeStorage()
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await storage.recordRegistration(center: LocationData(latitude: 1, longitude: 1), businessIds: ["1"])

        #expect(await storage.getPolygonMembership()["1"]?.membership == .inside)
        #expect(await storage.recordPolygonMembership(.inside, forIdentifier: "1") == .suppressedNoChange)
    }

    @Test
    func recordPolygonMembership_givenGeofenceLeavesRegisteredSet_expectBeliefPruned() async {
        let storage = await makeStorage()
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await storage.recordRegistration(center: LocationData(latitude: 1, longitude: 1), businessIds: ["2"])
        #expect(await storage.getPolygonMembership()["1"] == nil)

        await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: ["1"])
        #expect(await storage.recordPolygonMembership(.inside, forIdentifier: "1") == .discoveredInside)
    }

    @Test
    func clearMonitorRegionRecord_expectPolygonBeliefKept() async {
        let storage = await makeStorage()
        let center = LocationData(latitude: 0, longitude: 0)
        // Seeded so the record's removal is observable.
        await storage.recordMonitorRegistration(
            identifier: "1", transitionTypes: [.enter, .exit], initialState: .exit,
            center: center, radius: 100
        )
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await storage.clearMonitorRegionRecord(identifier: "1")

        #expect(await storage.getPolygonMembership()["1"]?.membership == .inside)
        #expect(await storage.getMonitorRegionRecords()["1"] == nil)
    }

    @Test
    func clearMonitorRegionRecord_givenNoMonitorRecord_expectBeliefUntouched() async {
        let storage = await makeStorage()
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await storage.clearMonitorRegionRecord(identifier: "1")

        #expect(await storage.getPolygonMembership()["1"]?.membership == .inside)
    }

    @Test
    func clearMonitorRegionRecord_givenDeviceLeftDuringGap_expectExitDelivered() async {
        let storage = await makeStorage()
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await storage.clearMonitorRegionRecord(identifier: "1")

        #expect(await storage.recordPolygonMembership(.outside, forIdentifier: "1") == .deliver(.exit))
    }

    /// Pins an accepted loss: a device that left and returned unseen gets neither its exit nor its
    /// re-enter.
    @Test
    func clearMonitorRegionRecord_givenInsideVerdictAfterGap_expectNoChangeEitherWay() async {
        let storage = await makeStorage()
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1")

        await storage.clearMonitorRegionRecord(identifier: "1")

        #expect(await storage.recordPolygonMembership(.inside, forIdentifier: "1") == .suppressedNoChange)
    }

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

    @Test
    func recordPolygonMembership_givenEvidenceNewerThanPriorEvidence_expectAccepted() async {
        let storage = await makeStorage()
        let firstFix = Date(timeIntervalSince1970: 1000)
        let secondFix = Date(timeIntervalSince1970: 1005)
        // The write lands well after the fix that justified it.
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

    /// When the inside verdict of an entry test is evidenced. Fixed, and passed as `now` too, so
    /// the gap to the outside proof is exact rather than whatever the runner took between writes.
    private static let insideAt = Date(timeIntervalSince1970: 1800000000)

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

    /// Control for the test above.
    @Test
    func recordPolygonMembership_givenTheRingUnchanged_expectEnterDelivered() async {
        let storage = await makeStorage()
        await storage.setCachedGeofences([polygon(ring: Self.ringA)])

        let outcome = await storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfRingMatches: Self.ringA
        )

        #expect(outcome == .discoveredInside)
        #expect(outcome.deliveredTransition == .enter)
    }

    /// A recent outside belief for the same ring is what makes inside a crossing someone was seen
    /// to make.
    @Test
    func recordPolygonMembership_givenOutsideThenInsideOnTheSameRing_expectObservedEnter() async {
        let storage = await makeStorage()
        await storage.setCachedGeofences([polygon(ring: Self.ringA)])
        let first = await storage.recordPolygonMembership(
            .outside, forIdentifier: "1", onlyIfBeliefPredates: Self.insideAt.addingTimeInterval(-60),
            onlyIfRingMatches: Self.ringA, now: Self.insideAt
        )

        let outcome = await storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfBeliefPredates: Self.insideAt,
            onlyIfRingMatches: Self.ringA, now: Self.insideAt
        )

        #expect(first == .suppressedInitialOutside)
        #expect(outcome == .deliver(.enter))
    }

    /// Outside the OLD ring says nothing about when the device came to be inside the new one: the
    /// replacement may have been drawn around it. Still an ENTER, but discovered, not observed.
    @Test
    func recordPolygonMembership_givenOutsideTheReplacedRingThenInsideTheNewOne_expectDiscoveredInside() async {
        let storage = await makeStorage()
        await storage.setCachedGeofences([polygon(ring: Self.ringA)])
        _ = await storage.recordPolygonMembership(.outside, forIdentifier: "1", onlyIfRingMatches: Self.ringA)
        await storage.setCachedGeofences([polygon(ring: Self.ringB)])

        let outcome = await storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfRingMatches: Self.ringB
        )

        #expect(outcome == .discoveredInside)
    }

    /// Being proven outside the NEW ring re-establishes the precondition, so the next arrival is a
    /// crossing again — the replacement costs at most the one stay it landed in.
    @Test
    func recordPolygonMembership_givenOutsideConfirmedAgainstTheNewRing_expectNextEnterObserved() async {
        let storage = await makeStorage()
        await storage.setCachedGeofences([polygon(ring: Self.ringA)])
        _ = await storage.recordPolygonMembership(
            .outside, forIdentifier: "1", onlyIfBeliefPredates: Self.insideAt.addingTimeInterval(-600),
            onlyIfRingMatches: Self.ringA, now: Self.insideAt
        )
        await storage.setCachedGeofences([polygon(ring: Self.ringB)])

        let confirmed = await storage.recordPolygonMembership(
            .outside, forIdentifier: "1", onlyIfBeliefPredates: Self.insideAt.addingTimeInterval(-60),
            onlyIfRingMatches: Self.ringB, now: Self.insideAt
        )
        let outcome = await storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfBeliefPredates: Self.insideAt,
            onlyIfRingMatches: Self.ringB, now: Self.insideAt
        )

        #expect(confirmed == .suppressedNoChange)
        #expect(outcome == .deliver(.enter))
    }

    /// A belief written before records carried their ring cannot say which shape it was formed
    /// against, so it proves no entry: the stay it begins has no known start.
    @Test
    func recordPolygonMembership_givenLegacyOutsideRecordWithoutRing_expectDiscoveredInside() async {
        let storage = await makeStorage()
        await storage.setCachedGeofences([polygon(ring: Self.ringA)])
        var state = await storage.loadFromDisk() ?? GeofenceState()
        state.polygonMembership = [
            "1": PolygonMembershipRecord(membership: .outside, lastChangedAt: Date().addingTimeInterval(-60))
        ]
        await storage.saveToDisk(state)

        let outcome = await storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfRingMatches: Self.ringA
        )

        #expect(outcome == .discoveredInside)
    }

    /// The ring stamp survives a relaunch, so an outside belief written before the process died
    /// still makes the next arrival an observed crossing.
    @Test
    func recordPolygonMembership_givenOutsideBeliefAcrossRelaunch_expectObservedEnter() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let beforeRelaunch = GeofenceStorage(fileManager: .default, directoryURL: directory)
        await beforeRelaunch.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: ["1"])
        await beforeRelaunch.setCachedGeofences([polygon(ring: Self.ringA)])
        _ = await beforeRelaunch.recordPolygonMembership(
            .outside, forIdentifier: "1", onlyIfBeliefPredates: Self.insideAt.addingTimeInterval(-60),
            onlyIfRingMatches: Self.ringA, now: Self.insideAt
        )

        let afterRelaunch = GeofenceStorage(fileManager: .default, directoryURL: directory)
        let outcome = await afterRelaunch.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfBeliefPredates: Self.insideAt,
            onlyIfRingMatches: Self.ringA, now: Self.insideAt
        )

        #expect(outcome == .deliver(.enter))
    }

    // MARK: - Outside proof age

    /// Seeds an `outside` belief against ring A proven at `provenAt`, then applies an inside
    /// verdict evidenced at `insideAt` (nil for an unordered write).
    private func insideAfterOutside(
        provenAt: Date,
        insideAt: Date? = PolygonMembershipStorageTests.insideAt
    ) async -> (outcome: PolygonMembershipOutcome, storage: GeofenceStorage) {
        let storage = await makeStorage()
        await storage.setCachedGeofences([polygon(ring: Self.ringA)])
        _ = await storage.recordPolygonMembership(
            .outside, forIdentifier: "1", onlyIfBeliefPredates: provenAt,
            onlyIfRingMatches: Self.ringA, now: Self.insideAt
        )
        let outcome = await storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfBeliefPredates: insideAt,
            onlyIfRingMatches: Self.ringA, now: Self.insideAt
        )
        return (outcome, storage)
    }

    /// An outside belief from long before says the crossing happened at some point since, not at
    /// the inside fix. The ENTER is still owed and the belief still flips, but the entry is
    /// discovered: dating it to the inside fix would report a guessed `entered_at` and duration.
    @Test
    func recordPolygonMembership_givenStaleOutsideProofOnTheSameRing_expectDiscoveredInsideAndBeliefFlipped() async {
        let (outcome, storage) = await insideAfterOutside(provenAt: Self.insideAt.addingTimeInterval(-3 * 60 * 60))

        #expect(outcome == .discoveredInside)
        #expect(outcome.deliveredTransition == .enter)
        let record = await storage.getPolygonMembership()["1"]
        #expect(record?.membership == .inside)
        #expect(record?.lastChangedAt == Self.insideAt)
    }

    /// The window is inclusive at its bound, as on Android, and closed one step past it.
    @Test
    func recordPolygonMembership_givenOutsideProofAtAndPastTheWindow_expectBoundaryRespected() async {
        let limit = GeofenceConstants.polygonOutsideProofMaxAge

        let atLimit = await insideAfterOutside(provenAt: Self.insideAt.addingTimeInterval(-limit))
        let pastLimit = await insideAfterOutside(provenAt: Self.insideAt.addingTimeInterval(-limit - 0.001))

        #expect(atLimit.outcome == .deliver(.enter))
        #expect(pastLimit.outcome == .discoveredInside)
    }

    /// Proof at the very instant of the inside fix does not show the device outside BEFORE it, so
    /// it brackets no crossing.
    @Test
    func recordPolygonMembership_givenOutsideProofAtTheInsideInstant_expectDiscoveredInside() async {
        let (outcome, _) = await insideAfterOutside(provenAt: Self.insideAt)

        #expect(outcome == .discoveredInside)
    }

    /// An inside write with no evidence time cannot be placed against the proof at all, so it
    /// fails closed rather than borrowing the write time.
    @Test
    func recordPolygonMembership_givenNoInsideEvidenceTime_expectDiscoveredInside() async {
        let (outcome, _) = await insideAfterOutside(provenAt: Self.insideAt.addingTimeInterval(-10), insideAt: nil)

        #expect(outcome == .discoveredInside)
    }

    /// A long-held outside belief that is RE-PROVEN shortly before the arrival is fresh proof: the
    /// confirmation advances the stamp, and the stamp is what the window is measured from.
    @Test
    func recordPolygonMembership_givenOldOutsideReconfirmedWithinTheWindow_expectObservedEnter() async {
        let storage = await makeStorage()
        await storage.setCachedGeofences([polygon(ring: Self.ringA)])
        _ = await storage.recordPolygonMembership(
            .outside, forIdentifier: "1", onlyIfBeliefPredates: Self.insideAt.addingTimeInterval(-3 * 60 * 60),
            onlyIfRingMatches: Self.ringA, now: Self.insideAt
        )
        let confirmed = await storage.recordPolygonMembership(
            .outside, forIdentifier: "1", onlyIfBeliefPredates: Self.insideAt.addingTimeInterval(-30),
            onlyIfRingMatches: Self.ringA, now: Self.insideAt
        )

        let outcome = await storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfBeliefPredates: Self.insideAt,
            onlyIfRingMatches: Self.ringA, now: Self.insideAt
        )

        #expect(confirmed == .suppressedNoChange)
        #expect(outcome == .deliver(.enter))
    }

    /// A stamp ahead of `now` is discarded as evidence, so it proves nothing about the entry —
    /// even though, read literally, it would sit "within" the window of a later clock.
    @Test
    func recordPolygonMembership_givenFutureStampedOutsideRecord_expectDiscoveredInside() async {
        let storage = await makeStorage()
        await storage.setCachedGeofences([polygon(ring: Self.ringA)])
        var state = await storage.loadFromDisk() ?? GeofenceState()
        state.polygonMembership = [
            "1": PolygonMembershipRecord(
                membership: .outside, lastChangedAt: Self.insideAt.addingTimeInterval(60), ring: Self.ringA
            )
        ]
        await storage.saveToDisk(state)

        let outcome = await storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfBeliefPredates: Self.insideAt,
            onlyIfRingMatches: Self.ringA, now: Self.insideAt
        )

        #expect(outcome == .discoveredInside)
    }

    /// A record persisted by an earlier build, decoded from its stored JSON under the literal
    /// `lastChangedAt` key: an old stamp demotes the entry even with a matching ring, and a recent
    /// one still counts, so the upgrade neither invents nor loses an observed crossing.
    @Test(arguments: [(-3 * 60 * 60, false), (-60, true)] as [(TimeInterval, Bool)])
    func recordPolygonMembership_givenLegacyOutsideRecordWithRing_expectOnlyARecentStampObserved(
        offset: TimeInterval, observed: Bool
    ) async throws {
        let storage = await makeStorage()
        await storage.setCachedGeofences([polygon(ring: Self.ringA)])
        let encoder = JSONEncoder()
        let ringJSON = try String(decoding: encoder.encode(Self.ringA), as: UTF8.self)
        let stamp = try String(decoding: encoder.encode(Self.insideAt.addingTimeInterval(offset)), as: UTF8.self)
        let legacyJSON = #"{"membership":"outside","lastChangedAt":\#(stamp),"ring":\#(ringJSON)}"#
        let legacy = try JSONDecoder().decode(PolygonMembershipRecord.self, from: Data(legacyJSON.utf8))
        var state = await storage.loadFromDisk() ?? GeofenceState()
        state.polygonMembership = ["1": legacy]
        await storage.saveToDisk(state)

        let outcome = await storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfBeliefPredates: Self.insideAt,
            onlyIfRingMatches: Self.ringA, now: Self.insideAt
        )

        #expect(outcome == (observed ? .deliver(.enter) : .discoveredInside))
    }

    /// Freshness does not override geometry: recent proof against a replaced ring still proves no
    /// entry into the new one.
    @Test
    func recordPolygonMembership_givenFreshOutsideProofAgainstTheReplacedRing_expectDiscoveredInside() async {
        let storage = await makeStorage()
        await storage.setCachedGeofences([polygon(ring: Self.ringA)])
        _ = await storage.recordPolygonMembership(
            .outside, forIdentifier: "1", onlyIfBeliefPredates: Self.insideAt.addingTimeInterval(-10),
            onlyIfRingMatches: Self.ringA, now: Self.insideAt
        )
        await storage.setCachedGeofences([polygon(ring: Self.ringB)])

        let outcome = await storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfBeliefPredates: Self.insideAt,
            onlyIfRingMatches: Self.ringB, now: Self.insideAt
        )

        #expect(outcome == .discoveredInside)
    }

    /// Freshness does not override ordering either: an inside fix older than the outside proof is
    /// still refused as superseded, not delivered as a crossing.
    @Test
    func recordPolygonMembership_givenInsideEvidenceOlderThanTheOutsideProof_expectSuppressedNewerDecision() async {
        let (outcome, storage) = await insideAfterOutside(
            provenAt: Self.insideAt, insideAt: Self.insideAt.addingTimeInterval(-10)
        )

        #expect(outcome == .suppressedNewerDecision)
        #expect(await storage.getPolygonMembership()["1"]?.membership == .outside)
    }

    @Test
    func recordPolygonMembership_givenTheFenceLeftTheCacheSinceEvaluation_expectSuppressed() async {
        let storage = await makeStorage()

        let outcome = await storage.recordPolygonMembership(
            .inside, forIdentifier: "1", onlyIfRingMatches: Self.ringA
        )

        #expect(outcome == .suppressedGeometryChanged)
    }

    /// No ring means no ring check; the covering exit relies on this and is gated on its circle
    /// instead.
    @Test
    func recordPolygonMembership_givenNoRingSuppliedAndTheRingReplaced_expectTheGeometryCheckSkipped() async {
        let storage = await makeStorage()
        await storage.setCachedGeofences([polygon(ring: Self.ringA)])
        _ = await storage.recordPolygonMembership(.inside, forIdentifier: "1", onlyIfRingMatches: Self.ringA)
        await storage.setCachedGeofences([polygon(ring: Self.ringB)])

        let outcome = await storage.recordPolygonMembership(.outside, forIdentifier: "1")

        #expect(outcome == .deliver(.exit))
    }

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

    /// Control for the test above.
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

    /// An over-cap fence is monitored by `min(radius, cap)`, not its declared radius.
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
