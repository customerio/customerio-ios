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
            #expect(dwells(harness).isEmpty, "the requested outside fix has not arrived")
            #expect(await harness.storedVisit(fence: "A") != nil)
            await harness.advance(to: 95)
            harness.deliverCrossing(fence: "A", transition: .exit)
            #expect(await settleOnMain { harness.deliveredMetrics.contains { $0.transition == .exit } })
            #expect(harness.now == harness.epoch.addingTimeInterval(95))
            let exit = try #require(harness.deliveredMetrics.filter { $0.transition == .exit }.only)
            #expect(exit.visitDurationSeconds == 65)
            await harness.advance(to: 99)
            #expect(dwells(harness).isEmpty, "the cancelled evidence request must not emit after EXIT")
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
    func deadline_whenRequestedFixArrivesLater_thenWaitsAndPreservesRecordedMeasurementTime() async throws {
        try await withVisit(fixes: []) { harness in
            harness.fixes.loadRequestedAnswers([
                harness.pulledFix(latitude: 10, longitude: 20, accuracy: 10, age: 0.32, at: 90.6)
            ])
            await harness.advance(to: 90)
            #expect(dwells(harness).isEmpty, "the recorded response has not arrived")
            await harness.advance(to: 90.5)
            #expect(dwells(harness).isEmpty, "lookahead must not deliver future evidence early")
            await harness.advance(to: 90.6)
            let dwell = try #require(dwells(harness).only)
            #expect(abs(dwell.timestamp.timeIntervalSince(harness.epoch) - 90.28) < 0.001)
            #expect(dwell.dwellDurationSeconds == 60)
        }
    }

    @Test(arguments: [false, true])
    @available(iOS 17.0, *)
    func deadline_whenRequestedFixIsStaleOrPastTimeout_thenTimesOutAndWaitsForFreshRetry(pastTimeout: Bool) async throws {
        try await withVisit(fixes: []) { harness in
            harness.fixes.loadRequestedAnswers([
                harness.pulledFix(
                    latitude: 10,
                    longitude: 20,
                    accuracy: 10,
                    age: pastTimeout ? 0 : 31,
                    at: pastTimeout ? 100.1 : 90.6
                ),
                harness.pulledFix(latitude: 10, longitude: 20, accuracy: 10, age: 0, at: 160.6)
            ])
            await harness.advance(to: 99.9)
            #expect(dwells(harness).isEmpty)
            #expect(harness.fixRequestCount == 1)
            await harness.advance(to: 100)
            #expect(dwells(harness).isEmpty)
            #expect(harness.dwellScheduler.nextDeadline == 160, "retry starts after the actual request timeout")
            await harness.advance(to: 160.5)
            #expect(dwells(harness).isEmpty)
            await harness.advance(to: 160.6)
            let dwell = try #require(dwells(harness).only)
            #expect(abs(dwell.timestamp.timeIntervalSince(harness.epoch) - 160.6) < 0.001)
        }
    }

    @Test
    @available(iOS 17.0, *)
    func deadline_whenReplyArrivesAfterTimeout_thenLaterForegroundUsesRetainedFix() async throws {
        try await withVisit(fixes: []) { harness in
            harness.fixes.loadRequestedAnswers([
                harness.pulledFix(latitude: 10, longitude: 20, accuracy: 10, age: 0.1, at: 100.1)
            ])
            await harness.advance(to: 100)
            #expect(dwells(harness).isEmpty, "the request timeout must complete before the late reply")
            #expect(harness.dwellScheduler.nextDeadline == 160)
            await harness.advance(to: 100.1)
            #expect(dwells(harness).isEmpty, "a late reply cannot complete the timed-out request")
            let fix = try #require(harness.dwellCoordinator.fixResolver.latestFix)
            #expect(abs(fix.timestamp.timeIntervalSince(harness.epoch) - 100) < 0.001)
            await harness.advance(to: 101)
            harness.enterForeground()
            #expect(await settleOnMain { dwells(harness).count == 1 })
            let dwell = try #require(dwells(harness).only)
            #expect(abs(dwell.timestamp.timeIntervalSince(harness.epoch) - 100) < 0.001)
            #expect(dwell.dwellDurationSeconds == 70)
        }
    }

    @Test
    @available(iOS 17.0, *)
    func restart_whenRecordedResponseBelongsToNewProcess_thenOldRequestsStayInert() async throws {
        try await withVisit(fixes: []) { harness in
            harness.fixes.loadRequestedAnswers([
                harness.pulledFix(latitude: 10, longitude: 20, accuracy: 10, age: 0, at: 91)
            ], processStarts: [0, 90.2])
            await harness.advance(to: 90.2)
            let oldResolver = try #require(harness.dwellCoordinator?.fixResolver)
            let oldDelivery = try #require(harness.deliveryTracker)
            let visit = try #require(await harness.storedVisit(fence: "A"))
            harness.reenterProcess()
            await harness.wireMonitor()
            await GeofenceBootstrap.awaitPendingWorkForTesting()
            try await ReplayHarness.letAsyncWorkRun()
            // A retained graph can start late work after its old pending request has unwound.
            // Its request port must not issue another OS request in the replacement process.
            let requestsBeforeOldWork = harness.fixRequestCount
            oldResolver.resolve(cached: nil, purpose: .pendingEvents) { _, _ in }
            #expect(harness.fixRequestCount == requestsBeforeOldWork)
            await harness.advance(to: 90.6)
            #expect(oldResolver.latestFix == nil, "a retained dead graph consumed its old OS reply")
            #expect(dwells(harness).isEmpty, "the new process's recorded reply has not arrived")
            await harness.advance(to: 91)
            let dwell = try #require(dwells(harness).only)
            #expect(oldResolver.latestFix == nil, "the dead process must not receive its parked callback")
            #expect(dwell.visitId == visit.visitId)
            #expect(dwell.timestamp == harness.epoch.addingTimeInterval(91))
            #expect(oldDelivery.trackMetricReceivedInvocations.allSatisfy { $0.metric.transition != .dwell })
        }
    }

    @Test
    @available(iOS 17.0, *)
    func restart_whenSyntheticReplyBelongsToOldRequest_thenItCannotQualifyNewProcessVisit() async throws {
        try await withVisit(fixes: []) { harness in
            harness.fixes.loadRequestedAnswers([
                harness.pulledFix(latitude: 10, longitude: 20, accuracy: 10, age: 0, at: 91)
            ])
            await harness.advance(to: 90.2)
            #expect(harness.fixRequestCount == 1)
            let oldResolver = try #require(harness.dwellCoordinator?.fixResolver)
            let oldDelivery = try #require(harness.deliveryTracker)
            harness.reenterProcess()
            await harness.wireMonitor()
            await GeofenceBootstrap.awaitPendingWorkForTesting()
            await harness.advance(to: 91)
            #expect(harness.fixRequestCount == 2, "the new process must actually request evidence")
            #expect(dwells(harness).isEmpty, "an old synthetic request's reply cannot move to the new process")
            #expect(oldResolver.latestFix == nil)
            #expect(oldDelivery.trackMetricReceivedInvocations.allSatisfy { $0.metric.transition != .dwell })
            #expect(await harness.storedVisit(fence: "A") != nil)
        }
    }

    @Test
    @available(iOS 17.0, *)
    func deadline_whenRecordedResponseStreamIsEmpty_thenDoesNotInventCachedAnswer() async throws {
        try await withVisit(fixes: [.init(90, 10.0, 10)]) { harness in
            harness.fixes.loadRequestedAnswers([])
            await harness.advance(to: 90)
            #expect(dwells(harness).isEmpty, "a cached position is not a recorded OS response")
            #expect(harness.dwellScheduler.nextDeadline == 100)
            await harness.advance(to: 100)
            #expect(dwells(harness).isEmpty)
            #expect(harness.dwellScheduler.nextDeadline == 160)
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
    func exit_whenVisitEndsBeforeThreshold_thenNoLaterDwellAndShortDurationReported() async throws {
        try await withVisit(fixes: [.init(40, 10.0151, 10), .init(90, 10.0, 10)]) { harness in
            await harness.advance(to: 40)
            harness.deliverCrossing(fence: "A", transition: .exit)
            try await harness.settleBoundaries()
            let exit = try #require(harness.deliveredMetrics.filter { $0.transition == .exit }.only)
            #expect(exit.visitDurationSeconds == 10)
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
            let oldScheduler = harness.dwellScheduler
            harness.reenterProcess()
            #expect(oldScheduler.nextDeadline == nil, "the dead process still has a pending timer")
            await harness.wireMonitor()
            await GeofenceBootstrap.awaitPendingWorkForTesting()
            try await harness.settleBoundaries()
            #expect(harness.dwellScheduler.nextDeadline == 90, "bootstrap must resume the visit before foreground")
            harness.enterForeground()
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
