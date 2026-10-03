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

/// When a completed visit's EXIT may carry its duration: only for a visit whose entry and exit
/// were both observed crossings on one uninterrupted, coherent timeline. Every clock is a
/// `ManualGeofenceClock`, so wall time and uptime move only as each test says.
@Suite("GeofenceExitDurationContinuity", .serialized)
@MainActor
struct GeofenceExitDurationContinuityTests {
    // MARK: - Trustworthy visits

    /// Zero is a measured duration, not a missing one: it is reported, and the payload carries it.
    @Test
    func exitInTheSameSecondAsTheEntryReportsZero() async throws {
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1000000.2))
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(0.5)

        let context = try #require(await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        ))

        #expect(context.durationSeconds == 0)
        let properties = try Self.payload(exitedAt: clock.wall, context: context)
        #expect(properties["visitDurationSeconds"] as? Int == 0)
        #expect(properties["enteredAt"] as? Int == 1000000)
    }

    /// A threshold-disabled, EXIT-only fence still times its visits: duration does not depend on
    /// dwell. A same-boot stay of a month, with nothing interrupting it, is reported in full.
    @Test
    func uninterruptedMonthLongVisitOnAnExitOnlyFenceReportsItsWholeDuration() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        let enteredAt = clock.wall
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)

        clock.advance(30 * 86400)
        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        )

        #expect(context?.enteredAt == enteredAt)
        #expect(context?.durationSeconds == 30 * 86400)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    /// The EXIT is processed well after it happened — a cold launch — and is still timed from its
    /// own date, as the whole epoch seconds the event carries.
    @Test
    func lateProcessedExitIsTimedFromItsOwnDate() async {
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1000000.9))
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(59.2)
        let exitedAt = clock.wall
        clock.advance(600)

        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: exitedAt
        )

        #expect(context?.durationSeconds == 60)
        #expect(context?.durationSeconds == Int(exitedAt.timeIntervalSince1970) - 1000000)
    }

    // MARK: - Wall-clock steps

    /// A clock running two hours fast is corrected mid-visit. The EXIT is dated before the entry
    /// on the wall clock, but it is the real EXIT of this visit: it must end it, and report no
    /// duration across the step.
    @Test
    func backwardStepExitEndsTheVisitWithoutADuration() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)

        clock.advance(600)
        clock.stepWall(-7200)
        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        )

        #expect(context == nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    /// After the backward step's EXIT, a re-entry opens a distinct visit that is timed normally.
    @Test
    func reentryAfterABackwardStepExitIsTimedFromItsOwnEntry() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let first = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        clock.advance(600)
        clock.stepWall(-7200)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: clock.wall)

        clock.advance(60)
        let reentry = clock.wall
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: reentry)
        clock.advance(90)
        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        )

        #expect(context?.visitId != first?.visitId)
        #expect(context?.enteredAt == reentry)
        #expect(context?.durationSeconds == 90)
    }

    /// An hour's forward step mid-visit: the wall clock reads an hour and a minute, but a minute
    /// passed. The EXIT ends the visit and reports no duration it cannot place on one timeline.
    @Test
    func forwardStepExitEndsTheVisitWithoutADuration() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)

        clock.advance(30)
        clock.stepWall(3600)
        clock.advance(30)
        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        )

        #expect(context == nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    /// The OS dated the ENTER, then the clock was set back 100 s before the SDK recorded it, so
    /// the entry reads 100 s in the future of its recording. 200 s pass; the wall clock would
    /// report 100.
    @Test
    func entryDatedAheadOfItsRecordingReportsNoDuration() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        let enteredAt = clock.wall.addingTimeInterval(100)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) != nil)

        clock.advance(200)
        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        )

        #expect(context == nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    /// The EXIT is dated 100 s ahead of the clock it is processed on: it was dated on a clock since
    /// set back, so its date is not on the visit's timeline. It ends the visit, untimed.
    @Test
    func exitDatedAheadOfItsProcessingReportsNoDuration() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)

        clock.advance(300)
        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall.addingTimeInterval(100)
        )

        #expect(context == nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    /// Sub-second disagreement is below the whole seconds the event carries: still timed.
    @Test
    func subSecondDriftStillReportsTheDuration() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)

        clock.advance(600)
        clock.stepWall(0.5)
        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        )

        #expect(context?.durationSeconds == 600)
    }

    // MARK: - Delayed and overlapping EXITs

    /// An EXIT delivered late after the clock was set back is dated ahead of the clock now. Across
    /// the step nothing says which clock dated it, so it cannot be told from this visit's own EXIT:
    /// the pair is unknown. It closes the visit, as every boundary check orders it
    /// (`GeofenceExitMark.overtakes`), and reports no duration. Under a coherent clock the same
    /// stale EXIT leaves the visit; see `delayedExitDatedBeforeTheVisitLeavesItAndReportsNothing`.
    @Test
    func exitDatedAheadOfASetBackClockClosesTheVisitUntimed() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        let exitDatedOnTheOldClock = clock.wall.addingTimeInterval(-100)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) != nil)

        clock.advance(600)
        clock.stepWall(-7200)
        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: exitDatedOnTheOldClock
        )

        #expect(context == nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    /// A delayed EXIT dated before the current visit's entry belongs to an older stay.
    @Test
    func delayedExitDatedBeforeTheVisitLeavesItAndReportsNothing() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        let staleExitAt = clock.wall
        clock.advance(30)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let visit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        clock.advance(30)

        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: staleExitAt
        )

        #expect(context == nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == visit)
    }

    /// The re-ENTER replaced the visit after the EXIT that ended it was seen but before that EXIT
    /// read the store. The EXIT still reports the replaced visit's duration, and the newer visit is
    /// left for its own EXIT. An EXIT refused for another user records itself first, which is the
    /// state such an EXIT leaves before its read.
    @Test
    func exitReadAfterAnOverlappingReentryReportsTheReplacedVisit() async throws {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        let firstEntry = clock.wall
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: firstEntry)
        let first = try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id))
        clock.advance(60)
        let exitedAt = clock.wall
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: exitedAt, expectedUserId: "someone-else"
        )
        clock.advance(1)
        let reentry = clock.wall
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: reentry)
        clock.advance(2)

        let closed = await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: exitedAt)

        #expect(closed?.visitId == first.visitId)
        #expect(closed?.durationSeconds == 60)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.enteredAt == reentry)
        clock.advance(120)
        let finalExit = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        )
        #expect(finalExit?.enteredAt == reentry)
        #expect(finalExit?.durationSeconds == 122)
    }

    /// The boundary flaps: the EXIT ending the first visit is still suspended when a re-entry and a
    /// second EXIT, both within a second of it, complete. That second EXIT ends the re-entry; it is
    /// a different EXIT, so it must leave the replaced visit for the EXIT that ended it.
    @Test
    func secondExitWithinASecondDoesNotTakeTheReplacedVisitFromItsOwnExit() async throws {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let first = try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id))
        clock.advance(60)
        let firstExit = clock.wall
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: firstExit, expectedUserId: "someone-else"
        )
        clock.advance(0.4)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let reentry = try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id))
        clock.advance(0.4)

        let secondExit = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        )
        let closed = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: firstExit
        )

        #expect(secondExit?.visitId == reentry.visitId)
        #expect(closed?.visitId == first.visitId)
        #expect(closed?.durationSeconds == 60)
    }

    /// A duplicate delivery of the EXIT, dated at its own receipt a fraction of a second later,
    /// reads the store after the re-entry: it ended no visit of its own, so it reports none, and
    /// the replaced visit stays with the EXIT that ended it.
    @Test
    func duplicateExitDeliveryDoesNotReportTheReplacedVisit() async throws {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let first = try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id))
        clock.advance(60)
        let firstExit = clock.wall
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: firstExit, expectedUserId: "someone-else"
        )
        clock.advance(1)
        let reentry = clock.wall
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: reentry)

        let duplicate = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: firstExit.addingTimeInterval(0.3)
        )
        let closed = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: firstExit
        )

        #expect(duplicate == nil)
        #expect(closed?.visitId == first.visitId)
        #expect(closed?.durationSeconds == 60)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.enteredAt == reentry)
    }

    /// A decisive outside fix has recorded its exit mark and is still removing the visit when the
    /// visit's EXIT reads it — the state `endContinuity` leaves across its storage hop. The fix saw
    /// the device away before this EXIT, so the stay may span an excursion: the EXIT ends the
    /// visit untimed.
    @Test
    func exitReadWhileOutsideEvidenceIsEndingTheVisitReportsNoDuration() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(120)
        setup.coordinator.recordExit(
            GeofenceExitMark(date: clock.wall, processedAt: clock.read(), source: .outsideEvidence),
            geofenceId: setup.geofence.id
        )
        clock.advance(60)

        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        )

        #expect(context == nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    /// The replaced visit's EXIT is still in flight, and outside evidence taken before that EXIT
    /// also ended the visit: an excursion the OS may have missed. The EXIT still reports no
    /// duration for it, and the re-entry is left for its own, timed EXIT.
    @Test
    func replacedVisitWithOutsideEvidenceBeforeItsExitIsReportedUntimed() async throws {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(30)
        setup.coordinator.recordExit(
            GeofenceExitMark(date: clock.wall, processedAt: clock.read(), source: .outsideEvidence),
            geofenceId: setup.geofence.id
        )
        clock.advance(30)
        let exitedAt = clock.wall
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: exitedAt, expectedUserId: "someone-else"
        )
        clock.advance(1)
        let reentry = clock.wall
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: reentry)
        let newer = try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id))

        let closed = await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: exitedAt)

        #expect(closed == nil)
        #expect(newer.enteredAt == reentry)
        clock.advance(90)
        let reentryExit = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        )
        #expect(reentryExit?.visitId == newer.visitId)
        #expect(reentryExit?.durationSeconds == 90)
    }

    /// The same overlap across an hour's forward step: the replaced visit is still the one the EXIT
    /// ended, but its wall-clock span crosses the step, so it is reported without a duration.
    @Test
    func overlappingReentryAcrossAForwardStepReportsTheReplacedVisitUntimed() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(60)
        clock.stepWall(3600)
        let exitedAt = clock.wall
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: exitedAt, expectedUserId: "someone-else"
        )
        clock.advance(1)
        let reentry = clock.wall
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: reentry)

        let closed = await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: exitedAt)

        #expect(closed == nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.enteredAt == reentry)
    }

    /// A loss recorded after the re-entry replaced the visit, before its EXIT was read. The replaced
    /// visit is judged by the same continuity check as a stored one, which a loss recorded since
    /// its entry ends whatever the EXIT's date: its EXIT is untimed.
    @Test
    func knownLossBeforeTheOverlappingExitIsReadLeavesItUntimed() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(60)
        let exitedAt = clock.wall
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: exitedAt, expectedUserId: "someone-else"
        )
        clock.advance(1)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(1)
        _ = setup.coordinator.continuityLost(geofenceId: setup.geofence.id)

        let closed = await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: exitedAt)

        #expect(closed == nil)
    }

    // MARK: - Interrupted continuity

    /// The phone restarted mid-visit. Uptime on the new boot has already passed the old visit's
    /// recording uptime, so only the boot identity tells them apart.
    @Test
    func exitAfterARebootWhoseUptimeIsAlreadyGreaterReportsNoDuration() async {
        let clock = ManualGeofenceClock(uptime: 100)
        let beforeReboot = await makeSetup(clock: clock)
        await beforeReboot.coordinator.handleBoundary(
            geofence: beforeReboot.geofence, transition: .enter, occurredAt: clock.wall
        )
        clock.reboot(secondsLater: 600, uptimeAfterBoot: 5000)
        let relaunched = await makeSetup(directory: beforeReboot.directory, clock: clock)

        let context = await relaunched.coordinator.handleBoundary(
            geofence: relaunched.geofence, transition: .exit, occurredAt: clock.wall
        )

        #expect(context == nil)
        #expect(await relaunched.storage.getDwellVisit(geofenceId: relaunched.geofence.id) == nil)
    }

    /// Same boot, a later process: the persisted visit's continuity holds, so its EXIT is timed.
    @Test
    func exitInALaterProcessOnTheSameBootIsTimed() async {
        let clock = ManualGeofenceClock()
        let firstProcess = await makeSetup(clock: clock, locationAccess: { Self.always })
        let enteredAt = clock.wall
        await firstProcess.coordinator.handleBoundary(
            geofence: firstProcess.geofence, transition: .enter, occurredAt: enteredAt
        )
        clock.advance(3 * 3600)
        let relaunched = await makeSetup(directory: firstProcess.directory, clock: clock, locationAccess: { Self.always })

        let context = await relaunched.coordinator.handleBoundary(
            geofence: relaunched.geofence, transition: .exit, occurredAt: clock.wall
        )

        #expect(context?.enteredAt == enteredAt)
        #expect(context?.durationSeconds == 3 * 3600)
    }

    /// A visit persisted by a build that kept no timing names no boot: its EXIT ends it, untimed.
    @Test
    func exitForAVisitPersistedWithoutTimingReportsNoDuration() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        let legacy = GeofenceDwellVisit(
            visitId: "legacy-visit", enteredAt: clock.wall, geometryRevision: setup.geofence.dwellRevision,
            userId: "user-1", emitted: false, timing: nil
        )
        #expect(await setup.storage.saveDwellVisit(legacy, geofenceId: setup.geofence.id))
        clock.advance(120)

        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        )

        #expect(context == nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    /// Monitoring was interrupted mid-visit; the EXIT arrives before the removal task has run.
    @Test(arguments: [true, false])
    func exitAfterAKnownLossReportsNoDuration(forOneFence: Bool) async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(60)
        _ = setup.coordinator.continuityLost(geofenceId: forOneFence ? setup.geofence.id : nil)
        clock.advance(60)

        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        )

        #expect(context == nil)
    }

    /// Location access dropped while the app was not running; nothing reported it.
    @Test
    func exitAfterLocationAccessDroppedReportsNoDuration() async {
        let clock = ManualGeofenceClock()
        let access = AccessBox(Self.always)
        let firstProcess = await makeSetup(clock: clock, locationAccess: { access.value })
        await firstProcess.coordinator.handleBoundary(
            geofence: firstProcess.geofence, transition: .enter, occurredAt: clock.wall
        )
        clock.advance(120)
        access.value = GeofenceLocationAccess(delivery: .background, fullAccuracy: false)
        let relaunched = await makeSetup(
            directory: firstProcess.directory, clock: clock, locationAccess: { access.value }
        )

        let context = await relaunched.coordinator.handleBoundary(
            geofence: relaunched.geofence, transition: .exit, occurredAt: clock.wall
        )

        #expect(context == nil)
    }

    #if canImport(UIKit)
    /// Background App Refresh went off and came back while inside: region events could not reach
    /// the app meanwhile, so the stay's EXIT is untimed.
    @Test
    func exitAfterBackgroundRefreshWasBrieflyOffReportsNoDuration() async {
        let clock = ManualGeofenceClock()
        let refresh = FlagBox(true)
        let center = NotificationCenter()
        let setup = await makeSetup(
            clock: clock, notificationCenter: center,
            locationAccess: { Self.always }, backgroundRefreshAvailable: { refresh.value }
        )
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(60)
        refresh.value = false
        center.post(name: UIApplication.backgroundRefreshStatusDidChangeNotification, object: nil)
        refresh.value = true
        center.post(name: UIApplication.backgroundRefreshStatusDidChangeNotification, object: nil)
        clock.advance(60)

        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        )

        #expect(context == nil)
    }
    #endif

    // MARK: - Unknown boundaries

    /// A healed or corrected EXIT is dated when it was noticed: it ends the observed visit untimed.
    @Test
    func discoveredExitOfAnObservedVisitReportsNoDuration() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(600)

        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall, crossingObserved: false
        )

        #expect(context == nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    /// A visit started from a discovered ENTER has no known start: its EXIT is untimed.
    @Test
    func observedExitOfADiscoveredVisitReportsNoDuration() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: clock.wall, crossingObserved: false
        )
        clock.advance(600)

        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        )

        #expect(context == nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    // MARK: - Decisive outside evidence

    /// A deadline fix wholly outside the circle ends the visit's continuity; no EXIT is made up for
    /// it. Core Location's real EXIT, when it finally comes, finds nothing to time. A fresh inside
    /// fix later starts a candidate — it supports a late dwell, but its start is not an entry, so
    /// the EXIT that follows it is untimed too.
    @Test
    func decisiveOutsideFixLeavesTheLaterExitUntimedAndALateCandidateUntimed() async {
        let clock = ManualGeofenceClock()
        let fixes = FixScript()
        let setup = await makeSetup(
            dwellThresholdSeconds: 60, transitionTypes: [.enter, .exit], clock: clock,
            freshFixProvider: { fixes.next() }
        )
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(120)
        fixes.queue(Self.fix(latitude: 0.51, accuracy: 5, at: clock.wall))
        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)

        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
        #expect(await setup.emitter.exitCount() == 0)
        #expect(await setup.emitter.dwellCount() == 0)

        clock.advance(300)
        let untimed = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        )
        #expect(untimed == nil)

        clock.advance(60)
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence, at: clock.wall, source: "location_evidence"
        )
        let candidate = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        #expect(candidate?.entryObserved == false)
        clock.advance(120)
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence, at: clock.wall, source: "location_evidence"
        )
        #expect(await setup.emitter.dwellCount() == 1)
        clock.advance(30)
        let candidateExit = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: clock.wall
        )
        #expect(candidateExit == nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    // MARK: - Payload

    /// An untimed EXIT carries none of the visit fields; a timed one carries them on every geoset
    /// row, under one transition id distinct from the visit id, through the outbox encoding.
    @Test
    func payloadOmitsVisitFieldsForAnUntimedExitAndFansATimedOneOut() throws {
        let exitedAt = Date(timeIntervalSince1970: 1000075.4)
        let untimed = try Self.payload(exitedAt: exitedAt, context: nil)
        for key in ["visitId", "enteredAt", "visitDurationSeconds", "dwellDurationSeconds", "detectionSource"] {
            #expect(untimed[key] == nil, "untimed EXIT carried \(key)")
        }

        let context = GeofenceExitContext(
            visitId: "visit-1", enteredAt: Date(timeIntervalSince1970: 1000000.9),
            durationSeconds: 75, detectionSource: "native"
        )
        let geofence = Geofence(
            id: "fence", latitude: 0.5, longitude: 0.5, radius: 100, name: "Campus",
            transitionTypes: [.exit], lastUpdated: Date(timeIntervalSince1970: 1), geosetIds: ["a", "b"]
        )
        let rows = try Self.roundTripped(
            GeofenceCrossing(
                geofenceId: geofence.id, transition: .exit, occurredAt: exitedAt,
                dwell: nil, exit: context, expectedUserId: nil
            ).pendingMetrics(userId: "user-1", cachedGeofence: geofence)
        )
        try #require(rows.count == 2)
        #expect(Set(rows.map(\.transitionId)).count == 1)
        #expect(rows[0].transitionId != "visit-1")
        for row in rows {
            let properties = row.trackEventProperties
            #expect(properties["visitId"] as? String == "visit-1")
            #expect(properties["enteredAt"] as? Int == 1000000)
            #expect(properties["visitDurationSeconds"] as? Int == 75)
            #expect(properties["detectionSource"] as? String == "native")
            #expect(properties["dwellDurationSeconds"] == nil)
        }
    }

    // MARK: - Helpers

    private static let always = GeofenceLocationAccess(delivery: .background, fullAccuracy: true)

    /// The `/track` properties of a single-row EXIT, after an outbox encode/decode.
    private static func payload(exitedAt: Date, context: GeofenceExitContext?) throws -> [String: Any] {
        let rows = try roundTripped(
            GeofenceCrossing(
                geofenceId: "fence", transition: .exit, occurredAt: exitedAt,
                dwell: nil, exit: context, expectedUserId: nil
            ).pendingMetrics(userId: "user-1", cachedGeofence: nil)
        )
        try #require(rows.count == 1)
        return rows[0].trackEventProperties
    }

    private static func roundTripped(_ rows: [PendingGeofenceMetric]) throws -> [PendingGeofenceMetric] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode([PendingGeofenceMetric].self, from: encoder.encode(rows))
    }

    private func makeSetup(
        dwellThresholdSeconds: Int = 0,
        transitionTypes: Set<GeofenceTransition> = [.exit],
        directory: URL? = nil,
        clock: ManualGeofenceClock,
        freshFixProvider: @escaping () async -> CLLocation? = { nil },
        // Private by default: other suites post lifecycle notifications on `.default`.
        notificationCenter: NotificationCenter = NotificationCenter(),
        locationAccess: (@MainActor () -> GeofenceLocationAccess?)? = nil,
        backgroundRefreshAvailable: (@MainActor () -> Bool)? = nil
    ) async -> Setup {
        let directory = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = GeofenceStorage(fileManager: .default, directoryURL: directory)
        let contextStore = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        contextStore.setUserId("user-1")
        let geofence = Geofence(
            id: "fence",
            latitude: 0.5,
            longitude: 0.5,
            radius: 100,
            name: "Campus",
            transitionTypes: transitionTypes,
            lastUpdated: Date(timeIntervalSince1970: 1),
            dwellThresholdSeconds: dwellThresholdSeconds
        )
        await storage.setCachedGeofences([geofence])
        await storage.recordRegistration(
            center: LocationData(latitude: geofence.latitude, longitude: geofence.longitude),
            businessIds: [geofence.id]
        )
        let spy = ExitDurationEmitterSpy()
        let coordinator = GeofenceDwellCoordinator(
            storage: storage,
            transitionEmitter: spy,
            contextStore: contextStore,
            logger: LoggerMock(),
            notificationCenter: notificationCenter,
            freshFixProvider: freshFixProvider,
            clock: clock,
            locationAccess: locationAccess,
            backgroundRefreshAvailable: backgroundRefreshAvailable
        )
        return Setup(storage: storage, emitter: spy, coordinator: coordinator, geofence: geofence, directory: directory)
    }

    private struct Setup {
        let storage: GeofenceStorage
        let emitter: ExitDurationEmitterSpy
        let coordinator: GeofenceDwellCoordinator
        let geofence: Geofence
        let directory: URL
    }

    /// A fix at `latitude` on the fence's meridian; 0.01° is about 1.1 km.
    private static func fix(latitude: Double, accuracy: Double, at timestamp: Date) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: 0.5),
            altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 10, timestamp: timestamp
        )
    }
}

@MainActor
private final class FlagBox {
    var value: Bool

    init(_ value: Bool) {
        self.value = value
    }
}

@MainActor
private final class AccessBox {
    var value: GeofenceLocationAccess

    init(_ value: GeofenceLocationAccess) {
        self.value = value
    }
}

/// Answers each fix request with the next queued fix; nil when none is queued.
@MainActor
private final class FixScript {
    private var fixes: [CLLocation] = []

    func queue(_ fix: CLLocation) {
        fixes.append(fix)
    }

    func next() -> CLLocation? {
        fixes.isEmpty ? nil : fixes.removeFirst()
    }
}

private actor ExitDurationEmitterSpy: GeofenceTransitionEmitting {
    private var exits = 0
    private var dwells = 0

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
        dwells += 1
        return true
    }

    func exitCount() -> Int {
        exits
    }

    func dwellCount() -> Int {
        dwells
    }
}
