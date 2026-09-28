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
        let firstEntry = Date(timeIntervalSince1970: 1_000)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: firstEntry
        )
        let firstVisit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)

        let returnEntry = firstEntry.addingTimeInterval(3_600)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: returnEntry
        )

        let secondVisit = await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)
        #expect(secondVisit == firstVisit)
    }

    @Test
    func circleExitThenEnterStartsANewVisit() async {
        let setup = await makeSetup(isPolygon: false)
        let firstEntry = Date(timeIntervalSince1970: 1_000)
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
        let currentEntry = Date(timeIntervalSince1970: 2_000)
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
    func longObservedVisitIsReportedOnExit() async {
        let setup = await makeSetup(
            dwellThresholdSeconds: 0,
            transitionTypes: [.exit],
            isPolygon: false
        )
        let enteredAt = Date(timeIntervalSince1970: 1_000)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .enter,
            occurredAt: enteredAt
        )

        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .exit,
            occurredAt: enteredAt.addingTimeInterval(7 * 86_400)
        )

        #expect(context?.durationSeconds == 7 * 86_400)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
    }

    @Test
    func dayLongDwellThresholdRemainsAchievableWhenEvidenceArrivesLate() async {
        let setup = await makeSetup(dwellThresholdSeconds: 86_400, isPolygon: false)
        let enteredAt = Date(timeIntervalSince1970: 1_000)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: enteredAt
        )

        await setup.coordinator.recordInsideEvidence(
            geofence: setup.geofence,
            at: enteredAt.addingTimeInterval(86_401),
            source: "location_evidence"
        )

        let dwell = await setup.emitter.dwells().first
        #expect(dwell?.context.enteredAt == enteredAt)
        #expect(dwell?.context.thresholdSeconds == 86_400)
        #expect(dwell?.context.durationSeconds == 86_401)
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
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(await setup.emitter.dwells().count == 1)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id)?.visitId == persistedVisit.visitId)
    }

    @Test
    func confirmedPolygonReentryStartsNewVisitWhileDuplicateEvidencePreservesIt() async {
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit])
        let firstEntry = Date(timeIntervalSince1970: 1_000)
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
        let enteredAt = Date(timeIntervalSince1970: 1_000)

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
        let enteredAt = Date(timeIntervalSince1970: 1_000)

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
        let enteredAt = Date(timeIntervalSince1970: 1_000)
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
        let enteredAt = Date(timeIntervalSince1970: 1_000)
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
    func exitOnlyFenceReturnsObservedVisitDuration() async {
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit])
        let enteredAt = Date(timeIntervalSince1970: 1_000)

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
            occurredAt: Date(timeIntervalSince1970: 1_075)
        )

        #expect(context == nil)
    }

    @Test
    func insideEvidenceAfterContinuityLossDoesNotClaimVisitDurationOnExit() async {
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit])
        let enteredAt = Date(timeIntervalSince1970: 1_000)
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

    @Test
    func insideEvidenceAfterContinuityLossStillSupportsBestEffortDwell() async {
        let setup = await makeSetup()
        let enteredAt = Date(timeIntervalSince1970: 1_000)
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

        let dwells = await setup.emitter.dwells()
        #expect(dwells.count == 1)
        #expect(dwells.first?.context.enteredAt == candidateStart)
        #expect(dwells.first?.context.durationSeconds == 70)
    }

    @Test
    func observedEntryAfterContinuityLossRestoresVisitDuration() async {
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit])
        let enteredAt = Date(timeIntervalSince1970: 1_000)
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

    @Test
    func evidenceForAnEndedVisitDoesNotStartAnother() async {
        let setup = await makeSetup()
        let enteredAt = Date(timeIntervalSince1970: 1_000)
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
        let setup = await makeSetup(dwellThresholdSeconds: 0, transitionTypes: [.exit])
        let enteredAt = Date(timeIntervalSince1970: 1_000)
        await setup.coordinator.handleBoundary(
            geofence: setup.geofence, transition: .enter, occurredAt: enteredAt
        )

        let context = await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .exit,
            occurredAt: enteredAt.addingTimeInterval(-1)
        )

        #expect(context == nil)
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
    func circleDeadlineGivenDecisiveOutsideFixClearsUnknownContinuity() async {
        let fix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0.51, longitude: 0.5),
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

        #expect(await setup.emitter.dwells().isEmpty)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
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
    func exitWhileFixIsResolvingDoesNotRearmEvidence() async {
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
        for _ in 0 ..< 100 where probe.calls == 0 {
            await Task.yield()
        }
        #expect(probe.calls == 1)

        await setup.coordinator.handleBoundary(
            geofence: setup.geofence,
            transition: .exit,
            occurredAt: Date()
        )
        probe.resolve(nil)
        try? await Task.sleep(nanoseconds: 50000000)

        #expect(probe.calls == 1)
        #expect(await setup.storage.getDwellVisit(geofenceId: setup.geofence.id) == nil)
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
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let dwells = await setup.emitter.dwells()
        #expect(dwells.count == 1)
        #expect(abs(dwells.first?.context.enteredAt.timeIntervalSince(enteredAt) ?? .infinity) < 0.001)
        #expect((dwells.first?.context.durationSeconds ?? 0) >= 1)
    }
    #endif

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
