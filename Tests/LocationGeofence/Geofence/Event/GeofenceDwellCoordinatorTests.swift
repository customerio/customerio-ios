@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
import CoreLocation
import Foundation
import SharedTests
import Testing
#if canImport(UIKit)
import UIKit
#endif

@Suite("GeofenceDwellCoordinator", .serialized)
@MainActor
struct GeofenceDwellCoordinatorTests {
    /// A copy of the ENTER that opened the visit — same date — keeps it. A later-dated ENTER is a
    /// crossing of its own (see `GeofenceDwellFollowupTests`): classic monitoring reports only
    /// crossings, and `CLMonitor` drops a same-state repeat.
    @Test
    func redeliveredCircleEnterPreservesTheCurrentVisit() async {
        let setup = await makeSetup(isPolygon: false)
        let firstEntry = Date(timeIntervalSince1970: 1000)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: firstEntry
        )
        let firstVisit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)

        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: firstEntry
        )

        let secondVisit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        #expect(secondVisit == firstVisit)
    }

    /// An ENTER that is no observed crossing — the OS correcting an assumed outside, or an initial
    /// enter discovered at registration — still qualifies a dwell, but its start is discovery:
    /// neither it nor the time since it is reported.
    @Test
    func unobservedCircleEnterSupportsDwellWithoutReportingEntry() async {
        let fix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0.5, longitude: 0.5),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 10,
            timestamp: Date()
        )
        let clock = ManualGeofenceClock(wall: fix.timestamp.addingTimeInterval(-120))
        let setup = await makeSetup(isPolygon: false, freshFixProvider: { fix }, clock: clock)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .enter,
            occurredAt: clock.wall,
            crossingObserved: false
        )
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.entryObserved == false)

        clock.advance(to: fix.timestamp)
        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)

        let dwells = await setup.emitter.dwells()
        #expect(dwells.count == 1)
        #expect(dwells.first?.context.enteredAt == nil)
        #expect(dwells.first?.context.durationSeconds == nil)
    }

    /// A correction racing the visit an earlier ENTER already opened — the same arrival, dated
    /// within the 1 s tolerance — keeps that visit as it is. Half a second, not exactly the
    /// tolerance: two clock reads microseconds apart would put a 1 s gap a hair either side of it.
    @Test
    func unobservedEnterForAnOpenVisitKeepsIt() async {
        let setup = await makeSetup(isPolygon: false)
        let enteredAt = Date(timeIntervalSince1970: 1000)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: enteredAt, crossingObserved: false
        )
        let first = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)

        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: enteredAt.addingTimeInterval(0.5)
        )

        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == first)
        #expect(first?.entryObserved == false)
    }

    @Test
    func circleExitThenEnterStartsANewVisit() async {
        let setup = await makeSetup(isPolygon: false)
        let firstEntry = Date(timeIntervalSince1970: 1000)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: firstEntry
        )
        let firstVisit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)

        await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .exit,
            occurredAt: firstEntry.addingTimeInterval(10)
        )
        let secondEntry = firstEntry.addingTimeInterval(20)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: secondEntry
        )

        let secondVisit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        #expect(secondVisit?.visitId != firstVisit?.visitId)
        #expect(secondVisit?.enteredAt == secondEntry)
    }

    @Test
    func delayedEnterDoesNotReplaceANewerVisit() async {
        let setup = await makeSetup(isPolygon: false)
        let currentEntry = Date(timeIntervalSince1970: 2000)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: currentEntry
        )
        let currentVisit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)

        await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .enter,
            occurredAt: currentEntry.addingTimeInterval(-1)
        )

        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == currentVisit)
    }

    @Test
    func dayLongDwellThresholdRemainsAchievableWhenEvidenceArrivesLate() async {
        let enteredAt = Date(timeIntervalSince1970: 1000)
        let clock = ManualGeofenceClock(wall: enteredAt)
        let setup = await makeSetup(dwellThresholdSeconds: 86400, isPolygon: false, clock: clock)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: enteredAt
        )

        clock.advance(to: enteredAt.addingTimeInterval(86401))
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence,
            at: enteredAt.addingTimeInterval(86401),
            source: "location_evidence"
        )

        let dwell = await setup.emitter.dwells().first
        #expect(dwell?.context.enteredAt == enteredAt)
        #expect(dwell?.context.thresholdSeconds == 86400)
        #expect(dwell?.context.durationSeconds == 86401)
    }

    @Test
    func relaunchResumesAPersistedDueVisitWithoutChangingItsIdentity() async {
        let now = Date()
        let setup = await makeSetup(
            dwellThresholdSeconds: 1,
            isPolygon: false,
            freshFixProvider: {
                CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: 0.5, longitude: 0.5),
                    altitude: 0,
                    horizontalAccuracy: 5,
                    verticalAccuracy: 5,
                    timestamp: Date()
                )
            }
        )
        let persistedVisit = GeofenceDwellVisit(
            visitId: "persisted-visit",
            enteredAt: now.addingTimeInterval(-120),
            geometryRevision: setup.geofence.dwellRevision,
            userId: "user-1",
            emitted: false,
            timing: GeofenceVisitTiming(enteredAt: now.addingTimeInterval(-120), recordedAt: setup.clock.read())
        )
        #expect(await setup.storage.saveDwellVisit(persistedVisit, geofenceId: setup.geofence.id))

        await setup.coordinator.resumePendingVisits(geofences: [setup.geofence])

        for _ in 0 ..< 200 where await setup.emitter.dwells().isEmpty {
            try? await Task.sleep(nanoseconds: 10000000)
        }

        #expect(await setup.emitter.dwells().count == 1)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.visitId == persistedVisit.visitId)
    }

    @Test
    func confirmedPolygonReentryStartsNewVisitWhileDuplicateEvidencePreservesIt() async {
        let setup = await makeSetup()
        let firstEntry = Date(timeIntervalSince1970: 1000)
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence,
            at: firstEntry,
            source: "location_evidence",
            beginsNewVisit: true
        )
        let firstVisit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)

        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence,
            at: firstEntry.addingTimeInterval(10),
            source: "location_evidence"
        )
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == firstVisit)

        let secondEntry = firstEntry.addingTimeInterval(20)
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence,
            at: secondEntry,
            source: "location_evidence",
            beginsNewVisit: true
        )
        let secondVisit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        #expect(secondVisit?.visitId != firstVisit?.visitId)
        #expect(secondVisit?.enteredAt == secondEntry)
    }

    @Test
    func polygonDwellRequiresInsideEvidenceAfterThresholdAndEmitsOnce() async throws {
        let enteredAt = Date(timeIntervalSince1970: 1000)
        let clock = ManualGeofenceClock(wall: enteredAt)
        let setup = await makeSetup(clock: clock)

        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        clock.advance(to: enteredAt.addingTimeInterval(59))
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence,
            at: enteredAt.addingTimeInterval(59),
            source: "location_evidence"
        )
        #expect(await setup.emitter.dwells().isEmpty)

        clock.advance(to: enteredAt.addingTimeInterval(67))
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence,
            at: enteredAt.addingTimeInterval(67),
            source: "location_evidence"
        )
        clock.advance(to: enteredAt.addingTimeInterval(90))
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence,
            at: enteredAt.addingTimeInterval(90),
            source: "location_evidence"
        )

        let dwells = await setup.emitter.dwells()
        try #require(dwells.count == 1)
        #expect(dwells[0].context.thresholdSeconds == 60)
        #expect(dwells[0].context.durationSeconds == 67)
        #expect(dwells[0].context.detectionSource == "location_evidence")
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.emitted == true)
    }

    @Test
    func dwellPersistedAfterExitAndReentryDoesNotOverwriteTheNewVisit() async {
        let suspending = SuspendingDwellEmitter()
        let enteredAt = Date(timeIntervalSince1970: 1000)
        let clock = ManualGeofenceClock(wall: enteredAt)
        let setup = await makeSetup(transitionEmitter: suspending, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        let firstVisit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)

        clock.advance(to: enteredAt.addingTimeInterval(61))
        let emission = Task { @MainActor in
            await setup.coordinator.recordInsideEvidence(
                geofence: setup.geofence,
                at: enteredAt.addingTimeInterval(61),
                source: "location_evidence"
            )
        }
        await suspending.waitUntilSuspended()
        // While the dwell is being persisted, the device leaves and comes back.
        clock.advance(to: enteredAt.addingTimeInterval(62))
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: enteredAt.addingTimeInterval(62)
        )
        let reentry = enteredAt.addingTimeInterval(63)
        clock.advance(to: reentry)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: reentry)
        await suspending.resume(returning: true)
        await emission.value

        let current = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        #expect(current?.visitId != firstVisit?.visitId)
        #expect(current?.enteredAt == reentry)
        #expect(current?.emitted == false)
    }

    @Test
    func failedOutboxWriteLeavesVisitRetryable() async throws {
        let emitter = DwellEmitterSpy(results: [false, true])
        let enteredAt = Date(timeIntervalSince1970: 1000)
        let clock = ManualGeofenceClock(wall: enteredAt)
        let setup = await makeSetup(emitter: emitter, clock: clock)

        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        clock.advance(to: enteredAt.addingTimeInterval(60))
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence,
            at: enteredAt.addingTimeInterval(60),
            source: "location_evidence"
        )
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.emitted == false)

        clock.advance(to: enteredAt.addingTimeInterval(61))
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence,
            at: enteredAt.addingTimeInterval(61),
            source: "location_evidence"
        )

        // A due evidence retry can already be in flight when the second explicit evidence arrives.
        // Wait for its write and the visit mark rather than observing the intermediate first attempt.
        for _ in 0 ..< 200 {
            let attempts = await emitter.dwells()
            if attempts.count >= 2,
               await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.emitted == true {
                break
            }
            try await Task.sleep(nanoseconds: 10000000)
        }
        let attempts = await emitter.dwells()
        try #require(attempts.count == 2)
        #expect(attempts[0].context.visitId == attempts[1].context.visitId)
        // The retry repeats the reserved occurrence, not the later evidence that prompted it.
        #expect(attempts[1].occurredAt == attempts[0].occurredAt)
        #expect(attempts[1].context.durationSeconds == 60)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.emitted == true)
    }

    @Test
    func failedEmittedWriteRetryRepeatsTheOutboxRowItAlreadyWrote() async throws {
        let outbox = makeOutbox()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let emitter = OutboxDwellEmitter(store: outbox) { attempt in
            // The row is in the outbox; make the `emitted` write that follows it fail.
            if attempt == 1 { Self.setWritable(false, directory) }
        }
        // No fix ever arrives, so only the reservation can make the retry emit.
        let enteredAt = Date(timeIntervalSince1970: 1000)
        let clock = ManualGeofenceClock(wall: enteredAt)
        let setup = await makeSetup(
            transitionEmitter: emitter, isPolygon: false, freshFixProvider: { nil }, directory: directory, clock: clock
        )
        defer { Self.setWritable(true, directory) }
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)

        clock.advance(to: enteredAt.addingTimeInterval(60.25))
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence, at: enteredAt.addingTimeInterval(60.25), source: "location_evidence"
        )
        Self.setWritable(true, setup.directory)
        let pending = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        #expect(pending?.emitted == false)
        #expect(pending?.dwellReservation != nil)

        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)

        // The ENTER's own due deadline may add an attempt; every one must be the first's twin.
        let attempts = await emitter.dwells()
        try #require(attempts.count >= 2)
        for attempt in attempts.dropFirst() {
            #expect(attempt.occurredAt == attempts[0].occurredAt)
            #expect(attempt.context.enteredAt == attempts[0].context.enteredAt)
            #expect(attempt.context.durationSeconds == 60)
            #expect(attempt.context.detectionSource == attempts[0].context.detectionSource)
        }
        #expect(await Self.rows(in: outbox).count == 1, "the retry must dedup against the row already queued")
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.emitted == true)
    }

    /// The process dies after the outbox write and before `emitted` is stored. The relaunch's
    /// retry sees later evidence, yet queues nothing new, and after the row was sent re-sends an
    /// identical one.
    @Test(arguments: [false, true])
    func relaunchAfterOutboxWriteRepeatsTheReservedDwell(rowAlreadyDelivered: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outbox = makeOutbox()
        let dying = OutboxDwellEmitter(store: outbox, suspendsAfterWrite: true)
        let enteredAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down) - 300)
        // One clock for both processes: the relaunch is on the same boot.
        let clock = ManualGeofenceClock(wall: enteredAt)
        let first = await makeSetup(
            transitionEmitter: dying, isPolygon: false, freshFixProvider: { nil }, directory: directory, clock: clock
        )
        await first.coordinator.handleBoundary(geofence: first.geofence, transition: .enter, occurredAt: enteredAt)
        clock.advance(to: enteredAt.addingTimeInterval(61.5))
        let emission = Task { @MainActor in
            await first.coordinator.recordInsideEvidence(
                geofence: first.geofence, at: enteredAt.addingTimeInterval(61.5), source: "location_evidence"
            )
        }
        await dying.waitUntilSuspended()
        let original = try #require(await Self.rows(in: outbox).first)
        if rowAlreadyDelivered { #expect(await outbox.remove(key: original.key)) }

        let relaunchEmitter = OutboxDwellEmitter(store: outbox)
        clock.advance(to: Date())
        let relaunched = await makeSetup(
            transitionEmitter: relaunchEmitter,
            isPolygon: false,
            freshFixProvider: { Self.insideFix(at: Date()) },
            directory: directory,
            clock: clock
        )
        await relaunched.coordinator.resumePendingVisits(geofences: [relaunched.geofence])
        for _ in 0 ..< 200 where await relaunchEmitter.dwells().isEmpty {
            try await Task.sleep(nanoseconds: 10000000)
        }

        let rows = await Self.rows(in: outbox)
        #expect(rows == [original])
        #expect(rows.first?.dwellDurationSeconds == 61)
        #expect(await relaunched.storage.getDwellVisit(geofenceId: relaunched.geofence.id)?.emitted == true)
        await dying.resume(returning: false)
        await emission.value
    }

    @Test
    func reservationKeepsTheFirstOccurrenceAndRefusesAReplacedVisit() async {
        let setup = await makeSetup()
        let visit = GeofenceDwellVisit(
            visitId: "visit-1",
            enteredAt: Date(timeIntervalSince1970: 1000),
            geometryRevision: setup.geofence.dwellRevision,
            userId: "user-1",
            emitted: false,
            timing: GeofenceVisitTiming(enteredAt: Date(timeIntervalSince1970: 1000), recordedAt: setup.clock.read())
        )
        #expect(await setup.storage.saveDwellVisit(visit, geofenceId: setup.geofence.id))
        let first = Self.reservation(occurredAtMilliseconds: 1060000)

        #expect(await setup.storage.reserveDwellEmission(first, for: visit, geofenceId: setup.geofence.id) == .reserved(first))
        let later = Self.reservation(occurredAtMilliseconds: 1090000)
        #expect(await setup.storage.reserveDwellEmission(later, for: visit, geofenceId: setup.geofence.id) == .reserved(first))

        let replacement = GeofenceDwellVisit(
            visitId: "visit-2", enteredAt: visit.enteredAt, geometryRevision: visit.geometryRevision,
            userId: visit.userId, emitted: false, timing: GeofenceVisitTiming(enteredAt: visit.enteredAt, recordedAt: setup.clock.read())
        )
        #expect(await setup.storage.saveDwellVisit(replacement, geofenceId: setup.geofence.id))
        #expect(await setup.storage.reserveDwellEmission(later, for: visit, geofenceId: setup.geofence.id) == .superseded)

        #expect(await setup.storage.markDwellVisitEmitted(replacement, geofenceId: setup.geofence.id) == .marked)
        #expect(await setup.storage.reserveDwellEmission(later, for: replacement, geofenceId: setup.geofence.id) == .superseded)
    }

    @Test
    func reservedWholeSecondOccurrenceSurvivesADiskRoundTrip() async throws {
        let setup = await makeSetup()
        let visit = GeofenceDwellVisit(
            visitId: "visit-1",
            enteredAt: Date(timeIntervalSince1970: 1700000000),
            geometryRevision: setup.geofence.dwellRevision,
            userId: "user-1",
            emitted: false,
            timing: GeofenceVisitTiming(enteredAt: Date(timeIntervalSince1970: 1700000000), recordedAt: setup.clock.read())
        )
        #expect(await setup.storage.saveDwellVisit(visit, geofenceId: setup.geofence.id))
        let reservation = Self.reservation(occurredAtMilliseconds: 1700000060000)
        _ = await setup.storage.reserveDwellEmission(reservation, for: visit, geofenceId: setup.geofence.id)

        let stored = try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.dwellReservation)
        #expect(stored == reservation)
        #expect(Int(stored.occurredAt.timeIntervalSince1970) == 1700000060)
    }

    @Test
    func exitEndsVisitAndLaterEvidenceStartsANewOne() async {
        let setup = await makeSetup()
        let enteredAt = Date(timeIntervalSince1970: 1000)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        let firstVisit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)

        await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .exit,
            occurredAt: enteredAt.addingTimeInterval(10)
        )
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence,
            at: enteredAt.addingTimeInterval(20),
            source: "location_evidence"
        )

        let secondVisit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        #expect(firstVisit?.visitId != secondVisit?.visitId)
        #expect(secondVisit?.enteredAt == enteredAt.addingTimeInterval(20))
    }

    @Test
    func polygonEvidenceLongAfterTheDeadlineEmitsForTheStillValidVisit() async {
        let enteredAt = Date(timeIntervalSince1970: 1000)
        let clock = ManualGeofenceClock(wall: enteredAt)
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        let firstVisit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        let lateEvidence = enteredAt.addingTimeInterval(24 * 60 * 60)
        clock.advance(to: lateEvidence)

        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence,
            at: lateEvidence,
            source: "location_evidence"
        )

        let completed = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        #expect(await setup.emitter.dwells().count == 1)
        #expect(completed?.visitId == firstVisit?.visitId)
        #expect(completed?.enteredAt == enteredAt)
        #expect(completed?.emitted == true)
    }

    @Test
    func insideEvidenceAfterContinuityLossStillSupportsBestEffortDwell() async {
        let enteredAt = Date(timeIntervalSince1970: 1000)
        let clock = ManualGeofenceClock(wall: enteredAt)
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: enteredAt
        )
        clock.advance(5)
        await setup.coordinator.invalidateContinuity(geofenceId: setup.geofence.id)
        let candidateStart = enteredAt.addingTimeInterval(10)

        clock.advance(to: candidateStart)
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence, at: candidateStart, source: "location_evidence"
        )
        clock.advance(to: candidateStart.addingTimeInterval(70))
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence, at: candidateStart.addingTimeInterval(70), source: "location_evidence"
        )

        // Qualified from the candidate's start, but that start is not an entry: neither it nor the
        // time since it is claimed as observed, matching Android.
        let dwells = await setup.emitter.dwells()
        #expect(dwells.count == 1)
        #expect(dwells.first?.context.enteredAt == nil)
        #expect(dwells.first?.context.durationSeconds == nil)
        #expect(dwells.first?.context.thresholdSeconds == 60)
    }

    /// The ENTER's visit write and a later EXIT run on separate tasks. When the EXIT runs first it
    /// finds nothing to close, so the write must not then open a visit for a device already outside.
    @Test
    func enterWriteOvertakenByALaterExitLeavesNoVisitForTheReentryToInherit() async {
        let setup = await makeSetup(isPolygon: false, freshFixProvider: { nil })
        let firstEntry = Date(timeIntervalSince1970: 1000)

        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: firstEntry.addingTimeInterval(60)
        )
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: firstEntry
        )
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)

        let reentry = firstEntry.addingTimeInterval(3600)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: reentry
        )

        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.enteredAt == reentry)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: reentry.addingTimeInterval(120)
        )
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    /// OS callbacks each run on their own task. The EXIT closing the old visit and the re-entry
    /// both read the store before the EXIT removes anything: the re-entry must not adopt the visit
    /// that EXIT is ending, or the removal leaves it with none.
    @Test
    func reentryOverlappingTheExitThatEndsTheOldVisitStartsItsOwnVisit() async {
        let setup = await makeSetup(isPolygon: false, freshFixProvider: { nil })
        let firstEntry = Date(timeIntervalSince1970: 1000)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: firstEntry
        )
        let firstVisit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        let reentry = firstEntry.addingTimeInterval(61)

        let exit = Task { @MainActor in
            await setup.coordinator.handleBoundary(
                geofence: setup.geofence, transition: .exit, occurredAt: firstEntry.addingTimeInterval(60)
            )
        }
        let enter = Task { @MainActor in
            await setup.coordinator.handleBoundary(
                geofence: setup.geofence, transition: .enter, occurredAt: reentry
            )
        }
        await exit.value
        await enter.value

        let current = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        #expect(current?.visitId != firstVisit?.visitId)
        #expect(current?.enteredAt == reentry)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: reentry.addingTimeInterval(120)
        )
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    /// A delayed EXIT that found no visit has nothing to end. Removing unconditionally let it erase
    /// the visit a newer ENTER wrote while it was suspended on its read.
    @Test
    func delayedExitThatFoundNoVisitDoesNotEraseAnOverlappingNewerVisit() async {
        let setup = await makeSetup(isPolygon: false, freshFixProvider: { nil })
        let enteredAt = Date(timeIntervalSince1970: 2000)

        let enter = Task { @MainActor in
            await setup.coordinator.handleBoundary(
                geofence: setup.geofence, transition: .enter, occurredAt: enteredAt
            )
        }
        let delayedExit = Task { @MainActor in
            await setup.coordinator.handleBoundary(
                geofence: setup.geofence, transition: .exit, occurredAt: enteredAt.addingTimeInterval(-500)
            )
        }
        await enter.value
        await delayedExit.value

        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.enteredAt == enteredAt)
    }

    /// A duplicated ENTER callback overlapping itself keeps one visit, which its EXIT then closes.
    @Test
    func overlappingDuplicateEntersKeepOneVisit() async {
        let setup = await makeSetup(isPolygon: false, freshFixProvider: { nil })
        let enteredAt = Date(timeIntervalSince1970: 3000)

        let first = Task { @MainActor in
            await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        }
        let duplicate = Task { @MainActor in
            await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        }
        await first.value
        await duplicate.value
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.enteredAt == enteredAt)

        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: enteredAt.addingTimeInterval(45)
        )

        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    /// Every piece of visit state is per fence: an EXIT for one never touches another's visit.
    @Test
    func exitOverlappingAnotherFencesEntryLeavesThatVisitAlone() async {
        let setup = await makeSetup(isPolygon: false, freshFixProvider: { nil })
        let other = Geofence(
            id: "other", latitude: 10, longitude: 10, radius: 100, name: "Other",
            transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1),
            dwellThresholdSeconds: 60
        )
        await setup.storage.setCachedGeofences([setup.geofence, other])
        let enteredAt = Date(timeIntervalSince1970: 4000)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)

        let exit = Task { @MainActor in
            await setup.coordinator.handleBoundary(
                geofence: setup.geofence, transition: .exit, occurredAt: enteredAt.addingTimeInterval(30)
            )
        }
        let otherEnter = Task { @MainActor in
            await setup.coordinator.handleBoundary(
                geofence: other, transition: .enter, occurredAt: enteredAt.addingTimeInterval(10)
            )
        }
        await exit.value
        await otherEnter.value

        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: other.id)?.enteredAt == enteredAt.addingTimeInterval(10))
    }

    @Test
    func longObservedVisitIsReportedOnExit() async {
        let enteredAt = Date(timeIntervalSince1970: 1000)
        let clock = ManualGeofenceClock(wall: enteredAt)
        let setup = await makeSetup(
            dwellThresholdSeconds: 0,
            transitionTypes: [.exit],
            isPolygon: false,
            clock: clock
        )
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .enter,
            occurredAt: enteredAt
        )

        clock.advance(to: enteredAt.addingTimeInterval(7 * 86400))
        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .exit,
            occurredAt: clock.wall
        )

        #expect(context?.durationSeconds == 7 * 86400)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    @Test
    func exitOnlyFenceReturnsObservedVisitDuration() async {
        let enteredAt = Date(timeIntervalSince1970: 1000)
        let clock = ManualGeofenceClock(wall: enteredAt)
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit], clock: clock)

        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: enteredAt
        )
        clock.advance(75)
        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .exit,
            occurredAt: clock.wall,
            detectionSource: "location_evidence"
        )

        #expect(context?.enteredAt == enteredAt)
        #expect(context?.durationSeconds == 75)
        #expect(context?.detectionSource == "location_evidence")
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    /// A discovered EXIT still ends the observed visit it closes, but withholds the duration: its
    /// date is when the exit was noticed. Nothing of that visit lingers, so the next stay is timed.
    @Test
    func discoveredExitEndsObservedVisitWithoutDurationAndNextVisitIsTimed() async {
        let enteredAt = Date(timeIntervalSince1970: 1000)
        let clock = ManualGeofenceClock(wall: enteredAt)
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit], isPolygon: false, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        let first = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)

        clock.advance(to: enteredAt.addingTimeInterval(7200))
        let discovered = await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .exit,
            occurredAt: enteredAt.addingTimeInterval(7200),
            crossingObserved: false
        )
        #expect(first?.entryObserved == true)
        #expect(discovered == nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)

        let reentry = enteredAt.addingTimeInterval(9000)
        clock.advance(to: reentry)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: reentry)
        clock.advance(90)
        let observed = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        )
        #expect(observed?.visitId != first?.visitId)
        #expect(observed?.enteredAt == reentry)
        #expect(observed?.durationSeconds == 90)
    }

    @Test
    func exitWithoutObservedEntryReturnsNoVisitContext() async {
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit])

        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .exit,
            occurredAt: Date(timeIntervalSince1970: 1075)
        )

        #expect(context == nil)
    }

    @Test
    func insideEvidenceAfterContinuityLossDoesNotClaimVisitDurationOnExit() async {
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit])
        let enteredAt = Date(timeIntervalSince1970: 1000)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: enteredAt
        )
        await setup.coordinator.invalidateContinuity(geofenceId: setup.geofence.id)

        // Still inside, but this is mid-visit evidence, not the entry.
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence,
            at: enteredAt.addingTimeInterval(30),
            source: "location_evidence"
        )
        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .exit,
            occurredAt: enteredAt.addingTimeInterval(90)
        )

        #expect(context == nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    /// A persisted date can come back one ulp late (`.secondsSince1970` rounds converting into the
    /// 1970 epoch and back), so a span of exactly whole seconds truncated a second low.
    @Test
    func exactWholeSecondVisitIsNotUndercountedAfterPersistence() async throws {
        let enteredAt = try #require(Self.dateThatPersistsLate())
        let clock = ManualGeofenceClock(wall: enteredAt)
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit], isPolygon: false, clock: clock)

        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        let stored = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        #expect(stored.map { $0.enteredAt > enteredAt } == true)
        clock.advance(to: enteredAt.addingTimeInterval(60))
        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: enteredAt.addingTimeInterval(60)
        )

        #expect(context?.durationSeconds == 60)
    }

    /// The slack is for representation error only: a real fraction short of a second still truncates.
    @Test
    func visitJustShortOfAWholeSecondStillTruncates() async {
        let enteredAt = Date(timeIntervalSince1970: 5000)
        let clock = ManualGeofenceClock(wall: enteredAt)
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit], isPolygon: false, clock: clock)

        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        clock.advance(to: enteredAt.addingTimeInterval(59.999))
        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: enteredAt.addingTimeInterval(59.999)
        )

        #expect(context?.durationSeconds == 59)
    }

    @Test
    func observedEntryAfterContinuityLossRestoresVisitDuration() async {
        let enteredAt = Date(timeIntervalSince1970: 1000)
        let clock = ManualGeofenceClock(wall: enteredAt)
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit], clock: clock)
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence, at: enteredAt, source: "location_evidence"
        )
        let reentry = enteredAt.addingTimeInterval(60)

        clock.advance(to: reentry)
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence, at: reentry, source: "location_evidence", beginsNewVisit: true
        )
        clock.advance(45)
        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .exit,
            occurredAt: reentry.addingTimeInterval(45)
        )

        #expect(context?.enteredAt == reentry)
        #expect(context?.durationSeconds == 45)
    }

    /// A reference-epoch date (what `Date()` and CoreLocation produce) that the storage encoding
    /// returns slightly later. Found by search rather than hard-coded so it tracks the encoder.
    private static func dateThatPersistsLate() -> Date? {
        struct Box: Codable { let date: Date }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        for step in 0 ..< 1000 {
            let date = Date(timeIntervalSinceReferenceDate: 811000000.123 + Double(step) * 0.017)
            guard let data = try? encoder.encode(Box(date: date)),
                  let back = try? decoder.decode(Box.self, from: data).date
            else { continue }
            if back > date, Int(date.addingTimeInterval(60).timeIntervalSince(back)) < 60 { return date }
        }
        return nil
    }

    /// The ENTER's visit write and a later EXIT run on separate tasks. When the EXIT runs first it
    /// finds nothing to close, so the write must not then open a visit for a device already outside.
    @Test
    func exitOnlyFenceEnterWriteOvertakenByALaterExitMeasuresTheReentryFromItsOwnEntry() async {
        let firstEntry = Date(timeIntervalSince1970: 1000)
        let clock = ManualGeofenceClock(wall: firstEntry.addingTimeInterval(60))
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit], isPolygon: false, clock: clock)

        let firstExit = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: firstEntry.addingTimeInterval(60)
        )
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: firstEntry
        )
        #expect(firstExit == nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)

        let reentry = firstEntry.addingTimeInterval(3600)
        clock.advance(to: reentry)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: reentry
        )
        clock.advance(120)
        let finalExit = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        )

        #expect(finalExit?.enteredAt == reentry)
        #expect(finalExit?.durationSeconds == 120)
    }

    /// OS callbacks each run on their own task. The EXIT closing the old visit and the re-entry
    /// both read the store before the EXIT removes anything: the re-entry must not adopt the visit
    /// that EXIT is ending, or the removal leaves it with none.
    @Test
    func exitOnlyFenceReentryOverlappingTheClosingExitReportsEachVisitsOwnDuration() async {
        let firstEntry = Date(timeIntervalSince1970: 1000)
        let clock = ManualGeofenceClock(wall: firstEntry)
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit], isPolygon: false, clock: clock)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: firstEntry
        )
        let reentry = firstEntry.addingTimeInterval(61)
        clock.advance(to: reentry)

        let exit = Task { @MainActor in
            await setup.coordinator.handleBoundary(
                geofence: setup.geofence, transition: .exit, occurredAt: firstEntry.addingTimeInterval(60)
            )
        }
        let enter = Task { @MainActor in
            await setup.coordinator.handleBoundary(
                geofence: setup.geofence, transition: .enter, occurredAt: reentry
            )
        }
        let closed = await exit.value
        _ = await enter.value

        #expect(closed?.enteredAt == firstEntry)
        #expect(closed?.durationSeconds == 60)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.enteredAt == reentry)
        clock.advance(120)
        let finalExit = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        )
        #expect(finalExit?.enteredAt == reentry)
        #expect(finalExit?.durationSeconds == 120)
    }

    /// The overlap the test above cannot force: the re-ENTER sees the EXIT and replaces its visit
    /// before that EXIT reads the store (a priority inversion between the two callback tasks). The
    /// EXIT then finds only the newer visit, and used to report no duration for the stay it ended.
    /// An EXIT refused for another user still records the exit time first, which is exactly the
    /// state such an EXIT leaves before its read; the same EXIT is then read for the right user.
    @Test
    func exitReadAfterAnOverlappingReentryReplacedItsVisitStillReportsThatVisitsDuration() async throws {
        let firstEntry = Date(timeIntervalSince1970: 1000)
        let clock = ManualGeofenceClock(wall: firstEntry)
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit], isPolygon: false, clock: clock)
        let exitedAt = firstEntry.addingTimeInterval(60)
        let reentry = firstEntry.addingTimeInterval(61)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: firstEntry)
        let first = try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id))
        clock.advance(to: exitedAt)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: exitedAt, expectedUserId: "someone-else"
        )
        clock.advance(to: reentry)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: reentry)

        let closed = await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: exitedAt)

        #expect(closed?.visitId == first.visitId)
        #expect(closed?.durationSeconds == 60)
        // The newer visit is left for its own EXIT, which measures it and not the replaced one.
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.enteredAt == reentry)
        clock.advance(120)
        let finalExit = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        )
        #expect(finalExit?.enteredAt == reentry)
        #expect(finalExit?.durationSeconds == 120)
    }

    /// Only the EXIT that ended the replaced visit may report it: any other EXIT that finds the
    /// newer visit started after it is a delayed one, with nothing to report.
    @Test
    func replacedVisitIsNotReportedByAnUnrelatedDelayedExit() async {
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit], isPolygon: false)
        let firstEntry = Date(timeIntervalSince1970: 1000)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: firstEntry)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: firstEntry.addingTimeInterval(60),
            expectedUserId: "someone-else"
        )
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: firstEntry.addingTimeInterval(61)
        )

        let delayed = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: firstEntry.addingTimeInterval(30)
        )

        #expect(delayed == nil)
    }

    /// A decisive-outside deadline fix ends the visit's continuity: the SDK saw the device away, so
    /// the stay's real EXIT, when Core Location finally reports it past its hysteresis, has no
    /// known start to be timed from. No EXIT is made up at the fix either.
    @Test
    func exitAfterADecisiveOutsideDeadlineFixReportsNoDuration() async {
        let enteredAt = Date(timeIntervalSince1970: 1000)
        let clock = ManualGeofenceClock(wall: enteredAt)
        let outside = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0.51, longitude: 0.5),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 10, timestamp: enteredAt.addingTimeInterval(120)
        )
        let setup = await makeSetup(
            isPolygon: false, freshFixProvider: { outside }, evidenceRetryDelay: 60, clock: clock
        )
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        clock.advance(to: outside.timestamp)
        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)

        clock.advance(to: enteredAt.addingTimeInterval(900))
        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        )

        #expect(await setup.emitter.dwells().isEmpty)
        #expect(await setup.emitter.exitCount() == 0)
        #expect(context == nil)
    }

    /// The EXIT's duration is the difference of whole epoch seconds, so it equals the EXIT's
    /// whole-second timestamp minus the truncated `enteredAt` it travels with.
    @Test
    func exitDurationMatchesTheWholeSecondFieldsItTravelsWith() async {
        let enteredAt = Date(timeIntervalSince1970: 1000.9)
        let exitedAt = Date(timeIntervalSince1970: 1060.1)
        let clock = ManualGeofenceClock(wall: enteredAt)
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit], isPolygon: false, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        clock.advance(to: exitedAt)

        let context = await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: exitedAt)

        let enteredSeconds = Int(context?.enteredAt.timeIntervalSince1970 ?? 0)
        #expect(context?.durationSeconds == 60)
        #expect(context?.durationSeconds == Int(exitedAt.timeIntervalSince1970) - enteredSeconds)
    }

    /// A delayed EXIT that found no visit has nothing to end. Removing unconditionally let it erase
    /// the visit a newer ENTER wrote while it was suspended on its read.
    @Test
    func exitOnlyFenceDelayedExitThatFoundNoVisitReturnsNoVisitContext() async {
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit], isPolygon: false)
        let enteredAt = Date(timeIntervalSince1970: 2000)

        let enter = Task { @MainActor in
            await setup.coordinator.handleBoundary(
                geofence: setup.geofence, transition: .enter, occurredAt: enteredAt
            )
        }
        let delayedExit = Task { @MainActor in
            await setup.coordinator.handleBoundary(
                geofence: setup.geofence, transition: .exit, occurredAt: enteredAt.addingTimeInterval(-500)
            )
        }
        _ = await enter.value
        let staleContext = await delayedExit.value

        #expect(staleContext == nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.enteredAt == enteredAt)
    }

    /// A duplicated ENTER callback overlapping itself keeps one visit, which its EXIT then closes.
    @Test
    func exitOnlyFenceOverlappingDuplicateEntersReportOneVisitDuration() async {
        let enteredAt = Date(timeIntervalSince1970: 3000)
        let clock = ManualGeofenceClock(wall: enteredAt)
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit], isPolygon: false, clock: clock)

        let first = Task { @MainActor in
            await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        }
        let duplicate = Task { @MainActor in
            await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        }
        _ = await first.value
        _ = await duplicate.value
        clock.advance(45)
        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        )

        #expect(context?.enteredAt == enteredAt)
        #expect(context?.durationSeconds == 45)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    /// An enter-only fence with no dwell threshold has no visit to track.
    @Test
    func enterOnlyFenceWithoutDwellThresholdKeepsNoVisit() async {
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.enter], isPolygon: false)

        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: Date(timeIntervalSince1970: 1000)
        )

        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    /// Candidate evidence observed before an EXIT already seen is from the visit that EXIT ended.
    @Test
    func insideEvidenceOlderThanASeenExitStartsNoCandidate() async {
        let setup = await makeSetup()
        let exitedAt = Date(timeIntervalSince1970: 1000)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: exitedAt
        )

        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence, at: exitedAt.addingTimeInterval(-10), source: "location_evidence"
        )

        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    /// Setup resumes from the catalog it read at launch; a refresh can replace the geometry and a
    /// visit be recorded against it before the resume runs. The older snapshot must not delete it.
    @Test
    func resumeFromGeometryOlderThanTheCacheKeepsTheNewerVisit() async {
        let setup = await makeSetup(isPolygon: false)
        let refreshed = Geofence(
            id: setup.geofence.id,
            latitude: setup.geofence.latitude,
            longitude: setup.geofence.longitude,
            radius: setup.geofence.radius + 20,
            name: setup.geofence.name,
            transitionTypes: setup.geofence.transitionTypes,
            lastUpdated: Date(timeIntervalSince1970: 2),
            dwellThresholdSeconds: setup.geofence.dwellThresholdSeconds
        )
        #expect(refreshed.dwellRevision != setup.geofence.dwellRevision)
        await setup.storage.setCachedGeofences([refreshed])
        await setup.coordinator.handleBoundary(
            geofence: refreshed, transition: .enter, occurredAt: Date(timeIntervalSince1970: 1000)
        )
        let visit = await setup.storage.getDwellVisit(geofenceId: refreshed.id)
        #expect(visit != nil)

        await setup.coordinator.resumePendingVisits(geofences: [setup.geofence])

        #expect(await setup.storage.getDwellVisit(geofenceId: refreshed.id) == visit)
    }

    /// The same mismatch the other way round is a genuinely stale visit, and is still dropped.
    @Test
    func visitFromAnotherUserIsStillRemovedAsStale() async {
        let setup = await makeSetup(isPolygon: false)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: Date(timeIntervalSince1970: 1000)
        )
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) != nil)

        setup.coordinator.contextStore.setUserId("user-2")
        _ = await setup.coordinator.currentVisit(geofence: setup.geofence, userId: "user-2")

        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    @Test
    func evidenceForAnEndedVisitDoesNotStartAnother() async {
        let setup = await makeSetup()
        let enteredAt = Date(timeIntervalSince1970: 1000)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: enteredAt
        )
        let visit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: enteredAt.addingTimeInterval(20)
        )

        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence,
            at: enteredAt.addingTimeInterval(10),
            source: "location_evidence",
            continuingVisitId: visit?.visitId
        )

        #expect(visit != nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    /// Stress over interleavings: an EXIT can complete between the deadline's visit check and its
    /// evidence write. The fix predates the exit, so no visit may survive both.
    @Test
    func circleDeadlineRacingExitNeverLeavesAVisitBehind() async {
        for yields in 0 ..< 40 {
            let setup = await makeSetup(
                isPolygon: false,
                freshFixProvider: {
                    CLLocation(
                        coordinate: CLLocationCoordinate2D(latitude: 0.5, longitude: 0.5),
                        altitude: 0,
                        horizontalAccuracy: 5,
                        verticalAccuracy: 5,
                        timestamp: Date().addingTimeInterval(-1)
                    )
                }
            )
            // Not yet due, so the only evidence request is the one started below.
            await setup.coordinator.handleBoundary(
                geofence: setup.geofence, transition: .enter, occurredAt: Date().addingTimeInterval(-30)
            )

            let deadline = Task { @MainActor in
                await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)
            }
            for _ in 0 ..< yields {
                await Task.yield()
            }
            await setup.coordinator.handleBoundary(
                geofence: setup.geofence, transition: .exit, occurredAt: Date()
            )
            await deadline.value

            let leftover = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
            #expect(leftover == nil, "visit left behind after \(yields) yields")
            await setup.coordinator.invalidateContinuity()
        }
    }

    @Test
    func delayedExitFromOlderVisitDoesNotClearNewerVisit() async {
        let setup = await makeSetup()
        let enteredAt = Date(timeIntervalSince1970: 1000)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: enteredAt
        )

        await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .exit,
            occurredAt: enteredAt.addingTimeInterval(-1)
        )

        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) != nil)
    }

    @Test
    func circleDeadlineGivenAmbiguousFixDoesNotEmitOrEndVisit() async {
        let fix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0.5, longitude: 0.5),
            altitude: 0,
            horizontalAccuracy: 150,
            verticalAccuracy: 10,
            timestamp: Date()
        )
        let setup = await makeSetup(isPolygon: false, freshFixProvider: { fix })
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .enter,
            occurredAt: Date().addingTimeInterval(-120)
        )

        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)

        #expect(await setup.emitter.dwells().isEmpty)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) != nil)
    }

    @Test
    func circleDeadlineGivenDecisiveInsideFixEmitsDwell() async {
        let fix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0.5, longitude: 0.5),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 10,
            timestamp: Date()
        )
        let clock = ManualGeofenceClock(wall: fix.timestamp.addingTimeInterval(-120))
        let setup = await makeSetup(isPolygon: false, freshFixProvider: { fix }, clock: clock)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .enter,
            occurredAt: clock.wall
        )

        clock.advance(to: fix.timestamp)
        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)

        #expect(await setup.emitter.dwells().count == 1)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.emitted == true)
    }

    @Test
    func exitWhileFixIsResolvingDoesNotRearmEvidence() async throws {
        let probe = SuspendedFixProvider()
        let clock = ManualGeofenceClock(wall: Date().addingTimeInterval(-120))
        let setup = await makeSetup(
            isPolygon: false,
            freshFixProvider: { await probe.next() },
            evidenceRetryDelay: 0.001,
            clock: clock
        )
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .enter,
            occurredAt: clock.wall
        )
        // Two minutes on, the deadline re-armed at a wake is due at once.
        clock.advance(120)
        await setup.coordinator.rearmPendingEvidence(includePolygons: false)
        // The due deadline runs on its own task; under a loaded suite it can take longer than any
        // fixed number of yields to reach the fix request.
        try #require(await settleOnMain(timeout: 5) { probe.calls == 1 })

        await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .exit,
            occurredAt: Date()
        )
        probe.resolve(nil)

        // Without the exit, the failed fix re-arms after 1 ms (see the control test below), so a
        // window hundreds of times longer is enough for a stray retry to land.
        #expect(await settleOnMain(timeout: 0.3) { probe.calls > 1 } == false)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    /// Control for the test above: the same failed fix, with the visit still open, does re-arm.
    @Test
    func failedFixWhileVisitStaysOpenRearmsEvidence() async throws {
        let probe = SuspendedFixProvider()
        let clock = ManualGeofenceClock(wall: Date().addingTimeInterval(-120))
        let setup = await makeSetup(
            isPolygon: false,
            freshFixProvider: { await probe.next() },
            evidenceRetryDelay: 0.001,
            clock: clock
        )
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .enter,
            occurredAt: clock.wall
        )
        clock.advance(120)
        await setup.coordinator.rearmPendingEvidence(includePolygons: false)
        try #require(await settleOnMain(timeout: 5) { probe.calls == 1 })

        probe.resolve(nil)

        #expect(await settleOnMain(timeout: 5) { probe.calls == 2 })
        await setup.coordinator.invalidateContinuity()
        probe.resolve(nil)
    }

    @Test
    func polygonEvidenceRetriesAreBounded() async {
        let clock = ManualGeofenceClock(wall: Date().addingTimeInterval(-120))
        let setup = await makeSetup(evidenceRetryDelay: 0.001, maxEvidenceRetryAttempts: 1, clock: clock)
        var verifierCalls = 0
        setup.coordinator.polygonVerifier = { _ in verifierCalls += 1 }

        await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .enter,
            occurredAt: clock.wall
        )
        clock.advance(120)
        await setup.coordinator.rearmPendingEvidence(includePolygons: true)
        for _ in 0 ..< 100 where verifierCalls < 2 {
            try? await Task.sleep(nanoseconds: 1000000)
        }
        try? await Task.sleep(nanoseconds: 20000000)

        #expect(verifierCalls == 2)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) != nil)
    }

    #if canImport(UIKit)
    @Test
    func foregroundBeforeThresholdDoesNotSpendTheDeadline() async {
        let notificationCenter = NotificationCenter()
        let setup = await makeSetup(
            dwellThresholdSeconds: 1,
            isPolygon: false,
            freshFixProvider: {
                CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: 0.5, longitude: 0.5),
                    altitude: 0,
                    horizontalAccuracy: 5,
                    verticalAccuracy: 5,
                    timestamp: Date()
                )
            },
            evidenceRetryDelay: 0.001,
            maxEvidenceRetryAttempts: 1,
            notificationCenter: notificationCenter
        )
        let enteredAt = Date()
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: enteredAt
        )

        // Foregrounded before the threshold: inside evidence now cannot qualify, so it must not
        // exhaust the bounded retries and leave the visit with no deadline at all.
        notificationCenter.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        for _ in 0 ..< 1000 where await setup.emitter.dwells().isEmpty {
            try? await Task.sleep(nanoseconds: 10000000)
        }

        let dwells = await setup.emitter.dwells()
        #expect(dwells.count == 1)
        #expect(abs(dwells.first?.context.enteredAt?.timeIntervalSince(enteredAt) ?? .infinity) < 0.001)
        #expect((dwells.first?.context.durationSeconds ?? 0) >= 1)
    }
    #endif

    /// The backend bumps `lastUpdated` for a name, metadata or geoset edit. A refresh carrying
    /// only that must not end the visit: same shape, same threshold, same stay.
    @Test
    func metadataOnlyRefreshKeepsTheVisitAndItsDwell() async throws {
        let enteredAt = Date(timeIntervalSince1970: 1000)
        let clock = ManualGeofenceClock(wall: enteredAt)
        let setup = await makeSetup(isPolygon: false, freshFixProvider: { nil }, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        let visit = try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id))
        let edited = Geofence(
            id: setup.geofence.id,
            latitude: setup.geofence.latitude,
            longitude: setup.geofence.longitude,
            radius: setup.geofence.radius,
            name: "Renamed",
            transitionTypes: setup.geofence.transitionTypes,
            lastUpdated: Date(timeIntervalSince1970: 5000),
            geosetIds: ["geoset-2"],
            metadata: ["tier": .string("gold")],
            dwellThresholdSeconds: setup.geofence.dwellThresholdSeconds
        )

        await setup.storage.setCachedGeofences([edited])
        clock.advance(to: enteredAt.addingTimeInterval(61))
        await setup.coordinator.recordInsideEvidence(
            geofence: edited, at: enteredAt.addingTimeInterval(61), source: "location_evidence"
        )

        #expect(await setup.storage.getDwellVisit(geofenceId: edited.id)?.visitId == visit.visitId)
        #expect(await setup.emitter.dwells().first?.context.visitId == visit.visitId)
    }

    /// A geometry edit is a different fence to measure against; that visit still ends.
    @Test
    func geometryRefreshStillDropsTheVisit() async {
        let setup = await makeSetup(isPolygon: false)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: Date(timeIntervalSince1970: 1000)
        )
        let moved = Geofence(
            id: setup.geofence.id,
            latitude: setup.geofence.latitude + 0.01,
            longitude: setup.geofence.longitude,
            radius: setup.geofence.radius,
            name: setup.geofence.name,
            transitionTypes: setup.geofence.transitionTypes,
            lastUpdated: setup.geofence.lastUpdated,
            dwellThresholdSeconds: setup.geofence.dwellThresholdSeconds
        )

        await setup.storage.setCachedGeofences([moved])

        #expect(await setup.storage.getDwellVisit(geofenceId: moved.id) == nil)
    }

    /// Bounded retries can run out — a stationary indoor device may never produce a tight enough
    /// fix in three minutes. The next wake re-arms the visit with a fresh budget, and a qualifying
    /// fix then still emits the dwell for the original entry.
    @Test
    func wakeAfterExhaustedRetriesRequestsEvidenceAgain() async throws {
        let inside = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0.5, longitude: 0.5),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date()
        )
        let fixes = FixSequence([nil, nil, inside])
        let enteredAt = inside.timestamp.addingTimeInterval(-120)
        let clock = ManualGeofenceClock(wall: enteredAt)
        let setup = await makeSetup(
            isPolygon: false,
            freshFixProvider: { fixes.next() },
            evidenceRetryDelay: 0.001,
            maxEvidenceRetryAttempts: 1,
            clock: clock
        )
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        // Two minutes on, the deadline re-armed at a wake is due at once.
        clock.advance(to: inside.timestamp)
        await setup.coordinator.rearmPendingEvidence(includePolygons: false)
        // The due deadline, then its single retry; both get no fix, and nothing is left armed.
        try #require(await settleOnMain(timeout: 10) {
            fixes.calls == 2 && setup.coordinator.deadlineTasks[setup.geofence.id] == nil
        })
        #expect(await setup.emitter.dwells().isEmpty)

        await setup.coordinator.rearmPendingEvidence(includePolygons: false)

        for _ in 0 ..< 300 where await setup.emitter.dwells().isEmpty {
            try? await Task.sleep(nanoseconds: 10000000)
        }
        let dwell = await setup.emitter.dwells().first
        #expect(abs(dwell?.context.enteredAt?.timeIntervalSince(enteredAt) ?? .infinity) < 0.001)
    }

    /// A background wake re-arms circles only: a polygon's evidence is a forced fresh-fix pass,
    /// and running one beside the wake's own would have one refused as an echo.
    @Test
    func backgroundWakeRearmLeavesPolygonsToTheirOwnPass() async {
        let setup = await makeSetup(evidenceRetryDelay: 60)
        var verifierCalls = 0
        setup.coordinator.polygonVerifier = { _ in verifierCalls += 1 }
        let visit = GeofenceDwellVisit(
            visitId: "polygon-visit",
            enteredAt: Date().addingTimeInterval(-120),
            geometryRevision: setup.geofence.dwellRevision,
            userId: "user-1",
            emitted: false,
            timing: .recorded(secondsAgo: 120, on: setup.clock)
        )
        #expect(await setup.storage.saveDwellVisit(visit, geofenceId: setup.geofence.id))

        await setup.coordinator.rearmPendingEvidence(includePolygons: false)
        #expect(setup.coordinator.deadlineTasks[setup.geofence.id] == nil)

        await setup.coordinator.rearmPendingEvidence(includePolygons: true)
        #expect(await settleOnMain(timeout: 10) { verifierCalls == 1 })
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    /// The re-arm reads storage, and an ENTER can write and arm a newer visit meanwhile. The older
    /// read must not replace that visit's deadline.
    @Test
    func rearmLeavesANewerVisitsPendingEvidenceAlone() async {
        let setup = await makeSetup(isPolygon: false, freshFixProvider: { nil }, evidenceRetryDelay: 60)
        let stored = GeofenceDwellVisit(
            visitId: "stored-visit",
            enteredAt: Date().addingTimeInterval(-120),
            geometryRevision: setup.geofence.dwellRevision,
            userId: "user-1",
            emitted: false,
            timing: .recorded(secondsAgo: 120, on: setup.clock)
        )
        #expect(await setup.storage.saveDwellVisit(stored, geofenceId: setup.geofence.id))
        setup.coordinator.evidenceRetries[setup.geofence.id] = .init(visitId: "newer-visit", attempts: 2)

        await setup.coordinator.rearmPendingEvidence(includePolygons: true)

        #expect(setup.coordinator.evidenceRetries[setup.geofence.id]?.visitId == "newer-visit")
        #expect(setup.coordinator.evidenceRetries[setup.geofence.id]?.attempts == 2)
        #expect(setup.coordinator.deadlineTasks[setup.geofence.id] == nil)
    }

    /// The event carries `enteredAt` truncated to whole epoch seconds and a timestamp read to whole
    /// seconds the same way; the reported duration is their difference, so the three agree.
    /// Qualifying still uses the elapsed time actually observed.
    @Test
    func dwellDurationMatchesTheWholeSecondFieldsItTravelsWith() async {
        let enteredAt = Date(timeIntervalSince1970: 1000.9)
        let clock = ManualGeofenceClock(wall: enteredAt)
        let setup = await makeSetup(isPolygon: false, freshFixProvider: { nil }, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)

        // 59.2 s observed: 1060 - 1000 would read 60, but the stay has not reached the threshold.
        clock.advance(to: Date(timeIntervalSince1970: 1060.1))
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence, at: Date(timeIntervalSince1970: 1060.1), source: "location_evidence"
        )
        #expect(await setup.emitter.dwells().isEmpty)

        let observedAt = Date(timeIntervalSince1970: 1061.1)
        clock.advance(to: observedAt)
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence, at: observedAt, source: "location_evidence"
        )

        let dwell = await setup.emitter.dwells().first
        let enteredSeconds = Int(dwell?.context.enteredAt?.timeIntervalSince1970 ?? 0)
        #expect(dwell?.context.durationSeconds == 61)
        #expect(dwell?.context.durationSeconds == Int(observedAt.timeIntervalSince1970) - enteredSeconds)
    }

    private func makeSetup(
        emitter: DwellEmitterSpy = DwellEmitterSpy(),
        transitionEmitter: GeofenceTransitionEmitting? = nil,
        dwellThresholdSeconds: Int = 60,
        transitionTypes: Set<GeofenceTransition> = [.enter, .exit],
        isPolygon: Bool = true,
        freshFixProvider: (() async -> CLLocation?)? = nil,
        evidenceRetryDelay: TimeInterval = 60,
        maxEvidenceRetryAttempts: Int = 3,
        // Private by default: suites running alongside post `willEnterForeground` on `.default` (the
        // replay harness does), and each post re-arms every live coordinator — resetting retry
        // budgets and spending scripted fixes mid-test.
        notificationCenter: NotificationCenter = NotificationCenter(),
        // Shared by two setups to model a relaunch over the same persisted state.
        directory: URL? = nil,
        clock: GeofenceClock = SystemGeofenceClock(),
        locationAccess: (@MainActor () -> GeofenceLocationAccess?)? = nil
    ) async -> Setup {
        let directory = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = GeofenceStorage(fileManager: .default, directoryURL: directory)
        let contextStore = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        contextStore.setUserId("user-1")
        let geofence = Geofence(
            id: "polygon",
            latitude: 0.5,
            longitude: 0.5,
            radius: 100,
            name: "Campus",
            transitionTypes: transitionTypes,
            lastUpdated: Date(timeIntervalSince1970: 1),
            vertices: isPolygon ? [
                LocationData(latitude: 0, longitude: 0),
                LocationData(latitude: 0, longitude: 1),
                LocationData(latitude: 1, longitude: 0)
            ] : nil,
            dwellThresholdSeconds: dwellThresholdSeconds
        )
        await storage.setCachedGeofences([geofence])
        await storage.recordRegistration(
            center: LocationData(latitude: geofence.latitude, longitude: geofence.longitude),
            businessIds: [geofence.id]
        )
        let coordinator = GeofenceDwellCoordinator(
            storage: storage,
            transitionEmitter: transitionEmitter ?? emitter,
            contextStore: contextStore,
            logger: LoggerMock(),
            notificationCenter: notificationCenter,
            freshFixProvider: freshFixProvider,
            evidenceRetryDelay: evidenceRetryDelay,
            maxEvidenceRetryAttempts: maxEvidenceRetryAttempts,
            clock: clock,
            locationAccess: locationAccess
        )
        return Setup(
            storage: storage, emitter: emitter, coordinator: coordinator, geofence: geofence, directory: directory,
            clock: clock
        )
    }

    private struct Setup {
        let storage: GeofenceStorage
        let emitter: DwellEmitterSpy
        let coordinator: GeofenceDwellCoordinator
        let geofence: Geofence
        let directory: URL
        let clock: GeofenceClock
    }

    private func makeOutbox() -> PendingGeofenceMetricStore {
        PendingGeofenceMetricStore(
            logger: LoggerMock(),
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
    }

    private static func rows(in outbox: PendingGeofenceMetricStore) async -> [PendingGeofenceMetric] {
        guard case .rows(let rows) = await outbox.read() else { return [] }
        return rows
    }

    /// Wholly inside the circle `makeSetup` builds.
    private static func insideFix(at timestamp: Date) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0.5, longitude: 0.5),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: timestamp
        )
    }

    private static func reservation(occurredAtMilliseconds: Int64) -> GeofenceDwellReservation {
        GeofenceDwellReservation(
            occurredAtEpochMilliseconds: occurredAtMilliseconds,
            enteredAtEpochMilliseconds: 1000000,
            durationSeconds: 60,
            thresholdSeconds: 60,
            detectionSource: "location_evidence"
        )
    }

    /// A read-only directory refuses the atomic write's temporary file, failing the state save.
    private static func setWritable(_ writable: Bool, _ directory: URL) {
        try? FileManager.default.setAttributes(
            [.posixPermissions: writable ? 0o755 : 0o555], ofItemAtPath: directory.path
        )
    }
}

/// Answers each fix request with the next scripted fix; nil once the script runs out.
@MainActor
private final class FixSequence {
    private var fixes: [CLLocation?]
    private(set) var calls = 0

    init(_ fixes: [CLLocation?]) {
        self.fixes = fixes
    }

    func next() -> CLLocation? {
        calls += 1
        return fixes.isEmpty ? nil : fixes.removeFirst()
    }
}

@MainActor
private final class SuspendedFixProvider {
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private(set) var calls = 0

    func next() async -> CLLocation? {
        calls += 1
        return await withCheckedContinuation { continuation = $0 }
    }

    func resolve(_ fix: CLLocation?) {
        continuation?.resume(returning: fix)
        continuation = nil
    }
}

/// Holds `trackDwell` open so a test can land boundary events while the emitter is suspended.
private actor SuspendingDwellEmitter: GeofenceTransitionEmitting {
    private var pending: CheckedContinuation<Bool, Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []

    func trackTransition(geofenceId: String, transition: GeofenceTransition, occurredAt: Date) async {}

    func trackExit(
        geofenceId: String, occurredAt: Date, context: GeofenceExitContext?, expectedUserId: String?
    ) async {}

    func trackDwell(
        geofenceId: String, occurredAt: Date, context: GeofenceDwellContext, expectedUserId: String?
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            pending = continuation
            suspensionWaiters.forEach { $0.resume() }
            suspensionWaiters.removeAll()
        }
    }

    func waitUntilSuspended() async {
        guard pending == nil else { return }
        await withCheckedContinuation { suspensionWaiters.append($0) }
    }

    func resume(returning persisted: Bool) {
        pending?.resume(returning: persisted)
        pending = nil
    }
}

private actor DwellEmitterSpy: GeofenceTransitionEmitting {
    struct Invocation: Sendable {
        let geofenceId: String
        let occurredAt: Date
        let context: GeofenceDwellContext
    }

    private var results: [Bool]
    private var invocations: [Invocation] = []
    private var exits = 0

    init(results: [Bool] = [true]) {
        self.results = results
    }

    func trackTransition(geofenceId: String, transition: GeofenceTransition, occurredAt: Date) async {
        if transition == .exit { exits += 1 }
    }

    func trackExit(
        geofenceId: String, occurredAt: Date, context: GeofenceExitContext?, expectedUserId: String?
    ) async {
        exits += 1
    }

    func trackDwell(
        geofenceId: String, occurredAt: Date, context: GeofenceDwellContext, expectedUserId: String?
    ) async -> Bool {
        invocations.append(Invocation(geofenceId: geofenceId, occurredAt: occurredAt, context: context))
        return results.isEmpty ? true : results.removeFirst()
    }

    func dwells() -> [Invocation] {
        invocations
    }

    func exitCount() -> Int {
        exits
    }
}

/// Writes each dwell's rows to a real outbox, as the tracker does before it returns. Optionally
/// suspends after the write forever — a process that died before `emitted` was stored.
private actor OutboxDwellEmitter: GeofenceTransitionEmitting {
    private let store: PendingGeofenceMetricStore
    private let suspendsAfterWrite: Bool
    private let afterWrite: @MainActor (Int) -> Void
    private var invocations: [DwellEmitterSpy.Invocation] = []
    private var pending: CheckedContinuation<Bool, Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        store: PendingGeofenceMetricStore,
        suspendsAfterWrite: Bool = false,
        afterWrite: @escaping @MainActor (Int) -> Void = { _ in }
    ) {
        self.store = store
        self.suspendsAfterWrite = suspendsAfterWrite
        self.afterWrite = afterWrite
    }

    func trackTransition(geofenceId: String, transition: GeofenceTransition, occurredAt: Date) async {}

    func trackExit(
        geofenceId: String, occurredAt: Date, context: GeofenceExitContext?, expectedUserId: String?
    ) async {}

    func trackDwell(
        geofenceId: String, occurredAt: Date, context: GeofenceDwellContext, expectedUserId: String?
    ) async -> Bool {
        let crossing = GeofenceCrossing(
            geofenceId: geofenceId, transition: .dwell, occurredAt: occurredAt,
            dwell: context, exit: nil, expectedUserId: expectedUserId
        )
        guard await store.append(crossing.pendingMetrics(userId: "user-1", cachedGeofence: nil)) == .persisted
        else { return false }
        invocations.append(DwellEmitterSpy.Invocation(geofenceId: geofenceId, occurredAt: occurredAt, context: context))
        await afterWrite(invocations.count)
        guard suspendsAfterWrite else { return true }
        return await withCheckedContinuation { continuation in
            pending = continuation
            suspensionWaiters.forEach { $0.resume() }
            suspensionWaiters.removeAll()
        }
    }

    func waitUntilSuspended() async {
        guard pending == nil else { return }
        await withCheckedContinuation { suspensionWaiters.append($0) }
    }

    func resume(returning persisted: Bool) {
        pending?.resume(returning: persisted)
        pending = nil
    }

    func dwells() -> [DwellEmitterSpy.Invocation] {
        invocations
    }
}
