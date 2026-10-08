@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import CoreLocation
import Foundation
import SharedTests
import Testing

/// A completed visit's EXIT duration against the foundation's provenance: the durable identity,
/// legacy visits, unproven candidates, superseding native ENTERs and the first clock reading.
/// Boundaries go through the production resolver, the dwell coordinator, the real tracker and the
/// file outbox; the context store is the real one, written through its setters. Each "process" is
/// a fresh store, tracker, coordinator and resolver over the same files. Delivery fails and a CDP
/// key is set, so every row the tracker writes stays in the outbox to be read.
@Suite("GeofenceExitDurationProvenance", .serialized)
@MainActor
struct GeofenceExitDurationProvenanceTests {
    /// EXIT-only, dwell disabled: its visits exist only to time the EXIT.
    private static let exitOnly = Geofence(
        id: "exit-only", latitude: 0, longitude: 0, radius: 100, name: "exit-only",
        transitionTypes: [.exit], lastUpdated: Date(timeIntervalSince1970: 1)
    )
    /// ENTER, EXIT and a dwell threshold, for the unproven-candidate paths.
    private static let dwellCircle = Geofence(
        id: "dwell-circle", latitude: 0, longitude: 0, radius: 100, name: "dwell-circle",
        transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1),
        dwellThresholdSeconds: 600
    )
    /// Far from the circles; its covering circle's EXIT is the resolver's to judge.
    private static let polygon = Geofence(
        id: "polygon", latitude: 5, longitude: 6, radius: 300, name: "polygon",
        transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1),
        vertices: [
            LocationData(latitude: 4.9992, longitude: 5.9992),
            LocationData(latitude: 4.9992, longitude: 6.0008),
            LocationData(latitude: 5.0008, longitude: 6.0008),
            LocationData(latitude: 5.0008, longitude: 5.9992)
        ]
    )

    // MARK: - Identity

    /// The user changes away and back through the context store's setter, with no profile event
    /// delivered at all. The EXIT that ends the earlier visit is still delivered, but must not time
    /// a stay that spans another identity. A stay entered after the change is timed.
    @Test
    func userChangedAwayAndBackBeforeAnyProfileEventLeavesTheExitUntimed() async throws {
        let files = Files()
        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly)
        let old = try #require(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id))
        files.advance(300)
        process.contextStore.setUserId("user-b")
        process.contextStore.setUserId("user-a")
        files.advance(300)

        await process.crossing(.exit, Self.exitOnly)

        let untimed = try #require(await process.exitRows().last)
        #expect(untimed.userId == "user-a")
        #expect(untimed.visitId == nil)
        #expect(untimed.enteredAt == nil)
        #expect(untimed.visitDurationSeconds == nil)
        #expect(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id) == nil)

        files.advance(60)
        let reentry = files.clock.wall
        await process.crossing(.enter, Self.exitOnly)
        files.advance(90)
        await process.crossing(.exit, Self.exitOnly)
        let rows = await process.exitRows()
        try #require(rows.count == 2)
        #expect(rows[1].visitId != old.visitId)
        #expect(rows[1].enteredAt.map { Int($0.timeIntervalSince1970) } == Int(reentry.timeIntervalSince1970))
        #expect(rows[1].visitDurationSeconds == 90)
    }

    /// The profile callback for an earlier B is delivered late — before or after A's new ENTER.
    /// It decides nothing by its timing: A's new visit, recorded under the identity now in force,
    /// keeps its id, its known entry and its duration.
    @Test(arguments: [true, false])
    func lateProfileEventForAnEarlierChangeKeepsTheNewVisitTimed(deliveredBeforeTheEntry: Bool) async throws {
        let files = Files()
        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly)
        files.advance(60)
        process.contextStore.setUserId("user-b")
        process.contextStore.setUserId("user-a")
        files.advance(30)
        // What the module's ProfileIdentifiedEvent observer runs.
        if deliveredBeforeTheEntry { await process.dwell.identityChanged() }
        let entry = files.clock.wall
        await process.crossing(.enter, Self.exitOnly)
        let visit = try #require(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id))
        if !deliveredBeforeTheEntry { await process.dwell.identityChanged() }
        files.advance(120)

        await process.crossing(.exit, Self.exitOnly)

        let row = try #require(await process.exitRows().last)
        #expect(visit.enteredAt == entry)
        #expect(row.visitId == visit.visitId)
        #expect(row.enteredAt.map { Int($0.timeIntervalSince1970) } == Int(entry.timeIntervalSince1970))
        #expect(row.visitDurationSeconds == 120)
    }

    /// An EXIT is still in flight when a re-entry replaces its visit, then the user changes away
    /// and back before that EXIT reads it. The replaced visit spans the change: the EXIT reports
    /// no duration for it, and the re-entry recorded before the change is not timed either. The
    /// first delivery of the EXIT is the one-receiver-later copy the overlap tests use: received
    /// for another user, it records itself before any await, then is dropped.
    @Test
    func identityChangeWhileAnOverlappingExitIsPendingLeavesItUntimed() async throws {
        let files = Files()
        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly)
        files.advance(60)
        let exitedAt = files.clock.wall
        await process.crossing(.exit, Self.exitOnly, receivedFor: "someone-else")
        files.advance(1)
        await process.crossing(.enter, Self.exitOnly)
        files.advance(1)
        process.contextStore.setUserId("user-b")
        process.contextStore.setUserId("user-a")

        await process.crossing(.exit, Self.exitOnly, at: exitedAt)

        let closed = try #require(await process.exitRows().last)
        #expect(closed.visitDurationSeconds == nil)
        #expect(closed.visitId == nil)
        files.advance(120)
        await process.crossing(.exit, Self.exitOnly)
        let rows = await process.exitRows()
        try #require(rows.count == 2)
        #expect(rows[1].visitDurationSeconds == nil)
    }

    /// The EXIT's facts were fixed before the user changed: the visit completed under A. A change
    /// away and back while the EXIT is being handed to the tracker delivers it as A, with the
    /// duration it carries; a change away to B drops it rather than giving it to B.
    @Test(arguments: [true, false])
    func identityChangeAfterTheExitWasTimedKeepsItsFactsOrDropsIt(backToTheSameUser: Bool) async throws {
        let files = Files()
        let process = await Process(files: files) { contextStore in
            contextStore.setUserId("user-b")
            if backToTheSameUser { contextStore.setUserId("user-a") }
        }
        let entry = files.clock.wall
        await process.crossing(.enter, Self.exitOnly)
        files.advance(75)

        await process.crossing(.exit, Self.exitOnly)

        let rows = await process.exitRows()
        if backToTheSameUser {
            try #require(rows.count == 1)
            #expect(rows[0].userId == "user-a")
            #expect(rows[0].enteredAt.map { Int($0.timeIntervalSince1970) } == Int(entry.timeIntervalSince1970))
            #expect(rows[0].visitDurationSeconds == 75)
        } else {
            #expect(rows.isEmpty)
        }
    }

    // MARK: - Legacy and unproven visits

    /// A visit a build before identity provenance persisted — observed entry and all — names no
    /// identity it was recorded under. Its EXIT ends it, untimed. The next stay, entered by a
    /// native crossing, is timed.
    @Test
    func legacyObservedVisitsExitIsUntimed() async throws {
        let files = Files()
        let process = await Process(files: files)
        let legacy = try await process.saveLegacyVisit(Self.exitOnly, entryObserved: true)
        files.advance(600)

        await process.crossing(.exit, Self.exitOnly)

        let untimed = try #require(await process.exitRows().last)
        #expect(untimed.visitDurationSeconds == nil)
        #expect(untimed.visitId == nil)
        files.advance(60)
        await process.crossing(.enter, Self.exitOnly)
        files.advance(45)
        await process.crossing(.exit, Self.exitOnly)
        let rows = await process.exitRows()
        try #require(rows.count == 2)
        #expect(rows[1].visitId != legacy.visitId)
        #expect(rows[1].visitDurationSeconds == 45)
    }

    /// A legacy unknown-entry candidate waits for proof. Its first fresh inside fix, five hours
    /// later, restarts it there: no DWELL, and its EXIT reports no entry or duration. A native
    /// ENTER after that is a stay of its own, which its EXIT times.
    @Test
    func legacyCandidateProvenLateIsUntimedAndANativeEnterIsTimed() async throws {
        let files = Files()
        let process = await Process(files: files)
        let legacy = try await process.saveLegacyVisit(Self.dwellCircle, entryObserved: false)
        files.advance(5 * 3600)

        await process.dwell.recordInsideEvidence(
            geofence: Self.dwellCircle, at: files.clock.wall, source: "location_evidence"
        )
        let proven = try #require(await process.storage.getDwellVisit(geofenceId: Self.dwellCircle.id))
        #expect(proven.visitId != legacy.visitId)
        #expect(proven.entryObserved == false)
        #expect(await process.rows(.dwell).isEmpty)
        files.advance(120)
        await process.crossing(.exit, Self.dwellCircle)
        let untimed = try #require(await process.exitRows().last)
        #expect(untimed.visitDurationSeconds == nil)
        #expect(untimed.enteredAt == nil)
        #expect(await process.rows(.dwell).isEmpty)

        files.advance(60)
        let entry = files.clock.wall
        await process.crossing(.enter, Self.dwellCircle)
        files.advance(90)
        await process.crossing(.exit, Self.dwellCircle)
        let rows = await process.exitRows()
        try #require(rows.count == 2)
        #expect(rows[1].enteredAt.map { Int($0.timeIntervalSince1970) } == Int(entry.timeIntervalSince1970))
        #expect(rows[1].visitDurationSeconds == 90)
        process.dwell.cancelEvidence(for: Self.dwellCircle.id)
    }

    /// A legacy visit whose dwell was already emitted, or reserved, keeps its id and facts: it is
    /// never qualified again and no DWELL row is added. Its EXIT is untimed.
    @Test(arguments: [true, false])
    func legacyEmittedOrReservedVisitKeepsItsFactsAndItsExitIsUntimed(emitted: Bool) async throws {
        let files = Files()
        let process = await Process(files: files)
        let reservation = emitted ? nil : GeofenceDwellReservation(
            occurredAtEpochMilliseconds: Int64(files.clock.wall.timeIntervalSince1970 * 1000),
            enteredAtEpochMilliseconds: nil, durationSeconds: nil, thresholdSeconds: 600,
            detectionSource: "location_evidence"
        )
        let legacy = try await process.saveLegacyVisit(
            Self.dwellCircle, entryObserved: false, emitted: emitted, reservation: reservation
        )
        let stored = try #require(await process.storage.getDwellVisit(geofenceId: Self.dwellCircle.id))
        #expect(stored.visitId == legacy.visitId)
        #expect(stored.emitted == emitted)
        #expect(stored.dwellReservation == reservation)
        #expect(stored.awaitsPresenceProof == false)
        files.advance(300)

        await process.crossing(.exit, Self.dwellCircle)

        let row = try #require(await process.exitRows().last)
        #expect(row.visitDurationSeconds == nil)
        #expect(row.visitId == nil)
        #expect(await process.rows(.dwell).isEmpty)
        process.dwell.cancelEvidence(for: Self.dwellCircle.id)
    }

    // MARK: - Superseding native ENTER

    /// The EXIT that ended a stay was lost. A native ENTER five hours later is a new crossing: the
    /// old visit ends there, and the next EXIT times only the new stay.
    @Test
    func laterNativeEnterAfterALostExitTimesOnlyTheNewStay() async throws {
        let files = Files()
        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly)
        let old = try #require(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id))
        files.advance(5 * 3600)
        let reentry = files.clock.wall

        await process.crossing(.enter, Self.exitOnly)
        files.advance(90)
        await process.crossing(.exit, Self.exitOnly)

        let row = try #require(await process.exitRows().last)
        #expect(row.visitId != old.visitId)
        #expect(row.enteredAt.map { Int($0.timeIntervalSince1970) } == Int(reentry.timeIntervalSince1970))
        #expect(row.visitDurationSeconds == 90)
    }

    // MARK: - Native ENTERs that are not crossings

    /// A stay whose dwell is emitted gets a native ENTER an hour in. A correction — the OS answering
    /// a state it assumed, or a heal — says the device is inside, not that it arrived again: the
    /// visit, its id and its entry stand, and its EXIT is timed from the original entry. A crossing
    /// is a new arrival: the stay ends there, and the EXIT times only the new one.
    @Test(arguments: [false, true])
    func enterDuringAnEmittedStayEndsItOnlyWhenACrossing(crossing: Bool) async throws {
        let files = Files()
        let process = await Process(files: files)
        let entry = files.clock.wall
        await process.crossing(.enter, Self.dwellCircle)
        let visit = try #require(await process.storage.getDwellVisit(geofenceId: Self.dwellCircle.id))
        files.advance(600)
        await process.dwell.recordInsideEvidence(geofence: Self.dwellCircle, at: files.clock.wall, source: "location_evidence")
        try #require(await process.rows(.dwell).count == 1)
        files.advance(3000)
        let enteredAgain = files.clock.wall

        await process.crossing(.enter, Self.dwellCircle, crossingObserved: crossing)
        files.advance(300)
        await process.crossing(.exit, Self.dwellCircle)

        let row = try #require(await process.exitRows().last)
        let reported = crossing ? enteredAgain : entry
        #expect((row.visitId == visit.visitId) == !crossing)
        #expect(row.enteredAt.map { Int($0.timeIntervalSince1970) } == Int(reported.timeIntervalSince1970))
        #expect(row.visitDurationSeconds == (crossing ? 300 : 3900))
        #expect(await process.rows(.dwell).count == 1)
        process.dwell.cancelEvidence(for: Self.dwellCircle.id)
    }

    /// A stay whose dwell was reserved but never queued — an outbox write that failed — gets a
    /// correction ENTER. The reservation stays exactly as it was, and the EXIT times the same
    /// physical stay from its original entry.
    @Test
    func correctionEnterLeavesAReservedStayAndItsExitDuration() async throws {
        let files = Files()
        let process = await Process(files: files)
        let entry = files.clock.wall
        await process.crossing(.enter, Self.dwellCircle)
        let visit = try #require(await process.storage.getDwellVisit(geofenceId: Self.dwellCircle.id))
        files.advance(600)
        let reservation = GeofenceDwellReservation(
            occurredAtEpochMilliseconds: Int64(files.clock.wall.timeIntervalSince1970 * 1000),
            enteredAtEpochMilliseconds: Int64(entry.timeIntervalSince1970 * 1000), durationSeconds: 600,
            thresholdSeconds: 600, detectionSource: "location_evidence"
        )
        #expect(
            await process.storage.reserveDwellEmission(reservation, for: visit, geofenceId: Self.dwellCircle.id)
                == .reserved(reservation)
        )
        files.advance(3000)

        await process.crossing(.enter, Self.dwellCircle, crossingObserved: false)
        let kept = try #require(await process.storage.getDwellVisit(geofenceId: Self.dwellCircle.id))
        files.advance(300)
        await process.crossing(.exit, Self.dwellCircle)

        #expect(kept.visitId == visit.visitId)
        #expect(kept.dwellReservation == reservation)
        #expect(kept.emitted == false)
        let row = try #require(await process.exitRows().last)
        #expect(row.visitId == visit.visitId)
        #expect(row.enteredAt.map { Int($0.timeIntervalSince1970) } == Int(entry.timeIntervalSince1970))
        #expect(row.visitDurationSeconds == 3900)
        process.dwell.cancelEvidence(for: Self.dwellCircle.id)
    }

    /// On an EXIT-only fence no stay ever qualifies a dwell, so a correction ENTER restarts it:
    /// nothing watched the time the OS assumed the device outside. The restarted visit has no known
    /// entry, so its EXIT is untimed rather than timed across that time.
    @Test
    func correctionEnterOnAnUnqualifiedStayLeavesItsExitUntimed() async throws {
        let files = Files()
        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly)
        let visit = try #require(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id))
        files.advance(600)

        await process.crossing(.enter, Self.exitOnly, crossingObserved: false)
        let restarted = try #require(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id))
        files.advance(60)
        await process.crossing(.exit, Self.exitOnly)

        #expect(restarted.visitId != visit.visitId)
        #expect(restarted.entryObserved == false)
        let row = try #require(await process.exitRows().last)
        #expect(row.visitDurationSeconds == nil)
        #expect(row.visitId == nil)
    }

    /// Two native ENTERs, a crossing and a correction, are noted — as the binder notes them, in the
    /// OS callback — on either side of an EXIT that ended the stay, before any of their routing
    /// tasks runs. The ENTER before that EXIT says the stay had already ended earlier, at an EXIT the
    /// SDK never saw: the EXIT is not the visit's, so it must not report the visit's entry or
    /// duration, whichever kind of ENTER is the later one.
    @Test(arguments: [true, false])
    func enterBeforeTheExitStopsItTimingTheVisitWhateverCameAfter(crossingFirst: Bool) async throws {
        let files = Files()
        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly)
        files.advance(100)
        process.dwell.noteEnter(geofenceId: Self.exitOnly.id, occurredAt: files.clock.wall, crossing: crossingFirst)
        files.advance(100)
        let exitedAt = files.clock.wall
        await process.crossing(.exit, Self.exitOnly, receivedFor: "someone-else")
        files.advance(100)
        process.dwell.noteEnter(geofenceId: Self.exitOnly.id, occurredAt: files.clock.wall, crossing: !crossingFirst)

        await process.crossing(.exit, Self.exitOnly, at: exitedAt)

        let row = try #require(await process.exitRows().last)
        #expect(row.visitDurationSeconds == nil)
        #expect(row.enteredAt == nil)
        #expect(row.visitId == nil)
    }

    /// The EXIT that ended a stay is still in flight when a native ENTER after it — a crossing, or
    /// a correction — replaces the visit. That EXIT still times the old visit, and only it; the new
    /// stay carries its own provenance: a crossing's EXIT is timed from it, a correction's is not.
    @Test(arguments: [true, false])
    func reentryAfterAPendingExitLeavesItTimingTheOldVisitOnly(crossing: Bool) async throws {
        let files = Files()
        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly)
        let first = try #require(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id))
        files.advance(60)
        let exitedAt = files.clock.wall
        await process.crossing(.exit, Self.exitOnly, receivedFor: "someone-else")
        files.advance(1)
        let reentry = files.clock.wall
        await process.crossing(.enter, Self.exitOnly, crossingObserved: crossing)
        let newer = try #require(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id))

        await process.crossing(.exit, Self.exitOnly, at: exitedAt)
        let closed = try #require(await process.exitRows().last)
        files.advance(120)
        await process.crossing(.exit, Self.exitOnly)

        #expect(closed.visitId == first.visitId)
        #expect(closed.visitDurationSeconds == 60)
        #expect(newer.visitId != first.visitId)
        let rows = await process.exitRows()
        try #require(rows.count == 2)
        #expect(rows[1].visitId == (crossing ? newer.visitId : nil))
        #expect(rows[1].enteredAt.map { Int($0.timeIntervalSince1970) } == (crossing ? Int(reentry.timeIntervalSince1970) : nil))
        #expect(rows[1].visitDurationSeconds == (crossing ? 120 : nil))
    }

    // MARK: - ENTERs noted before an EXIT, then hidden by later ones

    /// The reviewed trace, on one real EXIT call. An ENTER of the stay's fence is noted — as the
    /// binder notes it in the OS callback — while its routing task has not run: the stay ended at an
    /// EXIT the SDK never saw. The EXIT that ends the next stay is delivered; while it is suspended
    /// at its storage read, after recording itself, a later ENTER of the same kind is noted and
    /// replaces the earlier one in its slot. The EXIT must not time the old visit across the EXIT it
    /// never saw: its provenance is what it knew when it was first recorded, which later callbacks
    /// cannot erase. Crossings, and corrections of an EXIT-only stay that never qualifies.
    @Test(arguments: [true, false])
    func enterNotedBeforeTheExitStillLeavesItUntimedAfterALaterOneHidesIt(crossing: Bool) async throws {
        let files = Files()
        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly)
        files.advance(100)
        process.dwell.noteEnter(geofenceId: Self.exitOnly.id, occurredAt: files.clock.wall, crossing: crossing)
        files.advance(100)

        try await process.exitInterleaved(Self.exitOnly) {
            files.advance(100)
            process.dwell.noteEnter(geofenceId: Self.exitOnly.id, occurredAt: files.clock.wall, crossing: crossing)
        }

        let row = try #require(await process.exitRows().last)
        #expect(row.visitDurationSeconds == nil)
        #expect(row.enteredAt == nil)
        #expect(row.visitId == nil)
    }

    /// Control. The OS delivered the EXIT, then the re-entry; the re-entry's callback notes its
    /// ENTER before the EXIT's routing task records the EXIT. That ENTER came after the EXIT: it is
    /// the re-entry, not a sign of an earlier missed EXIT, so the EXIT still times the old visit,
    /// and the re-entry's own EXIT times the new stay.
    @Test
    func reentryNotedBeforeTheExitIsRecordedStillLetsItTimeTheVisit() async throws {
        let files = Files()
        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly)
        let first = try #require(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id))
        files.advance(60)
        let exitedAt = files.clock.wall
        files.advance(1)
        let reentry = files.clock.wall

        let exit = Task { @MainActor in await process.crossing(.exit, Self.exitOnly, at: exitedAt) }
        process.dwell.noteEnter(geofenceId: Self.exitOnly.id, occurredAt: reentry, crossing: true)
        await exit.value
        let closed = try #require(await process.exitRows().last)
        await process.crossing(.enter, Self.exitOnly, at: reentry)
        files.advance(120)
        await process.crossing(.exit, Self.exitOnly)

        #expect(closed.visitId == first.visitId)
        #expect(closed.visitDurationSeconds == 60)
        let rows = await process.exitRows()
        try #require(rows.count == 2)
        #expect(rows[1].visitId != first.visitId)
        #expect(rows[1].enteredAt.map { Int($0.timeIntervalSince1970) } == Int(reentry.timeIntervalSince1970))
        #expect(rows[1].visitDurationSeconds == 120)
    }

    /// The binder notes the EXIT's callback, then the re-entry's, before either routing task runs.
    /// Its handler is not actor-isolated, so the two tasks reach the main actor in no fixed order:
    /// here the re-entry is routed first and replaces the visit before the EXIT has recorded
    /// itself. That ENTER came after the EXIT, so the EXIT still reports the visit it ended, and
    /// the re-entry's stay is left stored.
    @Test
    func reentryRoutedBeforeItsNotedExitStillLetsTheExitTimeTheVisit() async throws {
        let files = Files()
        let process = await Process(files: files)
        let id = Self.exitOnly.id
        await process.crossing(.enter, Self.exitOnly)
        let first = try #require(await process.storage.getDwellVisit(geofenceId: id))
        files.advance(60)
        let exitedAt = files.clock.wall
        files.advance(1)
        let reentry = files.clock.wall
        process.dwell.noteExitCallback(geofenceId: id, occurredAt: exitedAt)
        process.dwell.noteEnter(geofenceId: id, occurredAt: reentry, crossing: true)

        await process.crossing(.enter, Self.exitOnly, at: reentry)
        let reentered = try #require(await process.storage.getDwellVisit(geofenceId: id))
        await process.crossing(.exit, Self.exitOnly, at: exitedAt)
        process.dwell.exitCallbackRouted(geofenceId: id, occurredAt: exitedAt)

        let row = try #require(await process.exitRows().last)
        #expect(row.visitId == first.visitId)
        #expect(row.visitDurationSeconds == 60)
        #expect(row.enteredAt.map { Int($0.timeIntervalSince1970) } == Int(first.enteredAt.timeIntervalSince1970))
        #expect(reentered.visitId != first.visitId)
        #expect(await process.storage.getDwellVisit(geofenceId: id)?.visitId == reentered.visitId)
        #expect(process.dwell.exitDuration.visitsEndedByPendingExit[id] == nil)
    }

    /// Control for that order after a burst: an ENTER at 10 is noted before the EXIT at 20 (the
    /// stay's own EXIT was lost), then an ENTER at 30, which is routed before the EXIT. Keeping the
    /// old visit for the noted EXIT must not let it time the visit across the EXIT the SDK never
    /// saw: what the EXIT knew when it was noted still leaves it untimed. Crossings and corrections.
    @Test(arguments: [true, false])
    func burstReentryRoutedBeforeTheNotedExitStillLeavesItUntimed(crossing: Bool) async throws {
        let files = Files()
        let process = await Process(files: files)
        let id = Self.exitOnly.id
        await process.crossing(.enter, Self.exitOnly)
        let first = try #require(await process.storage.getDwellVisit(geofenceId: id))
        files.advance(10)
        let enteredAt10 = files.clock.wall
        files.advance(10)
        let exitedAt20 = files.clock.wall
        files.advance(10)
        let enteredAt30 = files.clock.wall
        process.dwell.noteEnter(geofenceId: id, occurredAt: enteredAt10, crossing: crossing)
        process.dwell.noteExitCallback(geofenceId: id, occurredAt: exitedAt20)
        process.dwell.noteEnter(geofenceId: id, occurredAt: enteredAt30, crossing: crossing)

        await process.crossing(.enter, Self.exitOnly, at: enteredAt30, crossingObserved: crossing)
        let reentered = try #require(await process.storage.getDwellVisit(geofenceId: id))
        await process.crossing(.exit, Self.exitOnly, at: exitedAt20)
        process.dwell.exitCallbackRouted(geofenceId: id, occurredAt: exitedAt20)

        let row = try #require(await process.exitRows().last)
        #expect(row.visitId == nil)
        #expect(row.enteredAt == nil)
        #expect(row.visitDurationSeconds == nil)
        #expect(reentered.visitId != first.visitId)
        #expect(await process.storage.getDwellVisit(geofenceId: id)?.visitId == reentered.visitId)
    }

    /// The visit is remembered for a noted EXIT whose routing then records none: it was raised by a
    /// circle since replaced. Once its callback ends, nothing it left provisionally outlives it —
    /// the remembered visit, the ENTERs it knew, its routing count — so a later copy of the same
    /// date cannot time the visit either.
    @Test
    func noteExitRoutedWithoutRecordingItForgetsTheVisitRememberedForIt() async throws {
        let files = Files()
        let process = await Process(files: files)
        let id = Self.exitOnly.id
        await process.crossing(.enter, Self.exitOnly)
        files.advance(60)
        let exitedAt = files.clock.wall
        files.advance(1)
        let reentry = files.clock.wall
        process.dwell.noteExitCallback(geofenceId: id, occurredAt: exitedAt)
        process.dwell.noteEnter(geofenceId: id, occurredAt: reentry, crossing: true)
        await process.crossing(.enter, Self.exitOnly, at: reentry)
        let reentered = try #require(await process.storage.getDwellVisit(geofenceId: id))
        try #require(process.dwell.exitDuration.visitsEndedByPendingExit[id]?.exitDates == [exitedAt])

        await process.resolver.handleTransition(
            identifier: id, transition: .exit, occurredAt: exitedAt, eventCircle: .expired, receivedForUserId: "user-a"
        )
        process.dwell.exitCallbackRouted(geofenceId: id, occurredAt: exitedAt)

        #expect(process.dwell.exitDuration.visitsEndedByPendingExit[id] == nil)
        #expect(process.dwell.exitDuration.entersKnownAtExit[id] == nil)
        #expect(process.dwell.exitDuration.routingsInFlight[id] == nil)
        #expect(process.dwell.pendingExitCallbacks[id] == nil)
        #expect(process.dwell.exitMarks[id]?.isEmpty ?? true)
        await process.crossing(.exit, Self.exitOnly, at: exitedAt)
        let rows = await process.exitRows()
        #expect(!rows.isEmpty)
        #expect(rows.allSatisfy { $0.visitId == nil && $0.visitDurationSeconds == nil })
        #expect(await process.storage.getDwellVisit(geofenceId: id)?.visitId == reentered.visitId)
    }

    /// A delayed copy of the EXIT — the same OS date — is read after a later ENTER replaced the
    /// earlier one it was first recorded with. The copy keeps the EXIT's first provenance, so it
    /// cannot time the old visit either. The first delivery is received for another user: an
    /// internal seam that records the EXIT before any await, as a suspended EXIT does; it is not
    /// device or callback acceptance.
    @Test
    func delayedCopyOfTheExitKeepsWhatItKnewWhenFirstRecorded() async throws {
        let files = Files()
        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly)
        files.advance(100)
        process.dwell.noteEnter(geofenceId: Self.exitOnly.id, occurredAt: files.clock.wall, crossing: true)
        files.advance(100)
        let exitedAt = files.clock.wall
        await process.crossing(.exit, Self.exitOnly, receivedFor: "someone-else")
        files.advance(100)
        process.dwell.noteEnter(geofenceId: Self.exitOnly.id, occurredAt: files.clock.wall, crossing: true)

        await process.crossing(.exit, Self.exitOnly, at: exitedAt)

        let row = try #require(await process.exitRows().last)
        #expect(row.visitDurationSeconds == nil)
        #expect(row.visitId == nil)
    }

    /// Control. With nothing noted before the EXIT, its delayed copy after a real re-entry still
    /// times the old visit once — the remembered visit is consumed — and leaves the re-entry alone.
    /// The first delivery uses the same internal seam as above.
    @Test
    func delayedCopyAfterARealReentryTimesTheOldVisitOnce() async throws {
        let files = Files()
        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly)
        let first = try #require(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id))
        files.advance(60)
        let exitedAt = files.clock.wall
        await process.crossing(.exit, Self.exitOnly, receivedFor: "someone-else")
        files.advance(1)
        await process.crossing(.enter, Self.exitOnly)
        let newer = try #require(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id))

        await process.crossing(.exit, Self.exitOnly, at: exitedAt)
        await process.crossing(.exit, Self.exitOnly, at: exitedAt)

        let rows = await process.exitRows()
        try #require(rows.count == 2)
        #expect(rows[0].visitId == first.visitId)
        #expect(rows[0].visitDurationSeconds == 60)
        #expect(rows[1].visitDurationSeconds == nil)
        #expect(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id)?.visitId == newer.visitId)
    }

    /// Control. A correction noted before the EXIT says the device was inside, not that it arrived
    /// again: it cannot end an emitted or reserved stay, so it does not stop that stay's EXIT timing
    /// it from its original entry.
    @Test(arguments: [true, false])
    func correctionNotedBeforeTheExitLeavesAQualifiedStayTimed(emitted: Bool) async throws {
        let files = Files()
        let process = await Process(files: files)
        let entry = files.clock.wall
        await process.crossing(.enter, Self.dwellCircle)
        let visit = try #require(await process.storage.getDwellVisit(geofenceId: Self.dwellCircle.id))
        files.advance(600)
        if emitted {
            await process.dwell.recordInsideEvidence(geofence: Self.dwellCircle, at: files.clock.wall, source: "location_evidence")
            try #require(await process.rows(.dwell).count == 1)
        } else {
            let reservation = GeofenceDwellReservation(
                occurredAtEpochMilliseconds: Int64(files.clock.wall.timeIntervalSince1970 * 1000),
                enteredAtEpochMilliseconds: Int64(entry.timeIntervalSince1970 * 1000), durationSeconds: 600,
                thresholdSeconds: 600, detectionSource: "location_evidence"
            )
            try #require(
                await process.storage.reserveDwellEmission(reservation, for: visit, geofenceId: Self.dwellCircle.id)
                    == .reserved(reservation)
            )
        }
        files.advance(100)
        process.dwell.noteEnter(geofenceId: Self.dwellCircle.id, occurredAt: files.clock.wall, crossing: false)
        files.advance(100)

        try await process.exitInterleaved(Self.dwellCircle) {
            process.dwell.noteEnter(geofenceId: Self.dwellCircle.id, occurredAt: files.clock.wall, crossing: false)
        }

        let row = try #require(await process.exitRows().last)
        #expect(row.visitId == visit.visitId)
        #expect(row.enteredAt.map { Int($0.timeIntervalSince1970) } == Int(entry.timeIntervalSince1970))
        #expect(row.visitDurationSeconds == 800)
        process.dwell.cancelEvidence(for: Self.dwellCircle.id)
    }

    /// Across a wall-clock step, nothing orders the ENTER noted before the EXIT against it, so the
    /// EXIT reports no duration, as before.
    @Test
    func enterNotedBeforeTheExitAcrossAClockStepLeavesItUntimed() async throws {
        let files = Files()
        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly)
        files.advance(100)
        process.dwell.noteEnter(geofenceId: Self.exitOnly.id, occurredAt: files.clock.wall, crossing: true)
        files.clock.stepWall(3600)
        files.advance(100)

        try await process.exitInterleaved(Self.exitOnly) {
            files.advance(100)
            process.dwell.noteEnter(geofenceId: Self.exitOnly.id, occurredAt: files.clock.wall, crossing: true)
        }

        let row = try #require(await process.exitRows().last)
        #expect(row.visitDurationSeconds == nil)
    }

    /// The stored EXIT context, not only the remembered one. A crossing noted before the EXIT ended
    /// the stay; the slot is then replaced by an ENTER dated before the visit, which supersedes
    /// nothing, so the visit is still stored when the EXIT reads it. Internal chronology only: no
    /// producer delivers that stale ENTER (CLMonitor refuses a date at or before its last event, and
    /// the classic monitor dates events at receipt); it pins the stored path to the same rule.
    @Test
    func storedVisitIsNotTimedByAnExitThatKnewItHadEnded() async throws {
        let files = Files()
        let process = await Process(files: files)
        let entry = files.clock.wall
        await process.crossing(.enter, Self.exitOnly)
        files.advance(100)
        process.dwell.noteEnter(geofenceId: Self.exitOnly.id, occurredAt: files.clock.wall, crossing: true)
        files.advance(100)

        try await process.exitInterleaved(Self.exitOnly) {
            process.dwell.noteEnter(
                geofenceId: Self.exitOnly.id, occurredAt: entry.addingTimeInterval(-100), crossing: true
            )
        }

        let row = try #require(await process.exitRows().last)
        #expect(row.visitDurationSeconds == nil)
        #expect(row.visitId == nil)
        #expect(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id) == nil)
    }

    /// The reviewed burst, in the order the binder sees it. The classic monitor drains buffered
    /// region events in one main-actor turn, so the callbacks for an ENTER at 10 (the stay's EXIT
    /// was lost), the next stay's EXIT at 20 and an ENTER at 30 all run before any routing task:
    /// the ENTER at 30 replaces the one at 10 in its slot before the EXIT's routing task records it.
    /// The EXIT at 20 must not time the old visit across the EXIT the SDK missed. Then the deferred
    /// routing tasks run in OS order: the ENTER at 10 is refused (the EXIT overtakes it), and the
    /// stay entered at 30 is the one the EXIT at 40 reports — timed after a crossing, untimed after
    /// a correction. Internal chronology: the two synchronous calls are the ones the binder makes
    /// in each OS callback; the real binder's own schedule is the next test.
    @Test(arguments: [true, false])
    func burstEnterExitEnterLeavesTheExitUntimedAndReportsOnlyTheNextStay(crossing: Bool) async throws {
        let files = Files()
        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly)
        let first = try #require(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id))
        files.advance(10)
        let enteredAt10 = files.clock.wall
        files.advance(10)
        let exitedAt20 = files.clock.wall
        files.advance(10)
        let enteredAt30 = files.clock.wall
        process.dwell.noteEnter(geofenceId: Self.exitOnly.id, occurredAt: enteredAt10, crossing: crossing)
        process.dwell.noteExitCallback(geofenceId: Self.exitOnly.id, occurredAt: exitedAt20)
        process.dwell.noteEnter(geofenceId: Self.exitOnly.id, occurredAt: enteredAt30, crossing: crossing)

        await process.crossing(.exit, Self.exitOnly, at: exitedAt20)
        let untimed = try #require(await process.exitRows().last)
        await process.crossing(.enter, Self.exitOnly, at: enteredAt10, crossingObserved: crossing)
        await process.crossing(.enter, Self.exitOnly, at: enteredAt30, crossingObserved: crossing)
        files.advance(10)
        await process.crossing(.exit, Self.exitOnly)

        #expect(untimed.visitId == nil)
        #expect(untimed.enteredAt == nil)
        #expect(untimed.visitDurationSeconds == nil)
        let rows = await process.exitRows()
        try #require(rows.count == 2)
        #expect(rows[1].visitId != first.visitId)
        #expect(rows[1].visitDurationSeconds == (crossing ? 10 : nil))
        #expect(rows[1].enteredAt.map { Int($0.timeIntervalSince1970) } == (crossing ? Int(enteredAt30.timeIntervalSince1970) : nil))
    }

    /// Control, in the binder's order: the EXIT's callback, then the re-entry's, both before any
    /// routing task. The re-entry came after the EXIT, so the EXIT still times the old visit.
    @Test
    func binderOrderedReentryAfterTheExitStillLetsItTimeTheVisit() async throws {
        let files = Files()
        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly)
        let first = try #require(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id))
        files.advance(20)
        let exitedAt = files.clock.wall
        files.advance(10)
        process.dwell.noteExitCallback(geofenceId: Self.exitOnly.id, occurredAt: exitedAt)
        process.dwell.noteEnter(geofenceId: Self.exitOnly.id, occurredAt: files.clock.wall, crossing: true)

        await process.crossing(.exit, Self.exitOnly, at: exitedAt)

        let row = try #require(await process.exitRows().last)
        #expect(row.visitId == first.visitId)
        #expect(row.visitDurationSeconds == 20)
    }

    /// The same burst through the real GeofenceMonitorBinder, bound to a mock monitor whose three
    /// callbacks run in one main-actor turn, as the classic drain runs them. The routing tasks,
    /// re-arms and storage hops then run in whatever order the executor picks; whatever it is, no
    /// EXIT row may carry the old visit, which ended at an EXIT the SDK never saw. When the ENTER
    /// at 10 is routed before the EXIT, it opens the stay that EXIT does end, timed at no more than
    /// its 10 s.
    @Test
    func realBinderBurstNeverTimesTheOldVisitAcrossTheMissedExit() async throws {
        let files = Files()
        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly)
        let first = try #require(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id))
        let monitor = process.boundMonitor()
        let start = files.clock.wall
        files.advance(30)

        for (offset, transition) in [(10.0, GeofenceTransition.enter), (20, .exit), (30, .enter)] {
            monitor.simulateTransition(
                identifier: Self.exitOnly.id, transition: transition, location: nil,
                occurredAt: start.addingTimeInterval(offset)
            )
        }
        await settleQuietly(0.5)

        let rows = await process.exitRows()
        try #require(rows.count == 1)
        #expect(rows.allSatisfy { $0.visitId != first.visitId })
        #expect(rows.allSatisfy { ($0.visitDurationSeconds ?? 0) <= 10 })
        withExtendedLifetime(monitor) {}
    }

    /// What each EXIT knew is kept only as long as its EXIT's mark, or a visit remembered for it:
    /// on a steady clock each later EXIT subsumes the earlier mark, so one record per fence remains,
    /// however many EXITs pass, with no time cutoff.
    @Test
    func exitProvenanceLivesOnlyAsLongAsItsExitMark() async throws {
        let files = Files()
        let process = await Process(files: files)
        for _ in 0 ..< 5 {
            await process.crossing(.enter, Self.exitOnly)
            files.advance(60)
            process.dwell.noteEnter(geofenceId: Self.exitOnly.id, occurredAt: files.clock.wall, crossing: true)
            files.advance(60)
            await process.crossing(.exit, Self.exitOnly)
        }

        let marks = try #require(process.dwell.exitMarks[Self.exitOnly.id])
        let known = try #require(process.dwell.exitDuration.entersKnownAtExit[Self.exitOnly.id])
        #expect(marks.count == 1)
        #expect(Set(known.keys) == Set(marks.map(\.date)))
    }

    // MARK: - EXIT callbacks still being routed

    /// One classic drain delivers ENTER 10, EXIT 20, ENTER 30, EXIT 40 and ENTER 50 to the binder
    /// before any routing task runs. EXIT 20's callback knew of the ENTER at 10, which shows the
    /// stay ended at an EXIT the SDK never saw. EXIT 40's callback arrives while EXIT 20 is still
    /// being routed: it must not discard what EXIT 20 knew, or EXIT 20, routed next, learns only the
    /// ENTERs at 30 and 50 and times the old visit across the missed EXIT. Same-kind crossings,
    /// same-kind corrections of an EXIT-only stay that never qualifies, and mixed kinds. Internal
    /// chronology: the five synchronous calls are those the binder makes in each OS callback; the
    /// real binder's own schedule is the next test.
    @Test(arguments: [[true, true, true], [false, false, false], [true, false, true]])
    func fiveCallbackBurstLeavesTheFirstExitUntimed(crossings: [Bool]) async throws {
        let files = Files()
        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly)
        let first = try #require(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id))
        let start = files.clock.wall
        files.advance(60)
        process.dwell.noteEnter(geofenceId: Self.exitOnly.id, occurredAt: start.addingTimeInterval(10), crossing: crossings[0])
        process.dwell.noteExitCallback(geofenceId: Self.exitOnly.id, occurredAt: start.addingTimeInterval(20))
        process.dwell.noteEnter(geofenceId: Self.exitOnly.id, occurredAt: start.addingTimeInterval(30), crossing: crossings[1])
        process.dwell.noteExitCallback(geofenceId: Self.exitOnly.id, occurredAt: start.addingTimeInterval(40))
        process.dwell.noteEnter(geofenceId: Self.exitOnly.id, occurredAt: start.addingTimeInterval(50), crossing: crossings[2])

        await process.crossing(.exit, Self.exitOnly, at: start.addingTimeInterval(20))

        let row = try #require(await process.exitRows().last)
        #expect(row.visitId == nil)
        #expect(row.visitId != first.visitId)
        #expect(row.enteredAt == nil)
        #expect(row.visitDurationSeconds == nil)
    }

    /// The same five callbacks through the real GeofenceMonitorBinder, in one main-actor turn, then
    /// the routing tasks, re-arms and storage hops in whatever order the executor picks. No EXIT
    /// row may carry the old visit, and none may report more than the 10 s any later stay can span.
    @Test
    func realBinderFiveCallbackBurstNeverTimesTheOldVisit() async throws {
        let files = Files()
        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly)
        let first = try #require(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id))
        let monitor = process.boundMonitor()
        let start = files.clock.wall
        files.advance(60)

        let burst: [(TimeInterval, GeofenceTransition)] = [(10, .enter), (20, .exit), (30, .enter), (40, .exit), (50, .enter)]
        for (offset, transition) in burst {
            monitor.simulateTransition(
                identifier: Self.exitOnly.id, transition: transition, location: nil,
                occurredAt: start.addingTimeInterval(offset)
            )
        }
        await settleQuietly(0.5)

        let rows = await process.exitRows()
        try #require(rows.count == 2)
        #expect(rows.allSatisfy { $0.visitId != first.visitId })
        #expect(rows.allSatisfy { ($0.visitDurationSeconds ?? 0) <= 10 })
        #expect(
            process.dwell.exitDuration.entersKnownAtExit[Self.exitOnly.id].map { Set($0.keys) }
                == Set((process.dwell.exitMarks[Self.exitOnly.id] ?? []).map(\.date))
        )
        withExtendedLifetime(monitor) {}
    }

    /// EXIT callbacks the resolver never turns into a dwell EXIT — a polygon's covering circle when
    /// the polygon decides nothing, and a fence no longer cached — leave no exit mark and no
    /// provenance once their routing has finished: nothing accumulates, and no polygon visit is
    /// ended by a raw covering-circle EXIT.
    @Test
    func exitCallbacksTheResolverSuppressesLeaveNothingBehind() async throws {
        let files = Files()
        let process = await Process(files: files)
        let monitor = process.boundMonitor()

        for offset in 1 ... 3 {
            files.advance(10)
            for identifier in [Self.polygon.id, "uncached-fence"] {
                monitor.simulateTransition(
                    identifier: identifier, transition: .exit, location: nil, occurredAt: files.clock.wall.addingTimeInterval(-Double(offset))
                )
            }
        }
        await settleQuietly(0.5)

        for identifier in [Self.polygon.id, "uncached-fence"] {
            #expect(process.dwell.exitMarks[identifier]?.isEmpty ?? true)
            #expect(process.dwell.exitDuration.entersKnownAtExit[identifier]?.isEmpty ?? true)
            #expect(process.dwell.pendingExitCallbacks[identifier]?.isEmpty ?? true)
        }
        #expect(await process.exitRows().allSatisfy { $0.visitDurationSeconds == nil })
        withExtendedLifetime(monitor) {}
    }

    // MARK: - Ambiguous boots

    /// A stay whose dwell is emitted, or reserved, survives into a process that cannot prove it is
    /// on the same boot: the wall clock was set forward or back (and `kern.boottime` with it), or
    /// the boot time is unreadable. The visit stays as the marker of its dwell, with its id and its
    /// reservation, but nothing is measured across the boot: its EXIT reports no entry or duration.
    @Test(arguments: [0, 1, 2], [true, false])
    func qualifiedStayAcrossAnAmbiguousBootKeepsItsFactsAndItsExitIsUntimed(boot: Int, emitted: Bool) async throws {
        let files = Files()
        var process = await Process(files: files)
        let visit = try await process.qualifiedDwellCircleStay(emitted: emitted)
        switch boot {
        case 0: files.stepWallAndBoot(3600)
        case 1: files.stepWallAndBoot(-3600)
        default: files.bootTimeUnreadable()
        }
        files.advance(60)

        process = await Process(files: files)
        await process.dwell.revalidateVisits()
        let kept = try #require(await process.storage.getDwellVisit(geofenceId: Self.dwellCircle.id))
        await process.crossing(.exit, Self.dwellCircle)

        #expect(kept.visitId == visit.visitId)
        #expect(kept.emitted == visit.emitted)
        #expect(kept.dwellReservation == visit.dwellReservation)
        let row = try #require(await process.exitRows().last)
        #expect(row.visitId == nil)
        #expect(row.enteredAt == nil)
        #expect(row.visitDurationSeconds == nil)
        #expect(await process.storage.getDwellVisit(geofenceId: Self.dwellCircle.id) == nil)
        process.dwell.cancelEvidence(for: Self.dwellCircle.id)
    }

    /// Control: a restart on the same boot, with nothing interrupting the stay, still times its
    /// EXIT — here zero whole seconds, which is a measured duration.
    @Test
    func sameBootRestartStillTimesAZeroSecondStay() async throws {
        let files = Files()
        var process = await Process(files: files)
        files.advance(0.2)
        let entry = files.clock.wall
        await process.crossing(.enter, Self.exitOnly)
        let visit = try #require(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id))
        files.advance(0.5)

        process = await Process(files: files)
        await process.crossing(.exit, Self.exitOnly)

        let row = try #require(await process.exitRows().last)
        #expect(row.visitId == visit.visitId)
        #expect(row.enteredAt.map { Int($0.timeIntervalSince1970) } == Int(entry.timeIntervalSince1970))
        #expect(row.visitDurationSeconds == 0)
    }

    /// A known reboot — uptime behind the record — ends even an emitted stay; its EXIT is untimed,
    /// and the next stay, entered and left by native crossings, measures its own pair.
    @Test
    func knownRebootEndsAQualifiedStayAndTheNextNativeStayIsTimed() async throws {
        let files = Files()
        var process = await Process(files: files)
        let visit = try await process.qualifiedDwellCircleStay(emitted: true)
        files.reboot()

        process = await Process(files: files)
        await process.crossing(.exit, Self.dwellCircle)
        let untimed = try #require(await process.exitRows().last)
        files.advance(60)
        let reentry = files.clock.wall
        await process.crossing(.enter, Self.dwellCircle)
        files.advance(90)
        await process.crossing(.exit, Self.dwellCircle)

        #expect(untimed.visitId == nil)
        #expect(untimed.visitDurationSeconds == nil)
        let row = try #require(await process.exitRows().last)
        #expect(row.visitId != visit.visitId)
        #expect(row.enteredAt.map { Int($0.timeIntervalSince1970) } == Int(reentry.timeIntervalSince1970))
        #expect(row.visitDurationSeconds == 90)
        process.dwell.cancelEvidence(for: Self.dwellCircle.id)
    }

    /// The marker kept across an ambiguous boot is released by a native crossing — the device
    /// arrived again after an EXIT the SDK missed — and the next stay measures its own pair. The
    /// marker's dwell is not repeated.
    @Test
    func crossingAfterAnAmbiguousBootReleasesTheMarkerAndTimesItsOwnStay() async throws {
        let files = Files()
        var process = await Process(files: files)
        let visit = try await process.qualifiedDwellCircleStay(emitted: true)
        files.stepWallAndBoot(3600)
        files.advance(60)

        process = await Process(files: files)
        let reentry = files.clock.wall
        await process.crossing(.enter, Self.dwellCircle)
        let released = try #require(await process.storage.getDwellVisit(geofenceId: Self.dwellCircle.id))
        files.advance(90)
        await process.crossing(.exit, Self.dwellCircle)

        #expect(released.visitId != visit.visitId)
        let row = try #require(await process.exitRows().last)
        #expect(row.visitId == released.visitId)
        #expect(row.enteredAt.map { Int($0.timeIntervalSince1970) } == Int(reentry.timeIntervalSince1970))
        #expect(row.visitDurationSeconds == 90)
        #expect(await process.rows(.dwell).count == 1)
        process.dwell.cancelEvidence(for: Self.dwellCircle.id)
    }

    /// A stay not yet qualified keeps nothing across an ambiguous boot: none of its time counts,
    /// so its EXIT cannot report the old duration.
    @Test(arguments: [3600.0, -3600.0])
    func unqualifiedStayAcrossAnAmbiguousBootReportsNoOldDuration(step: TimeInterval) async throws {
        let files = Files()
        var process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly)
        files.advance(600)
        files.stepWallAndBoot(step)

        process = await Process(files: files)
        await process.crossing(.exit, Self.exitOnly)

        let row = try #require(await process.exitRows().last)
        #expect(row.visitId == nil)
        #expect(row.visitDurationSeconds == nil)
    }

    // MARK: - First clock reading

    /// A cold wake handles an ENTER the OS dated before this process's first clock reading. With no
    /// reference from an earlier process, or one the wall clock has since stepped away from, that
    /// date cannot be placed on the current clock: the visit's EXIT reports no entry or duration.
    @Test(arguments: [false, true])
    func entryDatedBeforeTheFirstReadingOnAnUnknownClockIsUntimed(steppedSinceTheReference: Bool) async throws {
        let files = Files()
        if steppedSinceTheReference {
            let earlier = await Process(files: files)
            // Any boundary persists the process's clock reference.
            await earlier.crossing(.exit, Self.exitOnly)
            files.clock.stepWall(3600)
        }
        let enteredAt = files.clock.wall
        files.advance(20)

        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly, at: enteredAt)
        files.advance(60)
        await process.crossing(.exit, Self.exitOnly)

        let row = try #require(await process.exitRows().last)
        #expect(row.visitDurationSeconds == nil)
        #expect(row.enteredAt == nil)
    }

    /// Control: the same delayed ENTER on a clock an earlier process's reference shows unchanged
    /// keeps its entry, and its EXIT is timed from it.
    @Test
    func entryDatedBeforeTheFirstReadingOnAKnownClockIsTimed() async throws {
        let files = Files()
        let earlier = await Process(files: files)
        await earlier.crossing(.exit, Self.exitOnly)
        files.advance(10)
        let enteredAt = files.clock.wall
        files.advance(20)

        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly, at: enteredAt)
        files.advance(60)
        await process.crossing(.exit, Self.exitOnly)

        let row = try #require(await process.exitRows().last)
        #expect(row.enteredAt.map { Int($0.timeIntervalSince1970) } == Int(enteredAt.timeIntervalSince1970))
        #expect(row.visitDurationSeconds == 80)
    }

    // MARK: - Files and processes

    /// What survives a process: the files, and the device's clock.
    @MainActor
    private final class Files {
        let contextDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let geofenceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1800000000))
        let dateUtil = DateUtilStub()
        var seeded = false

        init() {
            dateUtil.givenNow = clock.wall
        }

        /// Real time passes: both clocks, and the tracker's wall clock, move together.
        func advance(_ seconds: TimeInterval) {
            clock.advance(seconds)
            dateUtil.givenNow = clock.wall
        }

        /// The wall clock is set by `seconds`. XNU moves `kern.boottime` with it, so the next
        /// process reads a boot time `seconds` away: the same boot, but not provably so.
        func stepWallAndBoot(_ seconds: TimeInterval) {
            clock.stepWall(seconds)
            clock.boot = GeofenceBootIdentity(bootTime: (clock.boot.bootTime ?? 0) + seconds, processToken: nil)
            dateUtil.givenNow = clock.wall
        }

        /// The next process cannot read the boot time, so it knows its boot only by its own token.
        func bootTimeUnreadable() {
            clock.boot = GeofenceBootIdentity(bootTime: nil, processToken: UUID().uuidString)
        }

        /// The device restarts: uptime starts over, behind every earlier record.
        func reboot() {
            clock.reboot(secondsLater: 60, uptimeAfterBoot: 30)
            dateUtil.givenNow = clock.wall
        }
    }

    /// What a process builds at launch from those files.
    @MainActor
    private struct Process {
        let contextStore: BackgroundDeliveryContextStore
        let identity: GeofenceIdentityTracker
        let storage: GeofenceStorage
        let outbox: PendingGeofenceMetricStore
        let dwell: GeofenceDwellCoordinator
        let resolver: PolygonMembershipResolver
        let files: Files

        /// - Parameter beforeExitDelivery: runs as each EXIT reaches the tracker, after the
        ///   coordinator has fixed its facts.
        init(files: Files, beforeExitDelivery: ((BackgroundDeliveryContextStore) -> Void)? = nil) async {
            self.files = files
            self.contextStore = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: files.contextDirectory)
            self.storage = GeofenceStorage(fileManager: .default, directoryURL: files.geofenceDirectory)
            if !files.seeded {
                files.seeded = true
                contextStore.setUserId("user-a")
                contextStore.setCdpApiKey("cdp-key")
                let fences = [
                    GeofenceExitDurationProvenanceTests.exitOnly, GeofenceExitDurationProvenanceTests.dwellCircle,
                    GeofenceExitDurationProvenanceTests.polygon
                ]
                await storage.setCachedGeofences(fences)
                await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: Set(fences.map(\.id)))
            }
            self.identity = GeofenceIdentityTracker(contextStore: contextStore)
            self.outbox = PendingGeofenceMetricStore(
                logger: LoggerMock(), directoryURL: files.geofenceDirectory.appendingPathComponent("outbox")
            )
            let delivery = GeofenceDeliveryTrackerMock()
            delivery.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.transport)) }
            let tracker = GeofenceEventTracker(
                storage: storage, pendingStore: outbox, deliveryTracker: delivery, contextStore: contextStore,
                eventBusHandler: EventBusHandlerMock(), dateUtil: files.dateUtil, logger: LoggerMock(),
                cooldownInterval: 0
            )
            let contextStore = contextStore
            let emitter: GeofenceTransitionEmitting = beforeExitDelivery.map { hook in
                ExitHandoff(tracker: tracker, contextStore: contextStore, hook: hook)
            } ?? tracker
            self.dwell = GeofenceDwellCoordinator(
                storage: storage, transitionEmitter: emitter, contextStore: contextStore, logger: LoggerMock(),
                notificationCenter: NotificationCenter(), freshFixProvider: { nil }, evidenceRetryDelay: 3600,
                clock: files.clock, identityTracker: identity
            )
            let fixResolver = MovementFixResolver(logger: LoggerMock(), dateUtil: files.dateUtil)
            fixResolver.systemCachedFix = { nil }
            fixResolver.requestFreshFix = { [weak fixResolver] in fixResolver?.handleRequestFailure() }
            self.resolver = PolygonMembershipResolver(
                storage: storage, transitionEmitter: emitter, logger: LoggerMock(), contextStore: contextStore,
                dateUtil: files.dateUtil, fixResolver: fixResolver, notificationCenter: NotificationCenter(),
                dwellCoordinator: dwell
            )
        }

        /// A Core Location crossing, routed as the monitor binder routes it: dated `at` (now by
        /// default) and received for whoever is identified, unless `receivedFor` says otherwise.
        /// `crossingObserved` false is what CLMonitor passes for a correction of an assumed state,
        /// and BaselineHeal for a heal.
        func crossing(
            _ transition: GeofenceTransition,
            _ geofence: Geofence,
            at date: Date? = nil,
            receivedFor userId: String? = nil,
            crossingObserved: Bool = true
        ) async {
            await resolver.handleTransition(
                identifier: geofence.id, transition: transition, occurredAt: date ?? files.clock.wall,
                receivedForUserId: userId ?? contextStore.currentUserId ?? "", crossingObserved: crossingObserved
            )
        }

        /// A stay on the dwell circle entered by a native crossing, then 600 s later either emitted
        /// by inside evidence or left with a reservation never queued — a failed outbox write.
        /// Evidence scheduling is cancelled, as the process that recorded it is about to die.
        func qualifiedDwellCircleStay(emitted: Bool) async throws -> GeofenceDwellVisit {
            let circle = GeofenceExitDurationProvenanceTests.dwellCircle
            let entry = files.clock.wall
            await crossing(.enter, circle)
            let visit = try #require(await storage.getDwellVisit(geofenceId: circle.id))
            files.advance(600)
            if emitted {
                await dwell.recordInsideEvidence(geofence: circle, at: files.clock.wall, source: "location_evidence")
                try #require(await rows(.dwell).count == 1)
            } else {
                let reservation = GeofenceDwellReservation(
                    occurredAtEpochMilliseconds: Int64(files.clock.wall.timeIntervalSince1970 * 1000),
                    enteredAtEpochMilliseconds: Int64(entry.timeIntervalSince1970 * 1000), durationSeconds: 600,
                    thresholdSeconds: 600, detectionSource: "location_evidence"
                )
                try #require(await storage.reserveDwellEmission(reservation, for: visit, geofenceId: circle.id) == .reserved(reservation))
            }
            dwell.cancelEvidence(for: circle.id)
            return try #require(await storage.getDwellVisit(geofenceId: circle.id))
        }

        /// A mock monitor bound through the real GeofenceMonitorBinder to this process's resolver
        /// and coordinator; keep it alive for as long as its callbacks are needed.
        func boundMonitor() -> MockGeofenceRegionMonitor {
            let monitor = MockGeofenceRegionMonitor()
            GeofenceMonitorBinder.bind(
                monitor: monitor, resolver: resolver, coordinator: GeofenceSyncCoordinatorMock(),
                logger: LoggerMock(), dwellCoordinator: dwell
            )
            return monitor
        }

        /// A Core Location EXIT of `geofence` now, on its own task, as the binder routes it. Once the
        /// EXIT has recorded itself — synchronously, before its first await — and is suspended at a
        /// storage hop, `whileSuspended` runs on the main actor, as an OS callback can; then the
        /// EXIT finishes.
        func exitInterleaved(_ geofence: Geofence, whileSuspended: () -> Void) async throws {
            let exitedAt = files.clock.wall
            let exit = Task { @MainActor in await crossing(.exit, geofence, at: exitedAt) }
            var spins = 0
            while dwell.exitMarks[geofence.id]?.contains(where: { $0.date == exitedAt }) != true, spins < 10000 {
                spins += 1
                await Task.yield()
            }
            try #require(spins < 10000, "the EXIT never recorded itself")
            whileSuspended()
            await exit.value
        }

        /// Persists a visit through the real store as this build records it, then deletes from the
        /// bytes on disk the keys a build before identity provenance never wrote.
        func saveLegacyVisit(
            _ geofence: Geofence,
            entryObserved: Bool,
            emitted: Bool = false,
            reservation: GeofenceDwellReservation? = nil
        ) async throws -> GeofenceDwellVisit {
            let visit = GeofenceDwellVisit(
                visitId: UUID().uuidString, enteredAt: files.clock.wall, geometryRevision: geofence.dwellRevision,
                userId: "user-a", emitted: emitted, entryObserved: entryObserved, dwellReservation: reservation,
                timing: GeofenceVisitTiming(enteredAt: files.clock.wall, recordedAt: files.clock.read())
            )
            #expect(await storage.saveDwellVisit(visit, geofenceId: geofence.id))
            let file = files.geofenceDirectory.appendingPathComponent("geofenceState.json")
            var state = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            var visits = try #require(state["dwellVisits"] as? [String: Any])
            var stored = try #require(visits[geofence.id] as? [String: Any])
            #expect(stored.removeValue(forKey: "awaitsPresenceProof") != nil)
            #expect(stored.keys.contains("identityVersion"))
            stored.removeValue(forKey: "identityVersion")
            stored.removeValue(forKey: "identityLineage")
            visits[geofence.id] = stored
            state["dwellVisits"] = visits
            try JSONSerialization.data(withJSONObject: state).write(to: file, options: .atomic)
            return visit
        }

        func rows(_ transition: GeofenceTransition) async -> [PendingGeofenceMetric] {
            await outbox.rows().filter { $0.transition == transition }.sorted { $0.timestamp < $1.timestamp }
        }

        func exitRows() async -> [PendingGeofenceMetric] {
            await rows(.exit)
        }
    }

    /// Hands each EXIT to the real tracker after running `hook`: the point between the
    /// coordinator fixing the EXIT's facts and the tracker stamping its user.
    private final class ExitHandoff: GeofenceTransitionEmitting, @unchecked Sendable {
        let tracker: GeofenceEventTracker
        let contextStore: BackgroundDeliveryContextStore
        let hook: (BackgroundDeliveryContextStore) -> Void

        init(tracker: GeofenceEventTracker, contextStore: BackgroundDeliveryContextStore, hook: @escaping (BackgroundDeliveryContextStore) -> Void) {
            self.tracker = tracker
            self.contextStore = contextStore
            self.hook = hook
        }

        func trackTransition(geofenceId: String, transition: GeofenceTransition, occurredAt: Date) async {
            await tracker.trackTransition(geofenceId: geofenceId, transition: transition, occurredAt: occurredAt)
        }

        func trackDwell(
            geofenceId: String, occurredAt: Date, context: GeofenceDwellContext, expectedUserId: String?
        ) async -> Bool {
            await tracker.trackDwell(geofenceId: geofenceId, occurredAt: occurredAt, context: context, expectedUserId: expectedUserId)
        }

        func trackExit(
            geofenceId: String, occurredAt: Date, context: GeofenceExitContext?, expectedUserId: String?
        ) async {
            hook(contextStore)
            await tracker.trackExit(geofenceId: geofenceId, occurredAt: occurredAt, context: context, expectedUserId: expectedUserId)
        }
    }
}
