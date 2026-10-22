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

    /// A reservation is a fact about the stay: the dwell qualified when it was made. A continuity
    /// break since — here Always dropping to When In Use — refuses a first admission, never a
    /// reservation, which the retry path (a deadline or relaunch requesting evidence) still reads
    /// and delivers as reserved.
    @Test
    func reservedDwellIsDeliveredDespiteALaterAccessDowngrade() async throws {
        let granted = GeofenceLocationAccess(delivery: .background, fullAccuracy: true)
        let access = MutableAccess(granted)
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1000))
        let setup = await makeSetup(isPolygon: false, clock: clock, locationAccess: { access.value })
        let enteredAt = clock.wall
        let reservation = GeofenceDwellReservation(
            occurredAtEpochMilliseconds: Int64(enteredAt.timeIntervalSince1970 * 1000) + 60000,
            enteredAtEpochMilliseconds: Int64(enteredAt.timeIntervalSince1970 * 1000), durationSeconds: 60,
            thresholdSeconds: 60, detectionSource: "location_evidence"
        )
        let reserved = GeofenceDwellVisit(
            visitId: UUID().uuidString, enteredAt: enteredAt, geometryRevision: setup.geofence.dwellRevision,
            userId: "user-1", emitted: false, entryObserved: true, dwellReservation: reservation,
            timing: GeofenceVisitTiming(enteredAt: enteredAt, recordedAt: clock.read()), locationAccess: granted
        )
        try #require(await setup.storage.saveDwellVisit(reserved, geofenceId: setup.geofence.id))
        access.value = GeofenceLocationAccess(delivery: .foregroundOnly, fullAccuracy: true)
        clock.advance(60)

        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)

        let dwells = await setup.emitter.dwells()
        #expect(dwells.map(\.context.visitId) == [reserved.visitId])
        #expect(dwells.first?.context.durationSeconds == 60)
        // Delivered, the visit is an emitted stay like any other, which the downgrade may end.
        let stored = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        #expect(stored == nil || stored?.emitted == true)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    /// The monitor reports an authorization downgrade as an interruption of every fence, whose
    /// cleanup removes the visits it spans. One still owing its reserved dwell — delivered once
    /// and failed, say — survives it, and the retry delivers the reservation.
    @Test
    func interruptionKeepsAnUndeliveredReservationForTheRetry() async throws {
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1000))
        let setup = await makeSetup(isPolygon: false, clock: clock)
        let enteredAt = clock.wall
        let reservation = GeofenceDwellReservation(
            occurredAtEpochMilliseconds: Int64(enteredAt.timeIntervalSince1970 * 1000) + 60000,
            enteredAtEpochMilliseconds: Int64(enteredAt.timeIntervalSince1970 * 1000), durationSeconds: 60,
            thresholdSeconds: 60, detectionSource: "location_evidence"
        )
        let reserved = GeofenceDwellVisit(
            visitId: UUID().uuidString, enteredAt: enteredAt, geometryRevision: setup.geofence.dwellRevision,
            userId: "user-1", emitted: false, entryObserved: true, dwellReservation: reservation,
            timing: GeofenceVisitTiming(enteredAt: enteredAt, recordedAt: clock.read())
        )
        try #require(await setup.storage.saveDwellVisit(reserved, geofenceId: setup.geofence.id))
        clock.advance(90)

        await setup.coordinator.interruptContinuity(geofenceId: nil).value
        try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.visitId == reserved.visitId)
        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)

        let dwells = await setup.emitter.dwells()
        #expect(dwells.map(\.context.visitId) == [reserved.visitId])
        #expect(dwells.first?.context.durationSeconds == 60)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    /// Which fences are polygons comes from the persisted catalog only. A refresh that replaces
    /// the catalog wins over a launch load still reading the old one, and over a covering-circle
    /// callback whose fence the server has since made a circle.
    @Test
    func catalogReplacementWinsOverStalePolygonReads() async throws {
        let setup = await makeSetup(isPolygon: true)
        await settleQuietly()
        try #require(setup.coordinator.polygonIds.contains(setup.geofence.id))

        // The load reads the old catalog, then the refresh lands before it resumes.
        setup.coordinator.loadPolygonIds()
        setup.coordinator.rememberCatalog([])
        await settleQuietly()
        #expect(setup.coordinator.polygonIds.isEmpty)

        // The callback's fence is now a circle in the catalog: not a polygon, whatever the caller held.
        let circle = Geofence(
            id: setup.geofence.id, latitude: 0.5, longitude: 0.5, radius: 100, name: "Campus",
            transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 2), dwellThresholdSeconds: 60
        )
        await setup.storage.setCachedGeofences([circle])
        setup.coordinator.rememberCatalog([circle])
        setup.coordinator.noteEnter(geofenceId: circle.id, occurredAt: Date(), crossing: false)
        await setup.coordinator.forgetCoveringCircleEnter(geofenceId: circle.id)

        #expect(!setup.coordinator.polygonIds.contains(circle.id))
        #expect(setup.coordinator.enterMarks[circle.id]?.correction != nil)
    }

    /// A correction noted on a cold start, before the shapes are loaded, waits for them: for a
    /// polygon's covering circle it is dropped and the unqualified visit it would have ended stays.
    @Test
    func correctionBeforeTheShapesLoadDoesNotEndAPolygonVisit() async throws {
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1000))
        let setup = await makeSetup(isPolygon: true, clock: clock)
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence, at: clock.wall, source: "location_evidence", beginsNewVisit: true
        )
        let visit = try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id))
        clock.advance(300)
        // As at launch: nothing loaded yet when the OS corrects the covering circle it assumed outside.
        setup.coordinator.polygonIdsLoaded = false
        setup.coordinator.polygonIds = []
        setup.coordinator.noteEnter(geofenceId: setup.geofence.id, occurredAt: clock.wall, crossing: false)
        #expect(setup.coordinator.enterMarks[setup.geofence.id] == nil)
        #expect(await setup.coordinator.currentVisit(geofence: setup.geofence, userId: "user-1")?.visitId == visit.visitId)

        setup.coordinator.rememberCatalog([setup.geofence])

        #expect(setup.coordinator.enterMarks[setup.geofence.id] == nil)
        #expect(setup.coordinator.pendingCorrections.isEmpty)
        #expect(await setup.coordinator.currentVisit(geofence: setup.geofence, userId: "user-1")?.visitId == visit.visitId)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    /// The same correction for a circle is applied once the shapes are loaded, and ends the
    /// unqualified stay it is later than, as it would have at once.
    @Test
    func correctionBeforeTheShapesLoadIsAppliedToACircle() async throws {
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1000))
        let setup = await makeSetup(isPolygon: false, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) != nil)
        clock.advance(300)
        setup.coordinator.polygonIdsLoaded = false
        setup.coordinator.noteEnter(geofenceId: setup.geofence.id, occurredAt: clock.wall, crossing: false)
        // The ENTER that opened the visit is its crossing mark; the correction waits.
        #expect(setup.coordinator.enterMarks[setup.geofence.id]?.correction == nil)

        setup.coordinator.rememberCatalog([setup.geofence])

        #expect(setup.coordinator.enterMarks[setup.geofence.id]?.correction != nil)
        #expect(await setup.coordinator.currentVisit(geofence: setup.geofence, userId: "user-1") == nil)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    /// Two kinds of check: a timing suppressor (here an unobserved entry) still names the visit
    /// the EXIT ends, while an attribution failure (an observed boundary other than this EXIT
    /// already closed the stay) names nothing, though the EXIT still ends the visit.
    @Test
    func exitAttributionIsSeparateFromItsTiming() async throws {
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1000))
        let setup = await makeSetup(isPolygon: false, clock: clock)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: clock.wall, crossingObserved: false
        )
        clock.advance(300)
        let untimed = await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: clock.wall)
        #expect(untimed?.visitId != nil)
        #expect(untimed?.durationSeconds == nil)
        clock.advance(1)

        let enteredAt = clock.wall
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        var closed = try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id))
        closed.closedByObservedBoundary = enteredAt.addingTimeInterval(100)
        try #require(await setup.storage.saveDwellVisit(closed, geofenceId: setup.geofence.id))
        clock.advance(200)

        let other = await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: clock.wall)

        #expect(other == nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    /// A healed or corrected circle EXIT — not dated by the OS — bounds its departure by the last
    /// decisive inside fix, not the entry: here the DWELL's qualifying fix, 60 s before the heal.
    @Test
    func healedCircleExitBoundsItsUncertaintyByTheLastDecisiveInsideFix() async throws {
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1000))
        let setup = await makeSetup(isPolygon: false, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(600)
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence, at: clock.wall, source: "location_evidence", qualifiesDwell: true
        )
        try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.lastDecisiveInsideAt == clock.wall)
        clock.advance(60)

        let healed = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall, crossingObserved: false
        )

        #expect(healed?.durationSeconds == 660)
        #expect(healed?.visitDurationUncertaintySeconds == 60)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    /// A circle EXIT the OS decided and dated, long after the last inside evidence, bounds its
    /// departure by that evidence, not by the EXIT itself: the OS samples location sparsely, so the
    /// device may have left at any point since it was last known inside. Here the DWELL's
    /// qualifying fix, 30 min before the EXIT.
    @Test
    func osDecidedCircleExitLongAfterTheLastInsideEvidenceReportsThatGap() async throws {
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1000))
        let setup = await makeSetup(isPolygon: false, clock: clock)
        try #require(!setup.coordinator.osExitDatesAreReceipts)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(600)
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence, at: clock.wall, source: "location_evidence", qualifiesDwell: true
        )
        clock.advance(1800)

        let context = await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: clock.wall)

        #expect(context?.durationSeconds == 2400)
        #expect(context?.visitDurationUncertaintySeconds == 1800)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    /// The uncertainty is the millisecond gap rounded up, never down: 61.8 s since the last inside
    /// fix reports 62, though the whole epoch seconds of the two dates are 61 apart. Rounded down,
    /// a departure early in the gap would fall outside what the EXIT reports. The 661.9 s stay
    /// reports 662.
    @Test
    func exitUncertainty_roundsTheGapUp() async throws {
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1000))
        let setup = await makeSetup(isPolygon: false, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(600.1)
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence, at: clock.wall, source: "location_evidence", qualifiesDwell: true
        )
        clock.advance(61.8)

        let context = await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: clock.wall)

        #expect(context?.durationSeconds == 662)
        #expect(context?.visitDurationUncertaintySeconds == 62)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    /// Inside proof dated after a delayed EXIT may belong to a return: entry at 0, a decisive inside
    /// fix at 700, an EXIT dated 600 routed after it. The EXIT keeps the visit's id but reports no
    /// entry, duration or uncertainty, rather than 600 s certain to the second.
    @Test
    func exitDatedBeforeTheLastInsideProof_isUntimed() async throws {
        let entry = Date(timeIntervalSince1970: 1000)
        let clock = ManualGeofenceClock(wall: entry)
        let setup = await makeSetup(isPolygon: false, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: entry)
        let visit = try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id))
        clock.advance(700)
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence, at: clock.wall, source: "location_evidence", qualifiesDwell: true
        )
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
        clock.advance(10)

        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: entry.addingTimeInterval(600)
        )

        #expect(context?.visitId == visit.visitId)
        #expect(context?.enteredAt == nil)
        #expect(context?.durationSeconds == nil)
        #expect(context?.visitDurationUncertaintySeconds == nil)
    }

    /// The duration rounds up, so the stay is never longer than reported: entry 1000.1 s, EXIT
    /// 1020.9 s is a 20.8 s stay and reports 21, not the 20 the whole epoch seconds differ by.
    @Test
    func exitDuration_roundsUp() async throws {
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1000.1))
        let setup = await makeSetup(isPolygon: false, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(20.8)

        let context = await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: clock.wall)

        #expect(context?.durationSeconds == 21)
        #expect(context?.visitDurationUncertaintySeconds == 21)
    }

    /// A DWELL's duration to its evidence fix rounds up the same way: entry 1000.1 s, evidence
    /// 1060.9 s reports 61.
    @Test
    func dwellDuration_roundsUp() async throws {
        let emitter = DwellEmitterSpy()
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1000.1))
        let setup = await makeSetup(emitter: emitter, isPolygon: false, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(60.8)
        await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")

        #expect(await emitter.dwells().first?.context.durationSeconds == 61)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    /// The uncertainty also covers the duration's whole-second rounding: entry 0.9 s, last inside
    /// 10.1 s, EXIT 20.1 s report a 20 s duration, and the departure allows a stay as short as
    /// 9.2 s, so the uncertainty is 11, not the 10 s gap since the inside fix.
    @Test
    func exitUncertainty_coversTheDurationsRounding() async throws {
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1000.9))
        let setup = await makeSetup(isPolygon: false, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(9.2)
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence, at: clock.wall, source: "location_evidence", qualifiesDwell: true
        )
        clock.advance(10)

        let context = await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: clock.wall)

        #expect(context?.durationSeconds == 20)
        #expect(context?.visitDurationUncertaintySeconds == 11)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    /// An OS-decided circle EXIT of a stay nothing proved inside since its entry is uncertain by the
    /// whole stay, never by more.
    @Test
    func osDecidedCircleExitWithoutInsideEvidenceReportsTheWholeStay() async throws {
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1000))
        let setup = await makeSetup(isPolygon: false, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(300)

        let context = await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: clock.wall)

        #expect(context?.durationSeconds == 300)
        #expect(context?.visitDurationUncertaintySeconds == 300)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    /// A circle EXIT the classic monitor could only date at receipt bounds its departure by the
    /// whole stay: the OS decided it at some unknown earlier moment.
    @Test
    func receiptDatedCircleExitReportsTheWholeStayAsUncertainty() async throws {
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1000))
        let setup = await makeSetup(isPolygon: false, clock: clock)
        setup.coordinator.osExitDatesAreReceipts = true
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(240)
        // A decisive inside fix does not narrow it: nothing says when, before receipt, the OS decided.
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence, at: clock.wall, source: "location_evidence", qualifiesDwell: true
        )
        clock.advance(60)

        let context = await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: clock.wall)

        #expect(context?.durationSeconds == 300)
        #expect(context?.visitDurationUncertaintySeconds == 300)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    /// Evidence that qualifies a stay while a correction for its circle still waits for the shapes
    /// reserves nothing: reserved, the dwell would be a fact the correction could no longer undo.
    /// The drain applies the correction, which ends the unqualified stay; the next ENTER starts
    /// one of its own.
    @Test
    func queuedCorrectionBlocksAdmissionUntilTheShapesLoad() async throws {
        let fix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0.5, longitude: 0.5), altitude: 0,
            horizontalAccuracy: 5, verticalAccuracy: 10, timestamp: Date()
        )
        let clock = ManualGeofenceClock(wall: fix.timestamp.addingTimeInterval(-300))
        let setup = await makeSetup(isPolygon: false, freshFixProvider: { fix }, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let first = try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id))
        clock.advance(to: fix.timestamp)
        setup.coordinator.polygonIdsLoaded = false
        setup.coordinator.noteEnter(geofenceId: setup.geofence.id, occurredAt: clock.wall, crossing: false)

        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)

        #expect(await setup.emitter.dwells().isEmpty)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.dwellReservation == nil)

        setup.coordinator.rememberCatalog([setup.geofence])
        #expect(await setup.coordinator.currentVisit(geofence: setup.geofence, userId: "user-1") == nil)
        clock.advance(1)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let next = try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id))
        #expect(next.visitId != first.visitId)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    /// A correction queued while the reservation write is in flight was not there for the check
    /// before it: the reservation it overtook is taken back before anything is delivered.
    @Test
    func correctionQueuedDuringTheReservationWriteIsNotReserved() async throws {
        let fix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0.5, longitude: 0.5), altitude: 0,
            horizontalAccuracy: 5, verticalAccuracy: 10, timestamp: Date()
        )
        let clock = ManualGeofenceClock(wall: fix.timestamp.addingTimeInterval(-300))
        let setup = await makeSetup(isPolygon: false, freshFixProvider: { fix }, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(to: fix.timestamp)
        setup.coordinator.polygonIdsLoaded = false
        let coordinator = setup.coordinator
        let geofenceId = setup.geofence.id
        let correctedAt = clock.wall
        await setup.storage.setBeforeReservationWrite {
            await MainActor.run { coordinator.noteEnter(geofenceId: geofenceId, occurredAt: correctedAt, crossing: false) }
        }

        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)

        #expect(await setup.emitter.dwells().isEmpty)
        #expect(setup.coordinator.pendingCorrections.count == 1)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.dwellReservation == nil)
        await setup.storage.setBeforeReservationWrite(nil)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    /// A correction queued and then drained into the marks while the reservation write is in
    /// flight is no longer queued when the write returns, but it supersedes the stay all the
    /// same: the reservation is taken back and nothing is delivered.
    @Test
    func correctionAppliedDuringTheReservationWriteIsNotReserved() async throws {
        let fix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0.5, longitude: 0.5), altitude: 0,
            horizontalAccuracy: 5, verticalAccuracy: 10, timestamp: Date()
        )
        let clock = ManualGeofenceClock(wall: fix.timestamp.addingTimeInterval(-300))
        let setup = await makeSetup(isPolygon: false, freshFixProvider: { fix }, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(to: fix.timestamp)
        setup.coordinator.polygonIdsLoaded = false
        let coordinator = setup.coordinator
        let geofence = setup.geofence
        let correctedAt = clock.wall
        await setup.storage.setBeforeReservationWrite {
            await MainActor.run {
                coordinator.noteEnter(geofenceId: geofence.id, occurredAt: correctedAt, crossing: false)
                coordinator.rememberCatalog([geofence])
            }
        }

        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)

        #expect(await setup.emitter.dwells().isEmpty)
        #expect(setup.coordinator.pendingCorrections.isEmpty)
        #expect(setup.coordinator.enterMarks[setup.geofence.id]?.correction != nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.dwellReservation == nil)
        #expect(await setup.coordinator.currentVisit(geofence: setup.geofence, userId: "user-1") == nil)
        await setup.storage.setBeforeReservationWrite(nil)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    /// A retraction that fails to persist still delivers nothing, now or on a later retry: the
    /// reservation left on disk is only staged, never the visit's, so the visit is judged
    /// unreserved and the correction, once applied, ends it with the leftover.
    @Test
    func failedRetractionUnderAQueuedCorrectionDeliversNothing() async throws {
        let fix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0.5, longitude: 0.5), altitude: 0,
            horizontalAccuracy: 5, verticalAccuracy: 10, timestamp: Date()
        )
        let clock = ManualGeofenceClock(wall: fix.timestamp.addingTimeInterval(-300))
        let setup = await makeSetup(isPolygon: false, freshFixProvider: { fix }, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(to: fix.timestamp)
        setup.coordinator.polygonIdsLoaded = false
        let coordinator = setup.coordinator
        let geofenceId = setup.geofence.id
        let correctedAt = clock.wall
        await setup.storage.setRetractionFails(true)
        await setup.storage.setBeforeReservationWrite {
            await MainActor.run { coordinator.noteEnter(geofenceId: geofenceId, occurredAt: correctedAt, crossing: false) }
        }

        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)

        #expect(await setup.emitter.dwells().isEmpty)
        let left = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        #expect(left?.dwellReservation == nil)
        #expect(left?.stagedDwellReservation != nil)
        await setup.storage.setBeforeReservationWrite(nil)
        // A retry while the correction still waits delivers nothing either.
        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)
        #expect(await setup.emitter.dwells().isEmpty)
        await setup.storage.setRetractionFails(false)

        setup.coordinator.rememberCatalog([setup.geofence])
        #expect(await setup.coordinator.currentVisit(geofence: setup.geofence, userId: "user-1") == nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    /// The same refused, un-retracted reservation, then the process dies: the correction that refused
    /// it dies with it. The next process does not replay the leftover as a fact; with no fresh
    /// proof, nothing is delivered.
    @Test
    func failedRetractionThenRelaunch_replaysNothingWithoutFreshProof() async throws {
        let fix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0.5, longitude: 0.5), altitude: 0,
            horizontalAccuracy: 5, verticalAccuracy: 10, timestamp: Date()
        )
        let clock = ManualGeofenceClock(wall: fix.timestamp.addingTimeInterval(-300))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = await makeSetup(isPolygon: false, freshFixProvider: { fix }, directory: directory, clock: clock)
        await first.coordinator.handleBoundary(geofence: first.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(to: fix.timestamp)
        first.coordinator.polygonIdsLoaded = false
        let coordinator = first.coordinator
        let geofenceId = first.geofence.id
        let correctedAt = clock.wall
        await first.storage.setRetractionFails(true)
        await first.storage.setBeforeReservationWrite {
            await MainActor.run { coordinator.noteEnter(geofenceId: geofenceId, occurredAt: correctedAt, crossing: false) }
        }
        await first.coordinator.requestQualifyingEvidence(geofenceId: geofenceId)
        try #require(await first.emitter.dwells().isEmpty)
        first.coordinator.cancelEvidence(for: geofenceId)

        let second = await makeSetup(isPolygon: false, freshFixProvider: { nil }, directory: directory, clock: clock)
        await second.coordinator.requestQualifyingEvidence(geofenceId: geofenceId)

        #expect(await second.emitter.dwells().isEmpty)
        #expect(await second.storage.getDwellVisit(geofenceId: geofenceId)?.emitted == false)
        second.coordinator.cancelEvidence(for: geofenceId)
    }

    /// A replacement that begins and ends while a shape check reads the catalog, after the drain
    /// has run, does not strand the check: it reads again and completes without another refresh.
    @Test
    func shapeCheckReadsAgainAfterAReplacementDuringItsRead() async throws {
        let setup = await makeSetup(isPolygon: true)
        await settleQuietly()
        setup.coordinator.polygonIds = []
        let coordinator = setup.coordinator
        // The replacement begins and ends, drain included, while the check's first read is in
        // flight; the catalog it reads afterwards still holds the polygon.
        let replaced = MutableFlag()
        await setup.storage.setBeforeShapeRead {
            await MainActor.run {
                guard !replaced.value else { return }
                replaced.value = true
                coordinator.beginCatalogReplacement()
                coordinator.rememberCatalog([])
            }
        }

        await setup.coordinator.forgetCoveringCircleEnter(geofenceId: setup.geofence.id)

        #expect(replaced.value)
        #expect(setup.coordinator.polygonIds.contains(setup.geofence.id))
        #expect(setup.coordinator.pendingShapeChecks.isEmpty)
        await setup.storage.setBeforeShapeRead(nil)
    }

    /// A shape read that would run while a refresh replaces the catalog waits for the new one,
    /// and reads the fence as the refresh persisted it.
    @Test
    func shapeReadDuringCatalogReplacementWaitsForTheNewCatalog() async throws {
        let setup = await makeSetup(isPolygon: false)
        await settleQuietly()
        setup.coordinator.noteEnter(geofenceId: setup.geofence.id, occurredAt: Date(), crossing: false)
        try #require(setup.coordinator.enterMarks[setup.geofence.id]?.correction != nil)

        setup.coordinator.beginCatalogReplacement()
        await setup.coordinator.forgetCoveringCircleEnter(geofenceId: setup.geofence.id)
        #expect(setup.coordinator.pendingShapeChecks == [setup.geofence.id])
        #expect(setup.coordinator.enterMarks[setup.geofence.id]?.correction != nil)

        setup.coordinator.rememberCatalog([setup.geofence])
        await settleQuietly()

        #expect(setup.coordinator.pendingShapeChecks.isEmpty)
        #expect(!setup.coordinator.polygonIds.contains(setup.geofence.id))
        #expect(setup.coordinator.enterMarks[setup.geofence.id]?.correction != nil)
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
        // The EXIT left the dwell its in-flight emission owned; persisted since, it is no orphan.
        #expect(await setup.storage.getOrphanedDwells().isEmpty)
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

    /// A reserved dwell the outbox keeps refusing is offered again until 24 h have passed on the
    /// wall clock since its evidence, then given up: nothing more is delivered, and the visit is
    /// marked emitted so later evidence cannot qualify it again.
    @Test
    func reservedDwellRefusedForADay_isGivenUpAndCannotQualifyAgain() async throws {
        let emitter = DwellEmitterSpy(results: Array(repeating: false, count: 10))
        let enteredAt = Date(timeIntervalSince1970: 1000)
        let clock = ManualGeofenceClock(wall: enteredAt)
        let setup = await makeSetup(emitter: emitter, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        clock.advance(60)
        await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
        try #require(await emitter.dwells().count == 1)
        try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.dwellReservation != nil)

        clock.advance(24 * 60 * 60 - 1)
        await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
        #expect(await emitter.dwells().count == 2, "within the day the reserved dwell is offered again")

        clock.advance(1)
        await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")
        #expect(await emitter.dwells().count == 2, "after a day it is given up, not offered again")
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.emitted == true)
        clock.advance(60)
        await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")
        #expect(await emitter.dwells().count == 2, "the abandoned stay cannot qualify again")
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    /// A stay whose DWELL qualified but never reached the outbox (its write failed) is left: its
    /// EXIT delivers that DWELL, exactly as reserved, before ending the stay.
    @Test
    func exitOfAStayOwingItsDwell_deliversItFirst() async throws {
        let emitter = DwellEmitterSpy(results: [false, true])
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1000))
        let setup = await makeSetup(emitter: emitter, clock: clock)
        try await owe(setup, clock: clock)
        clock.advance(30)

        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: clock.wall)

        let attempts = await emitter.dwells()
        try #require(attempts.count == 2)
        #expect(attempts[1].occurredAt == attempts[0].occurredAt)
        #expect(attempts[1].context.visitId == attempts[0].context.visitId)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
        #expect(await setup.storage.getOrphanedDwells().isEmpty)
    }

    /// An EXIT a day after the owed DWELL's evidence gives it up, as a retry or the launch sweep
    /// would: it is not offered, and no orphan is left to offer later.
    @Test
    func exitADayAfterTheOwedDwell_givesItUp() async throws {
        let emitter = DwellEmitterSpy(results: [false, true])
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1000))
        let setup = await makeSetup(emitter: emitter, clock: clock)
        try await owe(setup, clock: clock)
        clock.advance(24 * 60 * 60)

        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: clock.wall)

        #expect(await emitter.dwells().count == 1, "only the first, failed attempt")
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
        #expect(await setup.storage.getOrphanedDwells().isEmpty)
    }

    /// The EXIT's delivery fails too: the stay still ends, and its DWELL is kept as an orphan,
    /// which the next launch delivers.
    @Test
    func exitWhoseDeliveryFails_leavesAnOrphanTheNextLaunchDelivers() async throws {
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1000))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = await makeSetup(emitter: DwellEmitterSpy(results: [false, false]), directory: directory, clock: clock)
        let visit = try await owe(first, clock: clock)
        clock.advance(30)
        await first.coordinator.handleBoundary(geofence: first.geofence, transition: .exit, occurredAt: clock.wall)
        #expect(await first.storage.getDwellVisit(geofenceId: first.geofence.id) == nil)
        try #require(await first.storage.getOrphanedDwells().map(\.visitId) == [visit.visitId])

        let second = await makeSetup(emitter: DwellEmitterSpy(results: [true]), directory: directory, clock: clock)
        await second.coordinator.resumePendingVisits(geofences: [second.geofence])

        let delivered = await second.emitter.dwells()
        #expect(delivered.map(\.context.visitId) == [visit.visitId])
        #expect(delivered.first?.occurredAt == visit.dwellReservation?.occurredAt)
        #expect(await second.storage.getOrphanedDwells().isEmpty)
    }

    /// At launch an orphan the outbox cannot take is kept for the next launch; one refused for good
    /// is dropped; one 24 h old is given up without being offered.
    @Test(arguments: [GeofenceDwellDelivery.writeFailed, .refused])
    func orphanedDwellAtLaunch_isKeptOnlyWhileTheOutboxCannotTakeIt(delivery: GeofenceDwellDelivery) async throws {
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1000))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = await makeSetup(emitter: DwellEmitterSpy(results: [false]), directory: directory, clock: clock)
        let visit = try await owe(first, clock: clock)
        await first.storage.removeDwellVisit(geofenceId: first.geofence.id, ifStill: visit.visitId)
        try #require(await first.storage.getOrphanedDwells().count == 1)

        let second = await makeSetup(emitter: DwellEmitterSpy(deliveries: [delivery]), directory: directory, clock: clock)
        await second.coordinator.resumePendingVisits(geofences: [second.geofence])
        #expect(await second.emitter.dwells().count == 1)
        #expect(await second.storage.getOrphanedDwells().count == (delivery == .writeFailed ? 1 : 0))

        guard delivery == .writeFailed else { return }
        clock.advance(24 * 60 * 60)
        let third = await makeSetup(emitter: DwellEmitterSpy(results: [true]), directory: directory, clock: clock)
        await third.coordinator.resumePendingVisits(geofences: [third.geofence])
        #expect(await third.emitter.dwells().isEmpty, "a day old, it is given up, not offered")
        #expect(await third.storage.getOrphanedDwells().isEmpty)
    }

    /// The orphan list is bounded: past 16, the oldest go first.
    @Test
    func orphanedDwells_keepTheNewestSixteen() throws {
        var state = GeofenceState()
        let reservation = GeofenceDwellReservation(
            occurredAtEpochMilliseconds: 1000000, enteredAtEpochMilliseconds: nil, durationSeconds: nil,
            thresholdSeconds: 60, detectionSource: "location_evidence"
        )
        for index in 0 ..< 17 {
            let visit = GeofenceDwellVisit(
                visitId: "visit-\(index)", enteredAt: Date(timeIntervalSince1970: 1000), geometryRevision: "r",
                userId: "user-1", emitted: false, entryObserved: true, dwellReservation: reservation, timing: nil
            )
            state.dwellVisits = ["fence": visit]
        }
        state.dwellVisits = nil

        let orphans = try #require(state.orphanedDwells)
        #expect(orphans.count == 16)
        #expect(orphans.first?.visitId == "visit-1")
        #expect(orphans.last?.visitId == "visit-16")
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
            #expect(attempt.context.durationSeconds == 61)
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
        #expect(rows.first?.dwellDurationSeconds == 62, "61.5 s to the evidence, rounded up")
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
        // Discovered, the departure is dated by its discovery: the whole stay is the uncertainty.
        #expect(discovered?.visitId == first?.visitId)
        #expect(discovered?.durationSeconds == 7200)
        #expect(discovered?.visitDurationUncertaintySeconds == 7200)
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

        #expect(context?.visitId != nil)
        #expect(context?.durationSeconds == nil)
        #expect(context?.enteredAt == nil)
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

    /// The slack is for representation error only: a real fraction short of a second rounds up.
    @Test
    func visitJustShortOfAWholeSecondRoundsUp() async {
        let enteredAt = Date(timeIntervalSince1970: 5000)
        let clock = ManualGeofenceClock(wall: enteredAt)
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit], isPolygon: false, clock: clock)

        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        clock.advance(to: enteredAt.addingTimeInterval(59.999))
        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: enteredAt.addingTimeInterval(59.999)
        )

        #expect(context?.durationSeconds == 60)
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

        let enteredSeconds = Int(context?.enteredAt?.timeIntervalSince1970 ?? 0)
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
            dwellProofSpacing: 0,
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
        // The clock is frozen, so the requests are unspaced.
        let setup = await makeSetup(evidenceRetryDelay: 0.001, maxEvidenceRetryAttempts: 1, dwellProofSpacing: 0, clock: clock)
        var verifierCalls = 0
        // As the resolver does when its pass issues a request: charged to the visit's budget.
        setup.coordinator.polygonVerifier = { _ in
            verifierCalls += 1
            _ = setup.coordinator.dwellProofAdmission()?()
        }

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

    /// The dwell-proof budget can run out — a stationary indoor device may never produce a tight
    /// enough fix. A later wake re-arms the visit without replenishing it: no request is made, no
    /// deadline is armed, and the exhaustion is logged once. A qualifying fix the SDK obtains for
    /// another reason still emits the dwell for the original entry.
    @Test
    func wakeAfterExhaustedBudgetRequestsNothingButAnOpportunisticFixStillEmits() async throws {
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
            dwellProofSpacing: 0,
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
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.dwellProofAttempts == 2)

        clock.advance(600)
        await setup.coordinator.rearmPendingEvidence(includePolygons: false)
        await settleQuietly(0.2)
        #expect(fixes.calls == 2)
        #expect(setup.coordinator.deadlineTasks[setup.geofence.id] == nil)
        let logged = setup.logger.infoReceivedInvocations.filter { $0.message.contains("dwell proof budget exhausted") }
        #expect(logged.count == 1)
        #expect(logged.first?.message.contains(setup.geofence.id) == true)

        let opportunistic = clock.read().wall
        await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: opportunistic, source: "location_evidence")
        let dwell = await setup.emitter.dwells().first
        #expect(abs(dwell?.context.enteredAt?.timeIntervalSince(enteredAt) ?? .infinity) < 0.001)
        #expect(fixes.calls == 2)
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
        setup.coordinator.evidenceRetries[setup.geofence.id] = .init(visitId: "newer-visit", shortRetryUsed: true)

        await setup.coordinator.rearmPendingEvidence(includePolygons: true)

        #expect(setup.coordinator.evidenceRetries[setup.geofence.id]?.visitId == "newer-visit")
        #expect(setup.coordinator.evidenceRetries[setup.geofence.id]?.shortRetryUsed == true)
        #expect(setup.coordinator.deadlineTasks[setup.geofence.id] == nil)
    }

    @Test
    func cancelledEvidenceReadKeepsItsReplacementDeadline() async {
        let files = BlockingDwellReadFileManager()
        let setup = await makeSetup(isPolygon: false, freshFixProvider: { nil }, fileManager: files)
        let visit = GeofenceDwellVisit(
            visitId: "pending-visit", enteredAt: setup.clock.read().wall,
            geometryRevision: setup.geofence.dwellRevision, userId: "user-1", emitted: false,
            timing: .recorded(secondsAgo: 0, on: setup.clock)
        )
        #expect(await setup.storage.saveDwellVisit(visit, geofenceId: setup.geofence.id))
        defer {
            files.releaseRead()
            setup.coordinator.cancelEvidence(for: setup.geofence.id)
        }
        files.blockNextRead()
        let oldRequest = Task { await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id) }
        #expect(await settleOnMain { files.isBlocked })

        setup.coordinator.scheduleDeadline(for: setup.geofence, visit: visit)
        let replacement = setup.coordinator.deadlineTasks[setup.geofence.id]
        oldRequest.cancel()
        files.releaseRead()
        await oldRequest.value

        #expect(!files.readTimedOut)
        #expect(setup.coordinator.deadlineTasks[setup.geofence.id] == replacement)
        #expect(setup.coordinator.evidenceRetries[setup.geofence.id]?.visitId == visit.visitId)
    }

    @Test
    func evidenceRetryForAnOlderVisitKeepsTheNewerVisitsDeadline() async {
        let setup = await makeSetup(isPolygon: false, freshFixProvider: { nil }, evidenceRetryDelay: 60)
        let older = GeofenceDwellVisit(
            visitId: "older-visit", enteredAt: setup.clock.read().wall,
            geometryRevision: setup.geofence.dwellRevision, userId: "user-1", emitted: false,
            timing: .recorded(secondsAgo: 0, on: setup.clock)
        )
        let newer = GeofenceDwellVisit(
            visitId: "newer-visit", enteredAt: older.enteredAt,
            geometryRevision: older.geometryRevision, userId: older.userId, emitted: false,
            timing: older.timing
        )
        setup.coordinator.scheduleDeadline(for: setup.geofence, visit: newer)
        let deadline = setup.coordinator.deadlineTasks[setup.geofence.id]
        defer { setup.coordinator.cancelEvidence(for: setup.geofence.id) }

        setup.coordinator.scheduleEvidenceRetry(for: setup.geofence, visit: older)

        #expect(setup.coordinator.evidenceRetries[setup.geofence.id]?.visitId == newer.visitId)
        #expect(setup.coordinator.evidenceRetries[setup.geofence.id]?.shortRetryUsed == false)
        #expect(setup.coordinator.evidenceRetries[setup.geofence.id]?.nextFixAfter == nil)
        #expect(setup.coordinator.deadlineTasks[setup.geofence.id] == deadline)
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

    /// Pulse-style one-hour polygon visit under the opt-in session. Collection must outlast the last
    /// forced proof request the coordinator can make for the visit, and no re-arm or copied ENTER may
    /// move its cap past the one fixed when the visit was recorded. Nothing here proves presence.
    @Test
    func pendingCollection_whenHourVisitRearms_thenCollectsThroughLastRequestAndStopsAtEntryCap() async throws {
        let probe = PulseProbe()
        let rig = try await makeCollectionRig(dwellThresholdSeconds: 3600, probe: probe)
        defer { rig.cancelWaits() }
        let setup = rig.setup, owner = rig.owner, manager = rig.manager
        let coordinator = setup.coordinator, id = setup.geofence.id, enteredAt = rig.start
        // Never proves presence: each forced request, charged to the visit's budget as the
        // resolver charges it, waits out its 10 s fix timeout.
        coordinator.polygonVerifier = { @MainActor fenceId in
            probe.verified.append(fenceId)
            _ = coordinator.dwellProofAdmission()?()
            try? await rig.scheduler.sleep(nanoseconds: 10 * 1000000000)
        }
        // Recording uptime + 3600 s threshold + the fixed 220 s grace.
        let capNanos = UInt64(rig.clock.uptime + 3820) * 1000000000

        await coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        try await rig.step(probe: probe, to: 0, waits: 1, verified: 0, next: 3600)
        let visitId = try #require(await setup.storage.getDwellVisit(geofenceId: id)?.visitId)
        #expect(owner.isRunning)
        #expect(owner.leases[id]?.deadline == capNanos)
        #expect(rig.collectionScheduler.nextDeadline == 3820)

        // Half way: a foreground re-arm, then the OS redelivering the ENTER that began this visit.
        rig.advance(to: 1800)
        await coordinator.rearmPendingEvidence(includePolygons: true)
        await coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        // Both re-arms wait the remaining 1800 s, keeping the original 3600 deadline.
        try await rig.step(probe: probe, to: 1800, waits: 3, verified: 0, next: 3600)
        #expect(await setup.storage.getDwellVisit(geofenceId: id)?.visitId == visitId)
        #expect(owner.leases[id]?.visit.visitId == visitId)
        #expect(owner.leases[id]?.deadline == capNanos)
        #expect(rig.collectionScheduler.nextDeadline == 3820)
        #expect(manager.starts == 1)

        try await rig.step(probe: probe, to: 3600, waits: 3, verified: 1, next: 3610)
        try await rig.step(probe: probe, to: 3610, waits: 4, verified: 1, next: 3670)
        try await rig.step(probe: probe, to: 3670, waits: 4, verified: 2, next: 3680)
        try await rig.step(probe: probe, to: 3680, waits: 5, verified: 2, next: 3740)
        try await rig.step(probe: probe, to: 3740, waits: 5, verified: 3, next: 3750)
        try await rig.step(probe: probe, to: 3750, waits: 6, verified: 3, next: 3810)
        try await rig.step(probe: probe, to: 3810, waits: 6, verified: 4, next: 3820)
        // The last request began at 3810 and may wait until 3820, so collection must still run.
        #expect(owner.isRunning)
        #expect(rig.collectionScheduler.nextDeadline == 3820)
        #expect(manager.stops == 0)

        rig.advance(to: 3820)
        try #require(await settleOnMain {
            coordinator.deadlineTasks[id] == nil && rig.scheduler.pendingCount == 0 &&
                !owner.isRunning && rig.collectionSettled
        }, "retries must exhaust and collection stop at the entry cap")
        #expect(manager.starts == 1)
        #expect(manager.stops == 1)
        #expect(probe.verified == Array(repeating: id, count: 4))
        #expect(probe.waits == [3600, 1800, 1800, 60, 60, 60].map { UInt64($0) * 1000000000 })
        #expect(await setup.emitter.dwells().isEmpty)
        #expect(await setup.storage.getDwellVisit(geofenceId: id)?.visitId == visitId)
    }

    /// A crossing held for a polygon is released when a refresh replaces that fence: circle routing
    /// never judges a held crossing, so kept it would refuse every later first DWELL for the id. It is
    /// noted as the circle's crossing, or dropped with a fence the refresh removed.
    @Test(arguments: [true, false])
    func heldPolygonCrossing_whenARefreshReplacesTheFence_isReleased(keptAsCircle: Bool) async throws {
        let setup = await makeSetup()
        try #require(await settleOnMain { setup.coordinator.polygonIdsLoaded })
        let id = setup.geofence.id
        setup.coordinator.noteEnter(geofenceId: id, occurredAt: Date().addingTimeInterval(-60), crossing: true)
        try #require(setup.coordinator.heldCoveringCrossings[id] != nil)
        let later = GeofenceDwellVisit(
            visitId: "later", enteredAt: Date(), geometryRevision: setup.geofence.dwellRevision, userId: "user-1",
            emitted: false, timing: .recorded(secondsAgo: 0, on: setup.clock)
        )
        try #require(setup.coordinator.correctionRefusesAdmission(of: later, geofenceId: id))
        let circle = Geofence(
            id: id, latitude: 0.5, longitude: 0.5, radius: 100, name: "Campus", transitionTypes: [.enter, .exit],
            lastUpdated: Date(timeIntervalSince1970: 2), dwellThresholdSeconds: 60
        )

        setup.coordinator.beginCatalogReplacement()
        setup.coordinator.rememberCatalog(keptAsCircle ? [circle] : [])

        #expect(setup.coordinator.heldCoveringCrossings[id] == nil)
        #expect((setup.coordinator.enterMarks[id]?.crossing != nil) == keptAsCircle)
        #expect(!setup.coordinator.correctionRefusesAdmission(of: later, geofenceId: id))
    }

    /// The lease's grace past the threshold is fixed at 220 s: the 120 s production retry spacing
    /// does not lengthen it, and neither a re-arm nor a copied ENTER extends it.
    @Test
    func pendingCollection_whenRetrySpacingIs120_thenGraceStays220AndNoRearmExtendsIt() async throws {
        let rig = try await makeCollectionRig(evidenceRetryDelay: 120)
        defer { rig.cancelWaits() }
        let coordinator = rig.setup.coordinator, id = rig.setup.geofence.id
        let capNanos = UInt64(rig.clock.uptime + 60 + 220) * 1000000000
        await coordinator.handleBoundary(geofence: rig.setup.geofence, transition: .enter, occurredAt: rig.at(0))
        try await rig.settle(running: true, nextExpiry: 280)
        #expect(rig.owner.leases[id]?.deadline == capNanos)

        rig.advance(to: 30)
        await coordinator.rearmPendingEvidence(includePolygons: true)
        await coordinator.handleBoundary(geofence: rig.setup.geofence, transition: .enter, occurredAt: rig.at(0))
        try await rig.settle(running: true, nextExpiry: 280)
        #expect(rig.owner.leases[id]?.deadline == capNanos)
    }

    /// Two pending polygon visits share one opted-in session. Each EXIT releases only its own visit's
    /// lease: the first departure leaves the other visit collecting toward its own cap, the last stops it.
    @Test
    func pendingCollection_whenTwoPolygonVisitsExitInTurn_thenSessionRunsUntilTheLastEnds() async throws {
        let rig = try await makeCollectionRig()
        defer { rig.cancelWaits() }
        let first = rig.setup.geofence, second = await addSecondPolygon(to: rig.setup)
        let coordinator = rig.setup.coordinator
        await coordinator.handleBoundary(geofence: first, transition: .enter, occurredAt: rig.at(0))
        rig.advance(to: 10)
        await coordinator.handleBoundary(geofence: second, transition: .enter, occurredAt: rig.at(10))
        // One session; its expiry wait is the earlier cap: entry + 60 s threshold + 220 s grace.
        try await rig.settle(running: true, nextExpiry: 280)
        let secondVisit = try #require(await rig.setup.storage.getDwellVisit(geofenceId: second.id))
        let secondLease = try #require(rig.owner.leases[second.id])
        #expect(secondLease.visit.visitId == secondVisit.visitId)
        #expect(rig.owner.leases[first.id] != nil)

        rig.advance(to: 20)
        await coordinator.handleBoundary(geofence: first, transition: .exit, occurredAt: rig.at(20))
        // The other visit keeps its own lease and cap, which now sets the expiry.
        try await rig.settle(running: true, nextExpiry: 290)
        #expect(rig.owner.leases[first.id] == nil)
        #expect(rig.owner.leases[second.id]?.visit.visitId == secondVisit.visitId)
        #expect(rig.owner.leases[second.id]?.deadline == secondLease.deadline)
        #expect(rig.manager.starts == 1)
        #expect(rig.manager.stops == 0)

        rig.advance(to: 30)
        await coordinator.handleBoundary(geofence: second, transition: .exit, occurredAt: rig.at(30))
        try await rig.settle(running: false)
        #expect(rig.owner.leases.isEmpty)
        #expect(rig.manager.starts == 1)
        #expect(rig.manager.stops == 1)
    }

    /// The refresh's own reconcile drops a lease as soon as the catalog it persisted stops describing
    /// the visit: replaced geometry, then an unregistered fence. A visit the catalog still describes
    /// keeps the session; once no lease is left it stops.
    @Test
    func pendingCollection_whenRefreshRevisesThenUnregistersFences_thenDropsEachLeaseAtOnce() async throws {
        let rig = try await makeCollectionRig()
        defer { rig.cancelWaits() }
        let first = rig.setup.geofence, second = await addSecondPolygon(to: rig.setup)
        let coordinator = rig.setup.coordinator, storage = rig.setup.storage
        let revisedFirst = Self.pendingPolygon(first.id, apex: LocationData(latitude: 1, longitude: 1))
        try #require(revisedFirst.dwellRevision != first.dwellRevision)
        await coordinator.handleBoundary(geofence: first, transition: .enter, occurredAt: rig.at(0))
        rig.advance(to: 10)
        await coordinator.handleBoundary(geofence: second, transition: .enter, occurredAt: rig.at(10))
        try await rig.settle(running: true, nextExpiry: 280)
        let secondVisitId = try #require(rig.owner.leases[second.id]?.visit.visitId)

        await storage.setCachedGeofences([revisedFirst, second])
        coordinator.reconcileCollection(geofences: [revisedFirst, second], registeredIds: [first.id, second.id])
        // Read before any await, so no later storage read can be what dropped it.
        #expect(rig.owner.leases[first.id] == nil)
        #expect(rig.owner.leases[second.id]?.visit.visitId == secondVisitId)
        #expect(rig.owner.isRunning)
        try await rig.settle(running: true, nextExpiry: 290)
        #expect(rig.manager.stops == 0)

        await storage.setCachedGeofences([revisedFirst])
        await storage.recordRegistration(
            center: LocationData(latitude: 0.5, longitude: 0.5), businessIds: [first.id]
        )
        coordinator.reconcileCollection(geofences: [revisedFirst], registeredIds: [first.id])
        #expect(rig.owner.leases.isEmpty)
        #expect(!rig.owner.isRunning)
        #expect(rig.manager.stops == 1)
        try await rig.settle(running: false)
        #expect(rig.manager.starts == 1)
    }

    /// A reserved dwell only repeats its delivery, so collection stops at the reservation: while the
    /// outbox write is still suspended, and still after it fails and leaves the visit unemitted.
    @Test
    func pendingCollection_whenDwellReservedButDeliveryHangsThenFails_thenStopsAtReservation() async throws {
        let suspending = SuspendingDwellEmitter()
        let rig = try await makeCollectionRig(transitionEmitter: suspending)
        defer { rig.cancelWaits() }
        let geofence = rig.setup.geofence, coordinator = rig.setup.coordinator
        await coordinator.handleBoundary(geofence: geofence, transition: .enter, occurredAt: rig.at(0))
        try await rig.settle(running: true, nextExpiry: 280)

        // Inside evidence a polygon pass already validated, past the 60 s threshold. Only the clock
        // moves, so the deadline's own wait stays parked and adds no request.
        let observedAt = rig.at(61)
        rig.clock.advance(to: observedAt)
        let emission = Task { @MainActor in
            await coordinator.recordInsideEvidence(geofence: geofence, at: observedAt, source: "location_evidence")
        }
        await suspending.waitUntilSuspended()
        #expect(!rig.owner.isRunning)
        #expect(rig.owner.leases.isEmpty)
        #expect(rig.manager.stops == 1)

        await suspending.resume(returning: false)
        await emission.value
        let visit = try #require(await rig.setup.storage.getDwellVisit(geofenceId: geofence.id))
        #expect(visit.dwellReservation != nil)
        #expect(!visit.emitted)
        try await rig.settle(running: false)
        #expect(rig.manager.starts == 1)
        #expect(rig.manager.stops == 1)
    }

    @Test
    func diagnostics_whenIdentityCleanupCancelsDeadline_thenRetiredFenceDoesNotReappear() async throws {
        let clock = ManualGeofenceClock(), scheduler = ReplayDwellScheduler()
        let history = makeDiagnosticHistory(clock: clock)
        defer {
            scheduler.cancelAll()
            try? FileManager.default.removeItem(at: history.directory)
        }
        let setup = await makeSetup(
            clock: clock, diagnosticRecorder: history.recorder, observeIdentity: true,
            waitForEvidence: { @MainActor delay in try await scheduler.sleep(nanoseconds: delay) }
        )
        history.identity.tracker = setup.coordinator.identityTracker
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        await history.recorder.drain()
        let scheduled = try #require(await history.journal.snapshot())
        #expect(scheduled.contains { $0.event == .deadlineScheduled && $0.fenceId == setup.geofence.id })

        setup.coordinator.contextStore.setUserId("user-2")
        await setup.coordinator.identityChanged()
        await history.recorder.drain()

        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
        #expect(await history.journal.snapshot() == [], "cancelling the retired visit must not repopulate its erased history")
    }

    @Test
    func diagnostics_whenOutboxCompletesAfterIdentityChange_thenOldEmissionStaysErased() async throws {
        let clock = ManualGeofenceClock(), scheduler = ReplayDwellScheduler()
        let history = makeDiagnosticHistory(clock: clock), emitter = SuspendingDwellEmitter()
        defer {
            scheduler.cancelAll()
            try? FileManager.default.removeItem(at: history.directory)
        }
        let setup = await makeSetup(
            transitionEmitter: emitter, clock: clock, diagnosticRecorder: history.recorder, observeIdentity: true,
            waitForEvidence: { @MainActor delay in try await scheduler.sleep(nanoseconds: delay) }
        )
        history.identity.tracker = setup.coordinator.identityTracker
        let coordinator = setup.coordinator
        await coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(to: clock.wall.addingTimeInterval(61))
        let emission = Task { @MainActor in
            await coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")
        }
        await emitter.waitUntilSuspended()
        coordinator.contextStore.setUserId("user-2")
        await coordinator.identityChanged()
        await history.recorder.drain()
        #expect(await history.journal.snapshot() == [], "the retired deadline's cancellation must stay erased")

        // The old outbox row committed before the switch, but its completion reaches the caller later.
        await emitter.resume(returning: true)
        await emission.value
        await history.recorder.drain()
        #expect(await history.journal.snapshot() == [], "the old delivery's completion must retain its original diagnostic generation")
    }

    private struct DiagnosticHistory {
        let journal: DwellDiagnosticJournal
        let recorder: DwellDiagnosticRecorder
        let directory: URL
        let identity: DiagnosticIdentityProbe
    }

    private func makeDiagnosticHistory(clock: GeofenceClock) -> DiagnosticHistory {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let journal = DwellDiagnosticJournal(directory: directory, isEnabled: { true })
        let identity = DiagnosticIdentityProbe()
        let recorder = DwellDiagnosticRecorder(
            journal: journal, isEnabled: true, now: { clock.read().uptime },
            identityProvider: { identity.tracker?.currentIdentity }
        )
        return DiagnosticHistory(journal: journal, recorder: recorder, directory: directory, identity: identity)
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
        dwellProofSpacing: TimeInterval? = nil,
        // Private by default: suites running alongside post `willEnterForeground` on `.default` (the
        // replay harness does), and each post re-arms every live coordinator — resetting retry
        // budgets and spending scripted fixes mid-test.
        notificationCenter: NotificationCenter = NotificationCenter(),
        // Shared by two setups to model a relaunch over the same persisted state.
        directory: URL? = nil,
        clock: GeofenceClock = SystemGeofenceClock(),
        locationAccess: (@MainActor () -> GeofenceLocationAccess?)? = nil,
        fileManager: FileManager = .default,
        pendingDwellCollection: PendingDwellCollectionOwner? = nil,
        diagnosticRecorder: DwellDiagnosticRecorder? = nil,
        observeIdentity: Bool = false,
        waitForEvidence: @escaping @MainActor (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) async -> Setup {
        let directory = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = GeofenceStorage(fileManager: fileManager, directoryURL: directory)
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
        let logger = LoggerMock()
        let coordinator = GeofenceDwellCoordinator(
            storage: storage,
            transitionEmitter: transitionEmitter ?? emitter,
            contextStore: contextStore,
            logger: logger,
            notificationCenter: notificationCenter,
            freshFixProvider: freshFixProvider,
            evidenceRetryDelay: evidenceRetryDelay,
            maxEvidenceRetryAttempts: maxEvidenceRetryAttempts,
            dwellProofSpacing: dwellProofSpacing,
            clock: clock,
            locationAccess: locationAccess,
            identityTracker: observeIdentity ? GeofenceIdentityTracker(contextStore: contextStore) : nil,
            pendingDwellCollection: pendingDwellCollection,
            diagnosticRecorder: diagnosticRecorder,
            waitForEvidence: waitForEvidence
        )
        return Setup(
            storage: storage, emitter: emitter, coordinator: coordinator, geofence: geofence, directory: directory,
            clock: clock, logger: logger
        )
    }

    /// Enters a circle stay and qualifies its DWELL 60 s later, whose first delivery the emitter
    /// is scripted to refuse: the stay is left owing it.
    @discardableResult
    private func owe(_ setup: Setup, clock: ManualGeofenceClock) async throws -> GeofenceDwellVisit {
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(60)
        await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
        let visit = try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id))
        try #require(visit.owesDwell)
        return visit
    }

    private struct Setup {
        let storage: GeofenceStorage
        let emitter: DwellEmitterSpy
        let coordinator: GeofenceDwellCoordinator
        let geofence: Geofence
        let directory: URL
        let clock: GeofenceClock
        let logger: LoggerMock
    }

    /// A coordinator whose opted-in pending-dwell session, evidence waits and clock the test drives.
    /// No fix provider or polygon verifier is wired, so nothing here proves presence on its own.
    private func makeCollectionRig(
        transitionEmitter: GeofenceTransitionEmitting? = nil,
        dwellThresholdSeconds: Int = 60,
        evidenceRetryDelay: TimeInterval = 60,
        probe: PulseProbe? = nil
    ) async throws -> CollectionRig {
        let clock = ManualGeofenceClock()
        let scheduler = ReplayDwellScheduler(), collectionScheduler = ReplayDwellScheduler()
        let manager = FakePendingDwellManager()
        let optInInfo: [String: Any] = [PendingDwellCollectionOptIn.key: true, "UIBackgroundModes": ["location"]]
        let owner = try #require(PendingDwellCollectionOwner.ifOptedIn(
            PendingDwellCollectionOptIn(infoValue: { optInInfo[$0] }),
            makeManager: { manager },
            sleep: { @MainActor delay in try await collectionScheduler.sleep(nanoseconds: delay) }
        ))
        let setup = await makeSetup(
            transitionEmitter: transitionEmitter,
            dwellThresholdSeconds: dwellThresholdSeconds,
            evidenceRetryDelay: evidenceRetryDelay,
            clock: clock,
            locationAccess: { GeofenceLocationAccess(delivery: .background, fullAccuracy: true) },
            pendingDwellCollection: owner,
            waitForEvidence: { @MainActor delay in
                probe?.waits.append(delay)
                try await scheduler.sleep(nanoseconds: delay)
            }
        )
        return CollectionRig(
            setup: setup, owner: owner, manager: manager, clock: clock,
            scheduler: scheduler, collectionScheduler: collectionScheduler, start: clock.wall
        )
    }

    /// Caches and registers a second pending polygon beside `setup.geofence`, as a refresh would.
    private func addSecondPolygon(to setup: Setup) async -> Geofence {
        let second = Self.pendingPolygon("polygon-b")
        await setup.storage.setCachedGeofences([setup.geofence, second])
        await setup.storage.recordRegistration(
            center: LocationData(latitude: 0.5, longitude: 0.5), businessIds: [setup.geofence.id, second.id]
        )
        return second
    }

    /// `makeSetup`'s polygon with another `id` and third vertex; only those can change its revision.
    private static func pendingPolygon(
        _ id: String, apex: LocationData = LocationData(latitude: 1, longitude: 0)
    ) -> Geofence {
        Geofence(
            id: id, latitude: 0.5, longitude: 0.5, radius: 100, name: "Campus", transitionTypes: [.enter, .exit],
            lastUpdated: Date(timeIntervalSince1970: 1),
            vertices: [LocationData(latitude: 0, longitude: 0), LocationData(latitude: 0, longitude: 1), apex],
            dwellThresholdSeconds: 60
        )
    }

    /// What `makeCollectionRig` built. Moments are seconds after it was built, on every clock.
    @MainActor
    private struct CollectionRig {
        let setup: Setup
        let owner: PendingDwellCollectionOwner
        let manager: FakePendingDwellManager
        let clock: ManualGeofenceClock
        let scheduler: ReplayDwellScheduler
        let collectionScheduler: ReplayDwellScheduler
        let start: Date

        func at(_ moment: TimeInterval) -> Date {
            start.addingTimeInterval(moment)
        }

        func advance(to moment: TimeInterval) {
            clock.advance(to: at(moment))
            scheduler.advance(to: moment)
            collectionScheduler.advance(to: moment)
        }

        /// Running with its one expiry wait parked at `nextExpiry`, or stopped with none parked, so no
        /// collection reconcile is still in flight.
        func settle(running: Bool, nextExpiry: TimeInterval? = nil) async throws {
            try #require(await settleOnMain {
                owner.isRunning == running && collectionScheduler.pendingCount == (running ? 1 : 0)
                    && (nextExpiry == nil || collectionScheduler.nextDeadline == nextExpiry)
            }, "collection did not settle: running=\(running) nextExpiry=\(String(describing: nextExpiry))")
        }

        /// Running only while its one expiry wait is parked.
        var collectionSettled: Bool {
            owner.isRunning == (collectionScheduler.pendingCount == 1)
        }

        func step(probe: PulseProbe, to moment: TimeInterval, waits: Int, verified: Int, next: TimeInterval) async throws {
            advance(to: moment)
            try #require(await settleOnMain {
                probe.waits.count == waits && probe.verified.count == verified &&
                    scheduler.pendingCount == 1 && scheduler.nextDeadline == next && collectionSettled
            }, "evidence chain stalled at t=\(moment)")
        }

        func cancelWaits() {
            scheduler.cancelAll()
            collectionScheduler.cancelAll()
        }
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

/// Stands in for the session's location manager: counts start and stop, delivers nothing.
private final class FakePendingDwellManager: NSObject, PendingDwellLocationManaging {
    var onActivity: (@MainActor (PendingDwellSessionCallback) -> Void)?
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    var distanceFilter: CLLocationDistance = kCLDistanceFilterNone
    var allowsBackgroundLocationUpdates = false
    var pausesLocationUpdatesAutomatically = true
    private(set) var starts = 0
    private(set) var stops = 0

    func startUpdatingLocation() {
        starts += 1
    }

    func stopUpdatingLocation() {
        stops += 1
    }
}

/// What the coordinator's injected waits and polygon verifier saw.
@MainActor
private final class PulseProbe {
    var waits: [UInt64] = []
    var verified: [String] = []
}

private actor DwellEmitterSpy: GeofenceTransitionEmitting {
    struct Invocation: Sendable {
        let geofenceId: String
        let occurredAt: Date
        let context: GeofenceDwellContext
    }

    private var results: [Bool]
    /// Outcomes for the next deliveries, before `results`: a refusal for good is only told here.
    private var deliveries: [GeofenceDwellDelivery]
    private var invocations: [Invocation] = []
    private var exits = 0

    init(results: [Bool] = [true], deliveries: [GeofenceDwellDelivery] = []) {
        self.results = results
        self.deliveries = deliveries
    }

    func deliverDwell(
        geofenceId: String, occurredAt: Date, context: GeofenceDwellContext, expectedUserId: String?
    ) async -> GeofenceDwellDelivery {
        invocations.append(Invocation(geofenceId: geofenceId, occurredAt: occurredAt, context: context))
        if !deliveries.isEmpty { return deliveries.removeFirst() }
        return results.isEmpty || results.removeFirst() ? .persisted : .writeFailed
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
        await deliverDwell(geofenceId: geofenceId, occurredAt: occurredAt, context: context, expectedUserId: expectedUserId)
            == .persisted
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

/// Blocks one real storage read while the main actor replaces its deadline. The bound prevents a
/// failed test from keeping the storage actor parked indefinitely.
private final class BlockingDwellReadFileManager: FileManager, @unchecked Sendable {
    private let lock = NSLock()
    private let release = DispatchSemaphore(value: 0)
    private var nextReadBlocked = false
    private var blocked = false
    private var timedOut = false

    var isBlocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return blocked
    }

    var readTimedOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timedOut
    }

    func blockNextRead() {
        lock.lock()
        nextReadBlocked = true
        lock.unlock()
    }

    func releaseRead() {
        release.signal()
    }

    override func fileExists(atPath path: String) -> Bool {
        lock.lock()
        let shouldBlock = nextReadBlocked
        nextReadBlocked = false
        if shouldBlock { blocked = true }
        lock.unlock()
        if shouldBlock {
            let result = release.wait(timeout: .now() + 5)
            lock.lock()
            timedOut = result == .timedOut
            blocked = false
            lock.unlock()
        }
        return super.fileExists(atPath: path)
    }
}

@MainActor
private final class DiagnosticIdentityProbe {
    var tracker: GeofenceIdentityTracker?
}

/// Location access a test changes under a live coordinator.
@MainActor
private final class MutableAccess {
    var value: GeofenceLocationAccess?

    init(_ value: GeofenceLocationAccess?) {
        self.value = value
    }
}

/// A flag a test flips from inside a storage hook.
@MainActor
private final class MutableFlag {
    var value = false
}
