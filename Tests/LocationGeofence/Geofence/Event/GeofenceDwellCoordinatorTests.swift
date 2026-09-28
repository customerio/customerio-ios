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

@Suite("GeofenceDwellCoordinator")
@MainActor
struct GeofenceDwellCoordinatorTests {
    @Test
    func redeliveredCircleEnterPreservesTheCurrentVisit() async {
        let setup = await makeSetup(isPolygon: false)
        let firstEntry = Date(timeIntervalSince1970: 1000)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: firstEntry
        )
        let firstVisit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)

        let returnEntry = firstEntry.addingTimeInterval(3600)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: returnEntry
        )

        let secondVisit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        #expect(secondVisit == firstVisit)
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
        let setup = await makeSetup(dwellThresholdSeconds: 86400, isPolygon: false)
        let enteredAt = Date(timeIntervalSince1970: 1000)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: enteredAt
        )

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
            emitted: false
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
    func polygonDwellRequiresInsideEvidenceAfterThresholdAndEmitsOnce() async {
        let setup = await makeSetup()
        let enteredAt = Date(timeIntervalSince1970: 1000)

        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence,
            at: enteredAt.addingTimeInterval(59),
            source: "location_evidence"
        )
        #expect(await setup.emitter.dwells().isEmpty)

        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence,
            at: enteredAt.addingTimeInterval(67),
            source: "location_evidence"
        )
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence,
            at: enteredAt.addingTimeInterval(90),
            source: "location_evidence"
        )

        let dwells = await setup.emitter.dwells()
        #expect(dwells.count == 1)
        #expect(dwells[0].context.thresholdSeconds == 60)
        #expect(dwells[0].context.durationSeconds == 67)
        #expect(dwells[0].context.detectionSource == "location_evidence")
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.emitted == true)
    }

    @Test
    func dwellPersistedAfterExitAndReentryDoesNotOverwriteTheNewVisit() async {
        let suspending = SuspendingDwellEmitter()
        let setup = await makeSetup(transitionEmitter: suspending)
        let enteredAt = Date(timeIntervalSince1970: 1000)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        let firstVisit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)

        let emission = Task { @MainActor in
            await setup.coordinator.recordInsideEvidence(
                geofence: setup.geofence,
                at: enteredAt.addingTimeInterval(61),
                source: "location_evidence"
            )
        }
        await suspending.waitUntilSuspended()
        // While the dwell is being persisted, the device leaves and comes back.
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: enteredAt.addingTimeInterval(62)
        )
        let reentry = enteredAt.addingTimeInterval(63)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: reentry)
        await suspending.resume(returning: true)
        await emission.value

        let current = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        #expect(current?.visitId != firstVisit?.visitId)
        #expect(current?.enteredAt == reentry)
        #expect(current?.emitted == false)
    }

    @Test
    func failedOutboxWriteLeavesVisitRetryable() async {
        let emitter = DwellEmitterSpy(results: [false, true])
        let setup = await makeSetup(emitter: emitter)
        let enteredAt = Date(timeIntervalSince1970: 1000)

        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence,
            at: enteredAt.addingTimeInterval(60),
            source: "location_evidence"
        )
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.emitted == false)

        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence,
            at: enteredAt.addingTimeInterval(61),
            source: "location_evidence"
        )

        let attempts = await emitter.dwells()
        #expect(attempts.count == 2)
        #expect(attempts[0].context.visitId == attempts[1].context.visitId)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.emitted == true)
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
        let setup = await makeSetup()
        let enteredAt = Date(timeIntervalSince1970: 1000)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        let firstVisit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        let lateEvidence = enteredAt.addingTimeInterval(24 * 60 * 60)

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
        let setup = await makeSetup()
        let enteredAt = Date(timeIntervalSince1970: 1000)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: enteredAt
        )
        await setup.coordinator.invalidateContinuity(geofenceId: setup.geofence.id)
        let candidateStart = enteredAt.addingTimeInterval(10)

        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence, at: candidateStart, source: "location_evidence"
        )
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
        let setup = await makeSetup(
            dwellThresholdSeconds: 0,
            transitionTypes: [.exit],
            isPolygon: false
        )
        let enteredAt = Date(timeIntervalSince1970: 1000)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .enter,
            occurredAt: enteredAt
        )

        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .exit,
            occurredAt: enteredAt.addingTimeInterval(7 * 86400)
        )

        #expect(context?.durationSeconds == 7 * 86400)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    @Test
    func exitOnlyFenceReturnsObservedVisitDuration() async {
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit])
        let enteredAt = Date(timeIntervalSince1970: 1000)

        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: enteredAt
        )
        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .exit,
            occurredAt: enteredAt.addingTimeInterval(75),
            detectionSource: "location_evidence"
        )

        #expect(context?.enteredAt == enteredAt)
        #expect(context?.durationSeconds == 75)
        #expect(context?.detectionSource == "location_evidence")
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
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
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit], isPolygon: false)
        let enteredAt = try #require(Self.dateThatPersistsLate())

        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        let stored = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        #expect(stored.map { $0.enteredAt > enteredAt } == true)
        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: enteredAt.addingTimeInterval(60)
        )

        #expect(context?.durationSeconds == 60)
    }

    /// The slack is for representation error only: a real fraction short of a second still truncates.
    @Test
    func visitJustShortOfAWholeSecondStillTruncates() async {
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit], isPolygon: false)
        let enteredAt = Date(timeIntervalSince1970: 5000)

        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: enteredAt.addingTimeInterval(59.999)
        )

        #expect(context?.durationSeconds == 59)
    }

    @Test
    func observedEntryAfterContinuityLossRestoresVisitDuration() async {
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit])
        let enteredAt = Date(timeIntervalSince1970: 1000)
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence, at: enteredAt, source: "location_evidence"
        )
        let reentry = enteredAt.addingTimeInterval(60)

        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence, at: reentry, source: "location_evidence", beginsNewVisit: true
        )
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
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit], isPolygon: false)
        let firstEntry = Date(timeIntervalSince1970: 1000)

        let firstExit = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: firstEntry.addingTimeInterval(60)
        )
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: firstEntry
        )
        #expect(firstExit == nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)

        let reentry = firstEntry.addingTimeInterval(3600)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: reentry
        )
        let finalExit = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: reentry.addingTimeInterval(120)
        )

        #expect(finalExit?.enteredAt == reentry)
        #expect(finalExit?.durationSeconds == 120)
    }

    /// OS callbacks each run on their own task. The EXIT closing the old visit and the re-entry
    /// both read the store before the EXIT removes anything: the re-entry must not adopt the visit
    /// that EXIT is ending, or the removal leaves it with none.
    @Test
    func exitOnlyFenceReentryOverlappingTheClosingExitReportsEachVisitsOwnDuration() async {
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit], isPolygon: false)
        let firstEntry = Date(timeIntervalSince1970: 1000)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: firstEntry
        )
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
        let closed = await exit.value
        _ = await enter.value

        #expect(closed?.enteredAt == firstEntry)
        #expect(closed?.durationSeconds == 60)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.enteredAt == reentry)
        let finalExit = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: reentry.addingTimeInterval(120)
        )
        #expect(finalExit?.enteredAt == reentry)
        #expect(finalExit?.durationSeconds == 120)
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
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit], isPolygon: false)
        let enteredAt = Date(timeIntervalSince1970: 3000)

        let first = Task { @MainActor in
            await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        }
        let duplicate = Task { @MainActor in
            await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        }
        _ = await first.value
        _ = await duplicate.value
        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .exit, occurredAt: enteredAt.addingTimeInterval(45)
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

    /// Core Location's exit hysteresis means a device can step just past the radius and return
    /// with no EXIT and no new ENTER. A decisive-outside deadline fix therefore only withholds the
    /// dwell: the visit, and with it this stay's later dwell, survives until the OS says it ended.
    @Test
    func circleDeadlineGivenDecisiveOutsideFixKeepsTheVisitForALaterInsideFix() async {
        let fixes = FixSequence([
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 0.51, longitude: 0.5),
                altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 10, timestamp: Date()
            ),
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 0.5, longitude: 0.5),
                altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 10, timestamp: Date()
            )
        ])
        let setup = await makeSetup(
            isPolygon: false, freshFixProvider: { fixes.next() }, evidenceRetryDelay: 60
        )
        let enteredAt = Date().addingTimeInterval(-120)
        // Stored directly rather than through an ENTER, which would arm a due deadline of its own:
        // this test decides when each fix lands.
        let visit = GeofenceDwellVisit(
            visitId: "visit-1",
            enteredAt: enteredAt,
            geometryRevision: setup.geofence.dwellRevision,
            userId: "user-1",
            emitted: false
        )
        #expect(await setup.storage.saveDwellVisit(visit, geofenceId: setup.geofence.id))

        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)

        #expect(await setup.emitter.dwells().isEmpty)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.visitId == visit.visitId)
        #expect(setup.coordinator.evidenceRetries[setup.geofence.id]?.attempts == 1)

        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)

        let dwell = await setup.emitter.dwells().first
        #expect(dwell?.context.visitId == visit.visitId)
        #expect(abs(dwell?.context.enteredAt?.timeIntervalSince(enteredAt) ?? .infinity) < 0.001)
        setup.coordinator.cancelEvidence(for: setup.geofence.id)
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
        let setup = await makeSetup(isPolygon: false, freshFixProvider: { fix })
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .enter,
            occurredAt: Date().addingTimeInterval(-120)
        )

        await setup.coordinator.requestQualifyingEvidence(geofenceId: setup.geofence.id)

        #expect(await setup.emitter.dwells().count == 1)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.emitted == true)
    }

    @Test
    func exitWhileFixIsResolvingDoesNotRearmEvidence() async throws {
        let probe = SuspendedFixProvider()
        let setup = await makeSetup(
            isPolygon: false,
            freshFixProvider: { await probe.next() },
            evidenceRetryDelay: 0.001
        )
        let enteredAt = Date().addingTimeInterval(-120)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .enter,
            occurredAt: enteredAt
        )
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
        let setup = await makeSetup(
            isPolygon: false,
            freshFixProvider: { await probe.next() },
            evidenceRetryDelay: 0.001
        )
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .enter,
            occurredAt: Date().addingTimeInterval(-120)
        )
        try #require(await settleOnMain(timeout: 5) { probe.calls == 1 })

        probe.resolve(nil)

        #expect(await settleOnMain(timeout: 5) { probe.calls == 2 })
        await setup.coordinator.invalidateContinuity()
        probe.resolve(nil)
    }

    @Test
    func polygonEvidenceRetriesAreBounded() async {
        let setup = await makeSetup(evidenceRetryDelay: 0.001, maxEvidenceRetryAttempts: 1)
        var verifierCalls = 0
        setup.coordinator.polygonVerifier = { _ in verifierCalls += 1 }

        await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .enter,
            occurredAt: Date().addingTimeInterval(-120)
        )
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

        for _ in 0 ..< 300 where await setup.emitter.dwells().isEmpty {
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
        let setup = await makeSetup(isPolygon: false, freshFixProvider: { nil })
        let enteredAt = Date(timeIntervalSince1970: 1000)
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
        let setup = await makeSetup(
            isPolygon: false,
            freshFixProvider: { fixes.next() },
            evidenceRetryDelay: 0.001,
            maxEvidenceRetryAttempts: 1
        )
        let enteredAt = Date().addingTimeInterval(-120)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)
        // The due deadline, then its single retry; both get no fix, and nothing is left armed.
        try #require(await settleOnMain(timeout: 5) {
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
            emitted: false
        )
        #expect(await setup.storage.saveDwellVisit(visit, geofenceId: setup.geofence.id))

        await setup.coordinator.rearmPendingEvidence(includePolygons: false)
        #expect(setup.coordinator.deadlineTasks[setup.geofence.id] == nil)

        await setup.coordinator.rearmPendingEvidence(includePolygons: true)
        #expect(await settleOnMain(timeout: 5) { verifierCalls == 1 })
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
            emitted: false
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
        let setup = await makeSetup(isPolygon: false, freshFixProvider: { nil })
        let enteredAt = Date(timeIntervalSince1970: 1000.9)
        await setup.coordinator.handleBoundary(geofence: setup.geofence, transition: .enter, occurredAt: enteredAt)

        // 59.2 s observed: 1060 - 1000 would read 60, but the stay has not reached the threshold.
        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence, at: Date(timeIntervalSince1970: 1060.1), source: "location_evidence"
        )
        #expect(await setup.emitter.dwells().isEmpty)

        let observedAt = Date(timeIntervalSince1970: 1061.1)
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
        notificationCenter: NotificationCenter = .default
    ) async -> Setup {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
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
            maxEvidenceRetryAttempts: maxEvidenceRetryAttempts
        )
        return Setup(storage: storage, emitter: emitter, coordinator: coordinator, geofence: geofence)
    }

    private struct Setup {
        let storage: GeofenceStorage
        let emitter: DwellEmitterSpy
        let coordinator: GeofenceDwellCoordinator
        let geofence: Geofence
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

    init(results: [Bool] = [true]) {
        self.results = results
    }

    func trackTransition(geofenceId: String, transition: GeofenceTransition, occurredAt: Date) async {}

    func trackExit(
        geofenceId: String, occurredAt: Date, context: GeofenceExitContext?, expectedUserId: String?
    ) async {}

    func trackDwell(
        geofenceId: String, occurredAt: Date, context: GeofenceDwellContext, expectedUserId: String?
    ) async -> Bool {
        invocations.append(Invocation(geofenceId: geofenceId, occurredAt: occurredAt, context: context))
        return results.isEmpty ? true : results.removeFirst()
    }

    func dwells() -> [Invocation] {
        invocations
    }
}
