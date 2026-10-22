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
                harness.pulledFix(latitude: 10, longitude: 20, accuracy: 10, age: 0, at: 220.6)
            ])
            await harness.advance(to: 99.9)
            #expect(dwells(harness).isEmpty)
            #expect(harness.fixRequestCount == 1)
            await harness.advance(to: 100)
            #expect(dwells(harness).isEmpty)
            #expect(harness.dwellScheduler.nextDeadline == 220, "retry starts after the actual request timeout")
            await harness.advance(to: 220.5)
            #expect(dwells(harness).isEmpty)
            await harness.advance(to: 220.6)
            let dwell = try #require(dwells(harness).only)
            #expect(abs(dwell.timestamp.timeIntervalSince(harness.epoch) - 220.6) < 0.001)
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
            #expect(harness.dwellScheduler.nextDeadline == 220)
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
                harness.pulledFix(latitude: 10, longitude: 20, accuracy: 10, age: 0, at: 211)
            ], processStarts: [0, 90.2])
            await harness.advance(to: 90.2)
            let oldResolver = try #require(harness.dwellCoordinator?.fixResolver)
            // Idle: the one request so far is the dwell resolver's, which stays pending in the dead
            // process. A probe through that resolver would only join it and never reach the port.
            try #require(harness.fixRequestCount == 1, "only the dwell deadline may have requested a fix")
            let oldPolygonFixResolver = harness.resolver.fixResolver
            let oldDelivery = try #require(harness.deliveryTracker)
            let visit = try #require(await harness.storedVisit(fence: "A"))
            harness.reenterProcess()
            await harness.wireMonitor()
            await GeofenceBootstrap.awaitPendingWorkForTesting()
            try await ReplayHarness.letAsyncWorkRun()
            // A retained graph can start late work. Its request port must not issue another OS
            // request in the replacement process.
            let requestsBeforeOldWork = harness.fixRequestCount
            oldPolygonFixResolver.resolve(cached: nil, purpose: .polygon) { _, _ in }
            #expect(harness.fixRequestCount == requestsBeforeOldWork)
            await harness.advance(to: 90.6)
            #expect(oldResolver.latestFix == nil, "a retained dead graph consumed its old OS reply")
            #expect(dwells(harness).isEmpty, "the new process's recorded reply has not arrived")
            // The relaunch's own request waits out the spacing since the old process's, at 90.
            await harness.advance(to: 210.9)
            #expect(dwells(harness).isEmpty, "the new process's recorded reply has not arrived")
            #expect(harness.fixRequestCount == requestsBeforeOldWork + 1, "one request, once the spacing allows")
            await harness.advance(to: 211)
            let dwell = try #require(dwells(harness).only)
            #expect(oldResolver.latestFix == nil, "the dead process must not receive its parked callback")
            #expect(dwell.visitId == visit.visitId)
            #expect(dwell.timestamp == harness.epoch.addingTimeInterval(211))
            #expect(oldDelivery.trackMetricReceivedInvocations.allSatisfy { $0.metric.transition != .dwell })
        }
    }

    @Test
    @available(iOS 17.0, *)
    func restart_whenOldRequestIsPending_thenDeadProcessNeverTimesItOut() async throws {
        try await withVisit(fixes: []) { harness in
            harness.fixes.loadRequestedAnswers([
                harness.pulledFix(latitude: 10, longitude: 20, accuracy: 10, age: 0, at: 91)
            ], processStarts: [0, 90.2])
            await harness.advance(to: 90.2)
            // The old process's request has no reply of its own; its timeout is due at 100.
            try #require(harness.fixRequestCount == 1, "the deadline's request must be pending before restart")
            let oldResolver = try #require(harness.dwellCoordinator?.fixResolver)
            var deadCompletions = 0
            oldResolver.resolve(cached: nil, purpose: .pendingEvents) { _, _ in deadCompletions += 1 }
            harness.reenterProcess()
            try await ReplayHarness.letAsyncWorkRun()
            #expect(deadCompletions == 0, "the stopped process timed out its request at restart")
            await harness.wireMonitor()
            await GeofenceBootstrap.awaitPendingWorkForTesting()
            await harness.advance(to: 100)
            #expect(deadCompletions == 0, "the stopped process timed out its request at its old deadline")
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
            // Its request waits out the spacing since the old process's, at 90.
            await harness.advance(to: 210)
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
            #expect(harness.dwellScheduler.nextDeadline == 220)
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
        try await withVisit(fixes: [.init(210, 10.0, 10)]) { harness in
            await harness.advance(to: 90)
            #expect(dwells(harness).isEmpty, "a timer or renewed cache timestamp qualified dwell")
            await harness.advance(to: 209)
            #expect(dwells(harness).isEmpty)
            await harness.advance(to: 210)
            let dwell = try #require(dwells(harness).only)
            #expect(dwell.timestamp == harness.epoch.addingTimeInterval(210))
            #expect(dwell.dwellDurationSeconds == 180)
        }
    }

    @Test
    @available(iOS 17.0, *)
    func deadline_whenAccuracyOverlapsBoundary_thenNoDwellUntilReliableInsideFix() async throws {
        try await withVisit(fixes: [.init(90, 10.0, 500), .init(210, 10.0, 10)]) { harness in
            await harness.advance(to: 90)
            #expect(dwells(harness).isEmpty)
            await harness.advance(to: 210)
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

    @Test(arguments: [true, false])
    @available(iOS 17.0, *)
    func suspend_whenThresholdPassesWhileFrozen_thenThawNeedsFreshProof(inside: Bool) async throws {
        try await withVisit(fixes: []) { harness in
            // After the thaw: the provider drops an unrequested answer the clock has already passed.
            harness.fixes.loadRequestedAnswers([
                harness.pulledFix(latitude: inside ? 10 : 10.0151, longitude: 20, accuracy: 10, age: 0.2, at: 200.5)
            ])
            await harness.advance(to: 60)
            let requests = harness.fixRequestCount
            harness.suspendExecution()
            await harness.advance(to: 200)
            try await harness.settleBoundaries()
            #expect(harness.now == harness.epoch.addingTimeInterval(200), "drive time must move while frozen")
            #expect(harness.fixRequestCount == requests, "a frozen process ran its dwell deadline")
            #expect(dwells(harness).isEmpty)
            await harness.resumeExecution()
            #expect(harness.fixRequestCount == requests + 1, "the overdue deadline must run at the thaw")
            #expect(dwells(harness).isEmpty, "the thaw is not evidence; the reply has not arrived")
            await harness.advance(to: 200.5)
            if inside {
                let dwell = try #require(dwells(harness).only)
                #expect(abs(dwell.timestamp.timeIntervalSince(harness.epoch) - 200.3) < 0.001, "dated by the proof fix")
                #expect(dwell.dwellDurationSeconds == 170)
            } else {
                #expect(dwells(harness).isEmpty)
                #expect(await harness.storedVisit(fence: "A") == nil, "fresh outside proof ends the visit")
            }
        }
    }

    @Test
    @available(iOS 17.0, *)
    func suspend_whenReplyIsInFlight_thenHeldUntilThawAndTooOldToDwell() async throws {
        try await withVisit(fixes: []) { harness in
            harness.fixes.loadRequestedAnswers([
                harness.pulledFix(latitude: 10, longitude: 20, accuracy: 10, age: 0, at: 95)
            ])
            await harness.advance(to: 92)
            try #require(harness.fixRequestCount == 1, "the deadline's request must be in flight")
            // Probes park on the same gate as fetch and requested-fix answers.
            var answeredAt: [String: Date] = [:]
            await harness.gate.park(at: 95, what: "in flight") { answeredAt["in flight"] = harness.now }
            harness.suspendExecution()
            await harness.advance(to: 300)
            await harness.gate.park(at: 250, what: "overdue") { answeredAt["overdue"] = harness.now }
            try await harness.settleBoundaries()
            #expect(answeredAt.isEmpty, "a frozen process received a reply")
            #expect(harness.dwellCoordinator.fixResolver.latestFix == nil, "the recorded reply reached a frozen process")
            await harness.resumeExecution()
            let thaw = harness.epoch.addingTimeInterval(300)
            #expect(answeredAt == ["in flight": thaw, "overdue": thaw], "held replies arrive at the thaw, not their recorded moment")
            #expect(harness.now == thaw, "the thaw rewound the clock")
            #expect(dwells(harness).isEmpty, "a fix measured at 95 is not proof at 300")
            #expect(harness.dwellScheduler.nextDeadline == 420, "the overdue timeout runs at the thaw, so the retry starts there")
            await harness.advance(to: 450)
            #expect(dwells(harness).isEmpty)
            #expect(await harness.storedVisit(fence: "A") != nil, "old inside evidence must not end the visit")
        }
    }

    /// The polygon twin of the frozen-threshold case. The outside answer is beyond the square but
    /// inside its enclosing circle, so a circle check would dwell and only the real shape refuses it.
    @Test(arguments: [true, false])
    @available(iOS 17.0, *)
    func suspend_whenPolygonThresholdPassesWhileFrozen_thenThawNeedsFreshShapeProof(inside: Bool) async throws {
        try await withVisit(fixes: [], polygon: true) { harness in
            let visit = try #require(await harness.storedVisit(fence: "A"))
            let requests = harness.fixRequestCount
            // Loaded after entry, so the entry pass kept its synthetic answer and this one is the thaw's.
            harness.fixes.loadRequestedAnswers([
                harness.pulledFix(latitude: inside ? 10 : 10.0015, longitude: 20, accuracy: 10, age: 0.2, at: 200.5)
            ])
            await harness.advance(to: 40)
            try #require(harness.fixRequestCount == requests, "an earlier request would take the thaw's answer")
            harness.suspendExecution()
            await harness.advance(to: 200)
            try await harness.settleBoundaries()
            #expect(harness.now == harness.epoch.addingTimeInterval(200), "drive time must move while frozen")
            #expect(harness.fixRequestCount == requests, "a frozen process ran its dwell deadline")
            #expect(dwells(harness).isEmpty)
            await harness.resumeExecution()
            #expect(
                await settleOnMain { harness.fixRequestCount == requests + 1 },
                "the overdue deadline must request polygon proof at the thaw"
            )
            #expect(dwells(harness).isEmpty, "the thaw is not evidence; the reply has not arrived")
            await harness.advance(to: 200.5)
            try #require(await settleOnMain {
                guard let fix = harness.resolver.fixResolver.latestFix else { return false }
                return abs(fix.timestamp.timeIntervalSince(harness.epoch) - 200.3) < 0.001
            }, "the thaw's proof must reach the polygon resolver")
            if inside {
                try #require(await settleOnMain { dwells(harness).count == 1 })
                let dwell = try #require(dwells(harness).only)
                #expect(dwell.visitId == visit.visitId)
                #expect(dwell.enteredAt == harness.epoch.addingTimeInterval(30), "entry dated by the entry fix")
                #expect(abs(dwell.timestamp.timeIntervalSince(harness.epoch) - 200.3) < 0.001, "dated by the proof fix")
                #expect(dwell.dwellDurationSeconds == 170)
            }
            // Past every evidence retry: one DWELL for the visit, none from a fix outside the shape.
            await harness.advance(to: 400)
            #expect(dwells(harness).count == (inside ? 1 : 0))
            if inside {
                #expect(await harness.storedVisit(fence: "A")?.emitted == true, "the visit keeps its DWELL marker")
            } else {
                #expect(await harness.storedVisit(fence: "A") == nil, "fresh outside-polygon proof ends the visit")
                let exits = harness.deliveredMetrics.filter { $0.transition == .exit }
                #expect(exits.count == 1, "an outside proof ends the visit exactly once")
                // Found outside 170 s after the entry: the EXIT is timed to the fix, and the gap
                // since the device was last proven inside travels with it as the uncertainty.
                #expect(exits.first?.visitId == visit.visitId)
                #expect(exits.first?.visitDurationSeconds == 170)
                #expect(exits.first?.visitDurationUncertaintySeconds == 170)
            }
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

    /// Fence A as a square ~110 m from centre to each edge: one closed ring, longitude first, as the
    /// API sends it. Latitude 10.0015 is ~56 m outside its north edge and ~167 m from the centre.
    private static let polygonWireFields = #""shape":"polygon","geometry":{"type":"Polygon","coordinates":"#
        + #"[[[19.999,9.999],[20.001,9.999],[20.001,10.001],[19.999,10.001],[19.999,9.999]]]},"#
        + #""enclosingCircle":{"latitude":10,"longitude":20,"baseRadiusM":250}"#

    /// Reads are synthetic OS answers. Setup still uses the real API decoder, registration,
    /// monitor callback, visit store and tracker; it never writes a visit into storage.
    @available(iOS 17.0, *)
    private func withVisit(
        fixes: [Fix],
        threshold: Int? = 60,
        polygon: Bool = false,
        run: (ReplayHarness) async throws -> Void
    ) async throws {
        try await ReplayHarness.withTail {
            let harness = ReplayHarness()
            defer { harness.detachFromBootstrap()
                harness.dwellScheduler.cancelAll()
            }
            let dwell = threshold.map { ",\"dwellThresholdSeconds\":\($0)" } ?? ""
            // One centre and 250 m circle either way; a polygon sends it as its enclosing circle.
            let shape = polygon ? Self.polygonWireFields : #""latitude":10,"longitude":20,"radius":250"#
            try harness.enqueueFetch(bodyJSON: """
            [{"id":"A","name":"Synthetic dwell",\(shape),"transitionTypes":["enter","exit"],"geosetIds":["7"]\(dwell)}]
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
            if polygon {
                try #require(await harness.hasRegisteredPolygons(), "fence A must decode and register as a real polygon")
            }
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
