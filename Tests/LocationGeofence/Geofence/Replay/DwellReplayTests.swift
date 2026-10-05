@testable import CioInternalCommon
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import Foundation
import SharedTests
import Testing

@Suite("Dwell replay", .serialized, .enabled(if: ReplayRuntime.isMonitorAvailable))
@MainActor
struct DwellReplayTests {
    @Test
    @available(iOS 17.0, *)
    func retry_whenPostThresholdFixIsTooOld_thenNoDwellUntilFreshEvidence() async throws {
        try await withVisit(fixes: [.init(100, 10.0, 10), .init(195, 10.0, 10)], threshold: 45) { harness in
            await harness.advance(to: 135)
            #expect(dwells(harness).isEmpty, "a 35-second-old fix bypassed MovementFixResolver")
            await harness.advance(to: 195)
            #expect(dwells(harness).count == 1)
        }
    }

    @Test
    @available(iOS 17.0, *)
    func deadline_whenOutsideAnswerIsFromFuture_thenDoesNotCloseVisitBeforeExit() async throws {
        try await withVisit(fixes: [.init(90, 10.0, 10), .init(95, 10.0151, 10)]) { harness in
            harness.fixes.loadRequestedAnswers([
                harness.pulledFix(latitude: 10.0151, longitude: 20, accuracy: 10, age: 0, at: 99)
            ])
            await harness.advance(to: 90)
            #expect(dwells(harness).count == 1)
            await harness.advance(to: 95)
            harness.deliverCrossing(fence: "A", transition: .exit)
            try await harness.settleBoundaries()
            let exit = try #require(harness.deliveredMetrics.filter { $0.transition == .exit }.only)
            #expect(exit.visitDurationSeconds == 65)
        }
    }

    @Test
    @available(iOS 17.0, *)
    func deadline_whenThresholdDiffersFromRetryDelay_thenEmitsAtThreshold() async throws {
        try await withVisit(fixes: [.init(75, 10.0, 10)], threshold: 45) { harness in
            await harness.advance(to: 74)
            #expect(dwells(harness).isEmpty)
            await harness.advance(to: 75)
            let dwell = try #require(dwells(harness).only)
            #expect(dwell.dwellThresholdSeconds == 45)
            #expect(dwell.dwellDurationSeconds == 45)
            #expect(dwell.timestamp == harness.epoch.addingTimeInterval(75))
        }
    }

    @Test
    @available(iOS 17.0, *)
    func deadline_whenRequestedFixAnswerExists_thenUsesThatEvidence() async throws {
        try await withVisit(fixes: []) { harness in
            harness.fixes.loadRequestedAnswers([
                harness.pulledFix(latitude: 10, longitude: 20, accuracy: 10, age: 0, at: 90)
            ])
            await harness.advance(to: 90)
            #expect(dwells(harness).count == 1)
        }
    }

    @Test
    @available(iOS 17.0, *)
    func deadline_whenThresholdReachedWithFreshInsideFix_thenOneDwellWithObservedDuration() async throws {
        try await withVisit(fixes: [.init(90, 10.0, 10)]) { harness in
            await harness.advance(to: 89)
            #expect(dwells(harness).isEmpty)
            await harness.advance(to: 90)
            let dwell = try #require(dwells(harness).only)
            #expect(dwell.timestamp == harness.epoch.addingTimeInterval(90))
            #expect(dwell.enteredAt == harness.epoch.addingTimeInterval(30))
            #expect(dwell.dwellThresholdSeconds == 60)
            #expect(dwell.dwellDurationSeconds == 60)
            #expect(dwell.visitId?.isEmpty == false)
            #expect(dwell.detectionSource == "location_evidence")
        }
    }

    @Test
    @available(iOS 17.0, *)
    func deadline_whenOnlyOldCachedFixExists_thenNoDwellUntilFreshRetryEvidence() async throws {
        try await withVisit(fixes: [.init(150, 10.0, 10)]) { harness in
            await harness.advance(to: 90)
            #expect(dwells(harness).isEmpty, "a timer or renewed cache timestamp qualified dwell")
            await harness.advance(to: 149)
            #expect(dwells(harness).isEmpty)
            await harness.advance(to: 150)
            let dwell = try #require(dwells(harness).only)
            #expect(dwell.timestamp == harness.epoch.addingTimeInterval(150))
            #expect(dwell.dwellDurationSeconds == 120)
        }
    }

    @Test
    @available(iOS 17.0, *)
    func deadline_whenAccuracyOverlapsBoundary_thenNoDwellUntilReliableInsideFix() async throws {
        try await withVisit(fixes: [.init(90, 10.0, 500), .init(150, 10.0, 10)]) { harness in
            await harness.advance(to: 90)
            #expect(dwells(harness).isEmpty)
            await harness.advance(to: 150)
            #expect(dwells(harness).count == 1)
        }
    }

    @Test
    @available(iOS 17.0, *)
    func deadline_whenFreshFixProvesOutside_thenNoDwell() async throws {
        try await withVisit(fixes: [.init(90, 10.0151, 10)]) { harness in
            await harness.advance(to: 90)
            #expect(dwells(harness).isEmpty)
            #expect(await harness.storedVisit(fence: "A") == nil)
        }
    }

    @Test
    @available(iOS 17.0, *)
    func deadline_whenDuplicateEnterAndForegroundWakeFollowDwell_thenNoRepeat() async throws {
        try await withVisit(fixes: [.init(90, 10.0, 10), .init(150, 10.0, 10)]) { harness in
            await harness.advance(to: 90)
            #expect(dwells(harness).count == 1)
            harness.deliverCrossing(fence: "A", transition: .enter, identity: 30)
            harness.enterForeground()
            try await harness.settleBoundaries()
            await harness.advance(to: 150)
            #expect(dwells(harness).count == 1)
            #expect(dwells(harness).first?.timestamp == harness.epoch.addingTimeInterval(90))
        }
    }

    @Test
    @available(iOS 17.0, *)
    func exit_whenVisitEndsBeforeThreshold_thenDeadlineCancelledAndShortDurationReported() async throws {
        try await withVisit(fixes: [.init(40, 10.0151, 10), .init(90, 10.0, 10)]) { harness in
            await harness.advance(to: 40)
            harness.deliverCrossing(fence: "A", transition: .exit)
            try await harness.settleBoundaries()
            let exit = try #require(harness.deliveredMetrics.filter { $0.transition == .exit }.only)
            #expect(exit.visitDurationSeconds == 10)
            #expect(harness.dwellScheduler.nextDeadline == nil)
            await harness.advance(to: 90)
            #expect(dwells(harness).isEmpty)
        }
    }

    @Test
    @available(iOS 17.0, *)
    func exit_whenVisitAlreadyDwelled_thenSharesVisitAndReportsDuration() async throws {
        try await withVisit(fixes: [.init(90, 10.0, 10), .init(100, 10.0151, 10)]) { harness in
            await harness.advance(to: 90)
            let dwell = try #require(dwells(harness).only)
            await harness.advance(to: 100)
            harness.deliverCrossing(fence: "A", transition: .exit)
            try await harness.settleBoundaries()
            let exit = try #require(harness.deliveredMetrics.filter { $0.transition == .exit }.only)
            #expect(exit.visitId == dwell.visitId)
            #expect(exit.enteredAt == dwell.enteredAt)
            #expect(exit.visitDurationSeconds == 70)
            #expect(exit.dwellDurationSeconds == nil)
        }
    }

    @Test
    @available(iOS 17.0, *)
    func reentry_whenPriorVisitDwelled_thenNewVisitCanDwellAgain() async throws {
        try await withVisit(fixes: [.init(90, 10.0, 10), .init(100, 10.0151, 10), .init(130, 10.0, 10), .init(190, 10.0, 10)]) { harness in
            await harness.advance(to: 90)
            await harness.advance(to: 100)
            harness.deliverCrossing(fence: "A", transition: .exit)
            try await harness.settleBoundaries()
            await harness.advance(to: 130)
            harness.deliverCrossing(fence: "A", transition: .enter)
            try await harness.settleBoundaries()
            await harness.advance(to: 189)
            #expect(dwells(harness).count == 1)
            await harness.advance(to: 190)
            #expect(dwells(harness).count == 2)
            #expect(Set(dwells(harness).compactMap(\.visitId)).count == 2)
        }
    }

    @Test
    @available(iOS 17.0, *)
    func restart_whenVisitHasPendingDeadline_thenOldProcessStopsAndNewProcessResumesVisit() async throws {
        try await withVisit(fixes: [.init(90, 10.0, 10)]) { harness in
            await harness.advance(to: 40)
            let visit = try #require(await harness.storedVisit(fence: "A"))
            let oldCoordinator = try #require(harness.dwellCoordinator)
            let oldDelivery = try #require(harness.deliveryTracker)
            harness.reenterProcess()
            #expect(harness.dwellScheduler.nextDeadline == nil, "the dead process still has a pending timer")
            await harness.wireMonitor()
            try await harness.settleBoundaries()
            await harness.advance(to: 89)
            #expect(dwells(harness).isEmpty)
            await harness.advance(to: 90)
            let dwell = try #require(dwells(harness).only)
            #expect(dwell.visitId == visit.visitId)
            #expect(oldDelivery.trackMetricReceivedInvocations.allSatisfy { $0.metric.transition != .dwell })
            #expect(oldCoordinator !== harness.dwellCoordinator)
        }
    }

    @Test
    @available(iOS 17.0, *)
    func deadline_whenLegacyCatalogueOmitsThreshold_thenDwellDisabled() async throws {
        try await withVisit(fixes: [.init(90, 10.0, 10)], threshold: nil) { harness in
            await harness.advance(to: 600)
            #expect(dwells(harness).isEmpty)
            #expect(harness.dwellScheduler.nextDeadline == nil)
        }
    }

    @available(iOS 17.0, *)
    private func dwells(_ harness: ReplayHarness) -> [PendingGeofenceMetric] {
        harness.deliveredMetrics.filter { $0.transition == .dwell }
    }

    private struct Fix {
        let at: TimeInterval
        let latitude: Double
        let accuracy: Double

        init(_ at: TimeInterval, _ latitude: Double, _ accuracy: Double) {
            self.at = at
            self.latitude = latitude
            self.accuracy = accuracy
        }
    }

    /// Reads are synthetic OS answers. Setup still uses the real API decoder, registration,
    /// monitor callback, visit store and tracker; it never writes a visit into storage.
    @available(iOS 17.0, *)
    private func withVisit(
        fixes: [Fix],
        threshold: Int? = 60,
        run: (ReplayHarness) async throws -> Void
    ) async throws {
        try await ReplayHarness.withTail {
            let harness = ReplayHarness()
            defer { harness.detachFromBootstrap()
                harness.dwellScheduler.cancelAll()
            }
            let dwell = threshold.map { ",\"dwellThresholdSeconds\":\($0)" } ?? ""
            try harness.enqueueFetch(bodyJSON: """
            [{"id":"A","name":"Synthetic dwell","latitude":10,"longitude":20,"radius":250,"transitionTypes":["enter","exit"],"geosetIds":["7"]\(dwell)}]
            """)
            let readings: [Fix] = [.init(0, 10.0151, 10), .init(30, 10.0, 10)] + fixes
            harness.loadPulledFixes(stimuli: readings.map(\.at), samples: readings.map {
                harness.pulledFix(latitude: $0.latitude, longitude: 20, accuracy: $0.accuracy, age: 0, at: $0.at)
            })
            harness.setIdentified(true)
            #expect(await settleOnMain { harness.acquireFixCallCount >= 1 })
            harness.feedFix(latitude: 10.0151, longitude: 20, accuracy: 10, age: 0, source: .bus)
            try await harness.settleBoundaries()
            #expect(harness.emitted(ev: "registration.applied").count == 1)
            await harness.advance(to: 30)
            harness.deliverCrossing(fence: "A", transition: .enter)
            try await harness.settleBoundaries()
            let visit = try #require(await harness.storedVisit(fence: "A"))
            #expect(visit.entryObserved, "the fixture must describe an observed arrival")
            #expect(harness.dwellScheduler.nextDeadline == threshold.map { 30 + TimeInterval($0) })
            try await run(harness)
        }
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
