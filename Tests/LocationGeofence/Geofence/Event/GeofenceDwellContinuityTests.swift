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

/// What a visit's continuity survives and what ends it: wall-clock steps, reboots, interruptions,
/// location-access loss and decisive outside evidence. Every clock is a `ManualGeofenceClock`, so
/// wall time and uptime move only as each test says.
@Suite("GeofenceDwellContinuity", .serialized)
@MainActor
struct GeofenceDwellContinuityTests {
    // MARK: - Wall-clock steps

    /// An hour's forward step 60 s into a 600 s threshold. A fix 90 s after the entry reads an hour
    /// and a half on the wall clock, but only 90 s have passed.
    @Test
    func forwardWallClockStepDoesNotQualifyADwellEarly() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(dwellThresholdSeconds: 600, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)

        clock.advance(60)
        clock.stepWall(3600)
        clock.advance(30)
        await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")

        #expect(await setup.emitter.dwells().isEmpty)

        clock.advance(510)
        await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")

        let dwells = await setup.emitter.dwells()
        #expect(dwells.count == 1)
        // The entry is on the timeline before the step, so no wall-clock span to it is reportable.
        #expect(dwells.first?.context.enteredAt == nil)
        #expect(dwells.first?.context.durationSeconds == nil)
    }

    /// A clock running two hours fast is corrected while the device is inside. The EXIT that
    /// follows is dated before the entry on the wall clock, yet it ends this visit, and the next
    /// ENTER opens a distinct one.
    @Test
    func backwardWallClockStepStillLetsTheExitEndTheVisitAndTheReentryOpenAnother() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let first = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)

        clock.advance(600)
        clock.stepWall(-7200)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: clock.wall)

        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)

        clock.advance(600)
        let reentryAt = clock.wall
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: reentryAt)

        let second = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        #expect(second != nil)
        #expect(second?.visitId != first?.visitId)
        #expect(second?.enteredAt == reentryAt)
    }

    /// A backward step leaves less wall time than has passed. The dwell still qualifies on the
    /// time that did pass, and reports no entry it cannot place on the current timeline.
    @Test
    func backwardWallClockStepQualifiesOnElapsedTimeWithoutReportingTheEntry() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(dwellThresholdSeconds: 600, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)

        clock.advance(300)
        clock.stepWall(-3600)
        clock.advance(300)
        await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")

        let dwells = await setup.emitter.dwells()
        #expect(dwells.count == 1)
        #expect(dwells.first?.context.enteredAt == nil)
        #expect(dwells.first?.context.durationSeconds == nil)
    }

    /// Disagreement under a second is below the whole seconds the event reports: the stay still
    /// reports its entry and duration.
    @Test
    func subSecondWallClockDriftStillReportsTheEntryAndDuration() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(dwellThresholdSeconds: 600, clock: clock)
        let enteredAt = clock.wall
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)

        clock.advance(600)
        clock.stepWall(0.5)
        await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")

        let dwell = await setup.emitter.dwells().first
        #expect(dwell?.context.enteredAt == enteredAt)
        #expect(dwell?.context.durationSeconds == 600)
    }

    /// A two-second step is a displacement the event's whole seconds would carry: the dwell still
    /// qualifies on monotonic time, but reports neither the entry nor a duration across the step.
    @Test(arguments: [2.0, -2.0])
    func wallClockStepOfWholeSecondsWithholdsTheEntryAndDuration(step: TimeInterval) async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(dwellThresholdSeconds: 600, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)

        clock.advance(300)
        clock.stepWall(step)
        clock.advance(300)
        await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")

        let dwells = await setup.emitter.dwells()
        #expect(dwells.count == 1)
        #expect(dwells.first?.context.enteredAt == nil)
        #expect(dwells.first?.context.durationSeconds == nil)
    }

    // MARK: - Boot

    /// The phone restarts mid-visit; the adopted region raises nothing on boot. Nothing watched the
    /// fence while the device was off, so the stored visit is gone, and an inside fix afterwards
    /// starts over rather than qualifying it.
    @Test
    func persistedVisitFromAnEarlierBootIsDroppedOnResume() async {
        let clock = ManualGeofenceClock()
        let beforeReboot = await makeSetup(clock: clock)
        await beforeReboot.coordinator.handleBoundary(
            geofence: beforeReboot.geofence, transition: .enter, occurredAt: clock.wall
        )

        clock.reboot(secondsLater: 600)
        let afterReboot = await makeSetup(directory: beforeReboot.directory, clock: clock)
        await afterReboot.coordinator.resumePendingVisits(geofences: [afterReboot.geofence])

        #expect(await afterReboot.storage.getDwellVisit(geofenceId: afterReboot.geofence.id) == nil)

        await afterReboot.coordinator.recordInsideEvidence(
            geofence: afterReboot.geofence, at: clock.wall, source: "location_evidence"
        )
        #expect(await afterReboot.emitter.dwells().isEmpty)
    }

    /// A process relaunch on the same boot is not an interruption: the stored visit resumes and
    /// qualifies with its identity and entry intact.
    @Test
    func persistedVisitFromThisBootSurvivesAProcessRelaunch() async {
        let clock = ManualGeofenceClock()
        let beforeRelaunch = await makeSetup(clock: clock)
        let enteredAt = clock.wall
        await beforeRelaunch.coordinator.handleBoundary(
            geofence: beforeRelaunch.geofence, transition: .enter, occurredAt: enteredAt
        )
        let visit = await beforeRelaunch.storage.getDwellVisit(geofenceId: beforeRelaunch.geofence.id)

        clock.advance(120)
        let relaunched = await makeSetup(directory: beforeRelaunch.directory, clock: clock)
        await relaunched.coordinator.recordInsideEvidence(
            geofence: relaunched.geofence, at: clock.wall, source: "location_evidence"
        )

        let dwell = await relaunched.emitter.dwells().first
        #expect(dwell?.context.visitId == visit?.visitId)
        #expect(dwell?.context.enteredAt == enteredAt)
        #expect(dwell?.context.durationSeconds == 120)
    }

    /// A visit stored by a build that recorded no timing says nothing about which boot it began
    /// on, so it supports no dwell.
    @Test
    func visitPersistedWithoutTimingSupportsNoDwell() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        let legacy = GeofenceDwellVisit(
            visitId: "legacy-visit", enteredAt: clock.wall, geometryRevision: setup.geofence.dwellRevision,
            userId: "user-1", emitted: false, timing: nil
        )
        #expect(await setup.storage.saveDwellVisit(legacy, geofenceId: setup.geofence.id))

        clock.advance(600)
        await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")

        #expect(await setup.emitter.dwells().isEmpty)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.visitId != legacy.visitId)
    }

    // MARK: - Interruption

    /// A loss is dated when it is seen; its removal may land later. A visit entered in between —
    /// after an EXIT ended the one the loss interrupted — is not the interrupted one.
    @Test(arguments: [true, false])
    func delayedInvalidationLeavesAVisitEnteredAfterTheLossAlone(forOneFence: Bool) async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(10)
        let geofenceId = forOneFence ? setup.geofence.id : nil
        let lostAt = setup.coordinator.continuityLost(geofenceId: geofenceId)

        clock.advance(10)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: clock.wall)
        clock.advance(10)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let reentry = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        await setup.coordinator.invalidateContinuity(geofenceId: geofenceId, lostAt: lostAt)

        #expect(reentry != nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == reentry)
    }

    /// An ENTER dated before a loss but processed after it would open a visit spanning the loss.
    @Test
    func entryDatedBeforeALossCannotOpenAVisitAfterIt() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        let enteredAt = clock.wall
        clock.advance(10)
        _ = setup.coordinator.continuityLost(geofenceId: setup.geofence.id)

        clock.advance(5)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)

        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    @Test
    func interruptionEndsTheVisitItInterrupted() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(10)

        await setup.coordinator.interruptContinuity(geofenceId: nil).value

        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    // MARK: - Known loss, before its removal runs

    /// The loss is known the moment it is recorded; its removal is a later task. Evidence landing
    /// in between must not qualify the interrupted visit, nor reuse its entry for a new one.
    @Test(arguments: [true, false])
    func knownLossStopsTheVisitQualifyingBeforeItsRemovalRuns(forOneFence: Bool) async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let visit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        clock.advance(120)

        _ = setup.coordinator.continuityLost(geofenceId: forOneFence ? setup.geofence.id : nil)
        await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")

        #expect(await setup.emitter.dwells().isEmpty)
        let stored = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        #expect(stored?.visitId != visit?.visitId)
        #expect(stored?.enteredAt != visit?.enteredAt)
    }

    /// A copy of the visit read before the loss reaches emission after it: admission is decided
    /// against the loss, not against whether the copy was read in time.
    @Test
    func knownLossStopsADwellForAVisitCopyReadBeforeIt() async throws {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let visit = try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id))
        clock.advance(120)

        _ = setup.coordinator.continuityLost(geofenceId: nil)
        await setup.coordinator.emitDwellIfQualified(
            geofence: setup.geofence, visit: visit, observedAt: clock.wall, source: "location_evidence", userId: "user-1"
        )

        #expect(await setup.emitter.dwells().isEmpty)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.dwellReservation == nil)
    }

    /// A dwell already handed to the outbox before the loss is a fact about the stay before it:
    /// the loss ends the visit, but the queued row stays.
    @Test
    func lossAfterADwellWasQueuedKeepsTheQueuedRow() async throws {
        let clock = ManualGeofenceClock()
        let outbox = PendingGeofenceMetricStore(
            logger: LoggerMock(),
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let emitter = QueueingThenHeldEmitter(outbox: outbox)
        let setup = await makeSetup(clock: clock, emitter: emitter)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(120)
        let emission = Task { @MainActor in
            await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")
        }
        await emitter.waitUntilHeld()

        clock.advance(1)
        await setup.coordinator.interruptContinuity(geofenceId: nil).value
        await emitter.release()
        await emission.value

        let rows = await outbox.rows()
        #expect(rows.map(\.transition) == [.dwell])
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    // MARK: - Background App Refresh

    /// Background App Refresh is a separate switch from location permission: with it off, Always
    /// and precise location are unchanged, yet region events stop reaching the app in the
    /// background. Its change notification ends visits recorded while it was on.
    @Test
    func backgroundRefreshTurnedOffEndsTheVisitWithPermissionUnchanged() async {
        let clock = ManualGeofenceClock()
        let refresh = FlagBox(true)
        let center = NotificationCenter()
        let setup = await makeSetup(
            clock: clock, notificationCenter: center,
            locationAccess: { Self.always }, backgroundRefreshAvailable: { refresh.value }
        )
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) != nil)

        refresh.value = false
        center.post(name: UIApplication.backgroundRefreshStatusDidChangeNotification, object: nil)

        #expect(await waitForNoVisit(setup))
    }

    /// A restoration before the asynchronous revalidation runs cannot erase the observed loss.
    @Test
    func rapidlyRestoredBackgroundRefreshStillEndsTheInterruptedVisit() async {
        let clock = ManualGeofenceClock()
        let refresh = FlagBox(true)
        let center = NotificationCenter()
        let setup = await makeSetup(
            clock: clock, notificationCenter: center,
            locationAccess: { Self.always }, backgroundRefreshAvailable: { refresh.value }
        )
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) != nil)

        clock.advance(10)
        refresh.value = false
        center.post(name: UIApplication.backgroundRefreshStatusDidChangeNotification, object: nil)
        refresh.value = true
        center.post(name: UIApplication.backgroundRefreshStatusDidChangeNotification, object: nil)
        await settleQuietly()

        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
        #expect(await setup.emitter.dwells().isEmpty)
    }

    /// A visit recorded with refresh already off loses nothing to a repeated report, nor to
    /// refresh coming back.
    @Test
    func repeatedOrRestoredBackgroundRefreshKeepsAVisitRecordedUnderIt() async {
        let clock = ManualGeofenceClock()
        let refresh = FlagBox(false)
        let center = NotificationCenter()
        let setup = await makeSetup(
            clock: clock, notificationCenter: center,
            locationAccess: { Self.always }, backgroundRefreshAvailable: { refresh.value }
        )
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let visit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)

        center.post(name: UIApplication.backgroundRefreshStatusDidChangeNotification, object: nil)
        refresh.value = true
        center.post(name: UIApplication.backgroundRefreshStatusDidChangeNotification, object: nil)
        await settleQuietly()

        #expect(visit != nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.visitId == visit?.visitId)
    }

    /// Refresh turned off while the app was not running: no notification reached it, but the visit
    /// was recorded under background delivery the app no longer has.
    @Test
    func relaunchAfterBackgroundRefreshTurnedOffEndsTheVisit() async {
        let clock = ManualGeofenceClock()
        let refresh = FlagBox(true)
        let before = await makeSetup(
            clock: clock, locationAccess: { Self.always }, backgroundRefreshAvailable: { refresh.value }
        )
        await before.coordinator.handleBoundary(geofence: before.geofence, transition: .enter, occurredAt: clock.wall)

        clock.advance(120)
        refresh.value = false
        let relaunched = await makeSetup(
            directory: before.directory, clock: clock,
            locationAccess: { Self.always }, backgroundRefreshAvailable: { refresh.value }
        )
        await relaunched.coordinator.resumePendingVisits(geofences: [relaunched.geofence])

        #expect(await relaunched.storage.getDwellVisit(geofenceId: relaunched.geofence.id) == nil)
    }

    // MARK: - When In Use

    /// Under When In Use the SDK holds no background session (`CoreLocationAuthority` keeps a
    /// `CLServiceSession` only for Always), so region events stop when the app leaves the
    /// foreground: an EXIT can no longer be observed, and the visit's continuity ends there.
    @Test
    func whenInUseVisitEndsWhenTheAppEntersTheBackground() async {
        let clock = ManualGeofenceClock()
        let center = NotificationCenter()
        let setup = await makeSetup(clock: clock, notificationCenter: center, locationAccess: { Self.whenInUse })
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) != nil)

        clock.advance(10)
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        #expect(await waitForNoVisit(setup))
    }

    /// Always with refresh available: suspension is not an interruption, and the visit survives
    /// for a late confirmation.
    @Test
    func alwaysVisitSurvivesTheAppEnteringTheBackground() async {
        let clock = ManualGeofenceClock()
        let center = NotificationCenter()
        let setup = await makeSetup(
            clock: clock, notificationCenter: center,
            locationAccess: { Self.always }, backgroundRefreshAvailable: { true }
        )
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let visit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)

        clock.advance(10)
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await settleQuietly()
        clock.advance(600)
        await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")

        #expect(await setup.emitter.dwells().first?.context.visitId == visit?.visitId)
    }

    /// Always, but refresh off: background delivery is just as unavailable as under When In Use.
    @Test
    func alwaysVisitWithoutBackgroundRefreshEndsWhenTheAppEntersTheBackground() async {
        let clock = ManualGeofenceClock()
        let center = NotificationCenter()
        let setup = await makeSetup(
            clock: clock, notificationCenter: center,
            locationAccess: { Self.always }, backgroundRefreshAvailable: { false }
        )
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)

        clock.advance(10)
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        #expect(await waitForNoVisit(setup))
    }

    /// The app left the foreground at some point between two processes, so a When In Use visit from
    /// an earlier process spans a period that could observe no EXIT, whatever the app's state now.
    @Test
    func whenInUseVisitFromAnEarlierProcessIsDropped() async {
        let clock = ManualGeofenceClock()
        let before = await makeSetup(clock: clock, locationAccess: { Self.whenInUse })
        await before.coordinator.handleBoundary(geofence: before.geofence, transition: .enter, occurredAt: clock.wall)

        clock.advance(120)
        let relaunched = await makeSetup(directory: before.directory, clock: clock, locationAccess: { Self.whenInUse })
        await relaunched.coordinator.recordInsideEvidence(
            geofence: relaunched.geofence, at: clock.wall, source: "location_evidence"
        )

        #expect(await relaunched.emitter.dwells().isEmpty)
    }

    /// Recorded while the app was in the background, where When In Use observes no EXIT: returning
    /// to the foreground ends it rather than carrying its entry across that period.
    @Test
    func whenInUseVisitRecordedInTheBackgroundEndsWhenTheAppReturns() async {
        let clock = ManualGeofenceClock()
        let center = NotificationCenter()
        let setup = await makeSetup(clock: clock, notificationCenter: center, locationAccess: { Self.whenInUse })
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await settleQuietly()
        clock.advance(10)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) != nil)

        clock.advance(300)
        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        #expect(await waitForNoVisit(setup))
    }

    /// While the app stays in the foreground, When In Use observes every edge: the visit qualifies.
    @Test
    func whenInUseVisitQualifiesWhileTheAppStaysInTheForeground() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock, locationAccess: { Self.whenInUse })
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let visit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)

        clock.advance(120)
        await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")

        #expect(await setup.emitter.dwells().first?.context.visitId == visit?.visitId)
    }

    // MARK: - Location access

    /// Access dropped while the app was not running: no callback reported it, but the visit was
    /// recorded under more access than there is now.
    @Test(arguments: [
        GeofenceLocationAccess(delivery: .foregroundOnly, fullAccuracy: true),
        GeofenceLocationAccess(delivery: .background, fullAccuracy: false),
        GeofenceLocationAccess(delivery: .none, fullAccuracy: true)
    ])
    func relaunchAfterLocationAccessDroppedEndsTheVisit(downgraded: GeofenceLocationAccess) async {
        let clock = ManualGeofenceClock()
        let access = AccessBox(GeofenceLocationAccess(delivery: .background, fullAccuracy: true))
        let beforeRelaunch = await makeSetup(clock: clock, locationAccess: { access.value })
        await beforeRelaunch.coordinator.handleBoundary(
            geofence: beforeRelaunch.geofence, transition: .enter, occurredAt: clock.wall
        )
        let visit = await beforeRelaunch.storage.getDwellVisit(geofenceId: beforeRelaunch.geofence.id)

        clock.advance(120)
        access.value = downgraded
        let relaunched = await makeSetup(
            directory: beforeRelaunch.directory, clock: clock, locationAccess: { access.value }
        )
        await relaunched.coordinator.recordInsideEvidence(
            geofence: relaunched.geofence, at: clock.wall, source: "location_evidence"
        )

        #expect(await relaunched.emitter.dwells().isEmpty)
        #expect(await relaunched.storage.getDwellVisit(geofenceId: relaunched.geofence.id)?.visitId != visit?.visitId)
    }

    /// More access, or the same access reported again, takes nothing away from a visit.
    @Test
    func increasedLocationAccessKeepsTheVisit() async {
        let clock = ManualGeofenceClock()
        let access = AccessBox(GeofenceLocationAccess(delivery: .foregroundOnly, fullAccuracy: true))
        let setup = await makeSetup(clock: clock, locationAccess: { access.value })
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let visit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)

        clock.advance(120)
        access.value = GeofenceLocationAccess(delivery: .background, fullAccuracy: true)
        await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")

        #expect(await setup.emitter.dwells().first?.context.visitId == visit?.visitId)
    }

    // MARK: - Circle outside evidence

    /// The deadline's fix is wholly outside the circle: the SDK saw the device leave, so this
    /// visit's continuity ends there. A later inside fix cannot qualify a stay spanning that
    /// absence, and no EXIT is made up for it.
    @Test
    func decisiveOutsideFixEndsTheVisitSoALaterInsideFixCannotQualifyIt() async {
        let clock = ManualGeofenceClock()
        let fixes = FixScript()
        let setup = await makeSetup(isPolygon: false, clock: clock, freshFixProvider: { fixes.next() })
        let visit = await seedVisit(setup, clock: clock)
        clock.advance(120)

        fixes.queue(Self.fix(latitude: 0.51, accuracy: 5, at: clock.wall))
        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)

        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)

        clock.advance(60)
        fixes.queue(Self.fix(latitude: 0.5, accuracy: 5, at: clock.wall))
        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)

        #expect(await setup.emitter.dwells().isEmpty)
        #expect(await setup.emitter.exitCount() == 0)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.visitId != visit.visitId)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    /// The outside fix ended the visit; a late copy of the ENTER that began it must not reopen a
    /// visit from before the absence. A real re-entry after the fix still opens one.
    @Test
    func enterDatedBeforeADecisiveOutsideFixCannotReopenTheVisit() async {
        let clock = ManualGeofenceClock()
        let fixes = FixScript()
        let setup = await makeSetup(isPolygon: false, clock: clock, freshFixProvider: { fixes.next() })
        let enteredAt = clock.wall
        _ = await seedVisit(setup, clock: clock)
        clock.advance(120)
        fixes.queue(Self.fix(latitude: 0.51, accuracy: 5, at: clock.wall))
        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)

        clock.advance(5)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)

        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.enteredAt == clock.wall)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    /// An accuracy circle straddling the edge decides nothing: the dwell is withheld, the visit
    /// kept, and a later decisive inside fix still qualifies it.
    @Test
    func ambiguousFixWithholdsTheDwellButKeepsTheVisit() async {
        let clock = ManualGeofenceClock()
        let fixes = FixScript()
        let setup = await makeSetup(isPolygon: false, clock: clock, freshFixProvider: { fixes.next() })
        let visit = await seedVisit(setup, clock: clock)
        clock.advance(120)

        // About 111 m from a 100 m circle's centre, give or take 50 m.
        fixes.queue(Self.fix(latitude: 0.501, accuracy: 50, at: clock.wall))
        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)

        #expect(await setup.emitter.dwells().isEmpty)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.visitId == visit.visitId)

        clock.advance(60)
        fixes.queue(Self.fix(latitude: 0.5, accuracy: 5, at: clock.wall))
        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)

        #expect(await setup.emitter.dwells().first?.context.visitId == visit.visitId)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    /// The fix resolves after an EXIT and a re-entry replaced the visit it was requested for. Its
    /// outside verdict is about the old visit, and must not end the new one.
    @Test
    func decisiveOutsideFixForAReplacedVisitLeavesTheNewVisitAlone() async {
        let clock = ManualGeofenceClock()
        let provider = HeldFixProvider()
        let setup = await makeSetup(isPolygon: false, clock: clock, freshFixProvider: { await provider.next() })
        _ = await seedVisit(setup, clock: clock)
        clock.advance(120)
        let request = Task { await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id) }
        #expect(await settleOnMain(timeout: 10) { provider.isWaiting })

        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: clock.wall)
        clock.advance(5)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let reentry = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        provider.resolve(Self.fix(latitude: 0.51, accuracy: 5, at: clock.wall))
        await request.value

        #expect(reentry != nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == reentry)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    /// A fix taken before the visit began says nothing about it.
    @Test
    func outsideFixOlderThanTheVisitDoesNotEndIt() async {
        let clock = ManualGeofenceClock()
        let fixes = FixScript()
        let setup = await makeSetup(isPolygon: false, clock: clock, freshFixProvider: { fixes.next() })
        let fixAt = clock.wall
        clock.advance(30)
        let visit = await seedVisit(setup, clock: clock)
        clock.advance(120)

        fixes.queue(Self.fix(latitude: 0.51, accuracy: 5, at: fixAt))
        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)

        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.visitId == visit.visitId)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    // MARK: - Events dated before a wall-clock step, processed after it

    /// The EXIT is dated on the clock before a forward step and processed after it, so its
    /// wall-clock age reads an hour too long and it lands before the visit's entry on the
    /// monotonic timeline. It still ends the visit: once the clock has stepped, that date cannot be
    /// ordered against the entry, and keeping the visit would carry its stay across a real EXIT.
    /// The re-entry 450 s later is a stay of its own and cannot qualify a 600 s dwell.
    @Test
    func exitDatedBeforeAForwardStepEndsTheVisitSoAShortReentryCannotQualify() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(dwellThresholdSeconds: 600, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let first = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        clock.advance(50)
        let exitDatedAt = clock.wall
        clock.advance(50)
        clock.stepWall(3600)
        clock.advance(10)

        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: exitDatedAt)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)

        clock.advance(40)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let reentry = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        #expect(reentry != nil)
        #expect(reentry?.visitId != first?.visitId)
        clock.advance(450)
        await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")

        #expect(await setup.emitter.dwells().isEmpty)
    }

    /// The deadline's fix is wholly outside the circle but was taken before a forward step: it
    /// still ends the visit it was requested for.
    @Test
    func decisiveOutsideFixTakenBeforeAForwardStepEndsTheVisit() async {
        let clock = ManualGeofenceClock()
        let fixes = FixScript()
        let setup = await makeSetup(isPolygon: false, clock: clock, freshFixProvider: { fixes.next() })
        _ = await seedVisit(setup, clock: clock)
        clock.advance(120)
        let fixTakenAt = clock.wall
        clock.stepWall(3600)
        clock.advance(10)

        fixes.queue(Self.fix(latitude: 0.51, accuracy: 5, at: fixTakenAt))
        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)

        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    /// The EXIT was processed before a backward step; a late copy of the visit's own ENTER arrives
    /// after it. Its old date reads as no age at all on the stepped-back clock, which would place it
    /// after the EXIT. It must not reopen the visit the EXIT ended.
    @Test
    func lateEnterCopyAfterABackwardStepCannotReopenTheExitedVisit() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        let enteredAt = clock.wall
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        clock.advance(50)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: clock.wall)
        clock.stepWall(-3600)
        clock.advance(10)

        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)

        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    /// An ENTER dated before a forward step and processed after it: the visit qualifies on time
    /// actually spent, but its date is on the old clock, so neither it nor a duration from it is
    /// reported.
    @Test
    func enterDatedBeforeAStepWithholdsTheEntryAndDuration() async throws {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(dwellThresholdSeconds: 600, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(30)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: clock.wall)
        clock.advance(30)
        let reenteredAt = clock.wall
        clock.stepWall(3600)
        clock.advance(10)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: reenteredAt)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) != nil)

        clock.advance(600)
        await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")

        let dwells = await setup.emitter.dwells()
        try #require(dwells.count == 1)
        #expect(dwells[0].context.enteredAt == nil)
        #expect(dwells[0].context.durationSeconds == nil)
    }

    /// Control, coherent clock: a delayed EXIT dated inside an older visit leaves the visit entered
    /// after it, and that visit still reports its entry.
    @Test
    func staleExitFromAnOlderVisitLeavesTheNewerVisitUnderACoherentClock() async throws {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(dwellThresholdSeconds: 600, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        clock.advance(20)
        let staleExitAt = clock.wall
        clock.advance(10)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: clock.wall)
        clock.advance(20)
        let reenteredAt = clock.wall
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: reenteredAt)
        let newer = try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id))
        clock.advance(10)

        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: staleExitAt)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.visitId == newer.visitId)

        clock.advance(590)
        await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")
        let dwells = await setup.emitter.dwells()
        try #require(dwells.count == 1)
        #expect(dwells[0].context.visitId == newer.visitId)
        #expect(dwells[0].context.enteredAt == reenteredAt)
    }

    /// Control: a stale EXIT for the visit ended before a step, processed after it, leaves the
    /// distinct visit a re-entry opened after the step; that visit's entry is on the new clock.
    @Test
    func staleExitProcessedAfterAStepLeavesTheReentryOpenedAfterIt() async throws {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(dwellThresholdSeconds: 600, clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let first = try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id))
        clock.advance(30)
        let exitedAt = clock.wall
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: exitedAt)
        clock.stepWall(3600)
        clock.advance(30)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let reentry = try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id))
        #expect(reentry.visitId != first.visitId)
        clock.advance(10)

        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: exitedAt)

        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.visitId == reentry.visitId)
    }

    @Test
    func staleUserVisitReadKeepsTheNewUsersVisit() async throws {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        setup.coordinator.contextStore.setUserId("user-2")
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let current = try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id))

        #expect(await setup.coordinator.currentVisit(geofence: setup.geofence, userId: "user-1") == nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.visitId == current.visitId)
    }

    @Test
    func oldEnterDatedBeforeABackwardStepCannotReopenAnExitDatedAfterIt() async {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(dwellThresholdSeconds: 600, clock: clock)
        let oldEnteredAt = clock.wall
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: oldEnteredAt)
        clock.advance(30)
        clock.stepWall(-3600)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .exit, occurredAt: clock.wall)
        clock.advance(10)

        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: oldEnteredAt)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)

        // The clock has caught up with the old entry's date, but the device returns only now.
        // This fresh observation starts a candidate now, rather than counting the time outside.
        clock.advance(4200)
        await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")
        #expect(await setup.emitter.dwells().isEmpty)
        clock.advance(600)
        await setup.coordinator.recordInsideEvidence(geofence: setup.geofence, at: clock.wall, source: "location_evidence")
        #expect(await setup.emitter.dwells().count == 1)
        #expect(await setup.emitter.dwells().first?.context.enteredAt == nil)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
    }

    @Test
    func staleCleanupKeepsTheVisitWrittenAfterItsRead() async throws {
        let clock = ManualGeofenceClock()
        let setup = await makeSetup(clock: clock)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let old = try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id))
        clock.advance(1)
        setup.coordinator.contextStore.setUserId("user-2")
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: clock.wall)
        let current = try #require(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id))

        await setup.storage.removeDwellVisitIfStale(geofenceId: setup.geofence.id, currentUserId: "user-1", ifStill: old.visitId)

        #expect(current.visitId != old.visitId)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.visitId == current.visitId)
    }

    // MARK: - Helpers

    private func makeSetup(
        dwellThresholdSeconds: Int = 60,
        isPolygon: Bool = true,
        directory: URL? = nil,
        clock: ManualGeofenceClock,
        freshFixProvider: @escaping () async -> CLLocation? = { nil },
        emitter: GeofenceTransitionEmitting? = nil,
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
            transitionTypes: [.enter, .exit],
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
        let spy = ContinuityEmitterSpy()
        let coordinator = GeofenceDwellCoordinator(
            storage: storage,
            transitionEmitter: emitter ?? spy,
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

    private static let always = GeofenceLocationAccess(delivery: .background, fullAccuracy: true)
    private static let whenInUse = GeofenceLocationAccess(delivery: .foregroundOnly, fullAccuracy: true)

    /// The removal a lifecycle notification starts runs on a task of its own.
    private func waitForNoVisit(_ setup: Setup) async -> Bool {
        for _ in 0 ..< 200 {
            if await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil { return true }
            try? await Task.sleep(nanoseconds: 10000000)
        }
        return false
    }

    private struct Setup {
        let storage: GeofenceStorage
        let emitter: ContinuityEmitterSpy
        let coordinator: GeofenceDwellCoordinator
        let geofence: Geofence
        let directory: URL
    }

    /// Stored directly rather than through an ENTER, so no deadline of its own requests a fix.
    private func seedVisit(_ setup: Setup, clock: ManualGeofenceClock) async -> GeofenceDwellVisit {
        let visit = GeofenceDwellVisit(
            visitId: UUID().uuidString,
            enteredAt: clock.wall,
            geometryRevision: setup.geofence.dwellRevision,
            userId: "user-1",
            emitted: false,
            timing: GeofenceVisitTiming(enteredAt: clock.wall, recordedAt: clock.read())
        )
        #expect(await setup.storage.saveDwellVisit(visit, geofenceId: setup.geofence.id))
        return visit
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

/// Queues each dwell's row in a real outbox, as the tracker does, then holds the call open until
/// released: a loss can land after the fact is queued and before the emission finishes.
private actor QueueingThenHeldEmitter: GeofenceTransitionEmitting {
    private let outbox: PendingGeofenceMetricStore
    private var held: CheckedContinuation<Void, Never>?
    private var holdWaiters: [CheckedContinuation<Void, Never>] = []

    init(outbox: PendingGeofenceMetricStore) {
        self.outbox = outbox
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
        guard await outbox.append(crossing.pendingMetrics(userId: "user-1", cachedGeofence: nil)) == .persisted
        else { return false }
        await withCheckedContinuation { continuation in
            held = continuation
            holdWaiters.forEach { $0.resume() }
            holdWaiters.removeAll()
        }
        return true
    }

    func waitUntilHeld() async {
        guard held == nil else { return }
        await withCheckedContinuation { holdWaiters.append($0) }
    }

    func release() {
        held?.resume()
        held = nil
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

/// Holds every fix request open until the test resolves them all with one fix.
@MainActor
private final class HeldFixProvider {
    private var continuations: [CheckedContinuation<CLLocation?, Never>] = []

    var isWaiting: Bool {
        !continuations.isEmpty
    }

    func next() async -> CLLocation? {
        await withCheckedContinuation { continuations.append($0) }
    }

    func resolve(_ fix: CLLocation?) {
        continuations.forEach { $0.resume(returning: fix) }
        continuations.removeAll()
    }
}

private actor ContinuityEmitterSpy: GeofenceTransitionEmitting {
    struct Dwell: Sendable {
        let occurredAt: Date
        let context: GeofenceDwellContext
    }

    private var recorded: [Dwell] = []
    private var exits = 0

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
        recorded.append(Dwell(occurredAt: occurredAt, context: context))
        return true
    }

    func dwells() -> [Dwell] {
        recorded
    }

    func exitCount() -> Int {
        exits
    }
}
