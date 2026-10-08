@testable import CioLocationGeofence
import Foundation
import SharedTests
import Testing

@Suite("Replay dwell scheduler", .serialized)
@MainActor
struct ReplayDwellSchedulerTests {
    @Test
    func sleep_whenDriveTimeReachesDeadline_thenResumesWithoutWallTimeWait() async throws {
        let scheduler = ReplayDwellScheduler()
        var resumed = false
        let task = Task { try await scheduler.sleep(nanoseconds: 60000000000)
            resumed = true
        }
        #expect(await settleOnMain { scheduler.nextDeadline == 60 })
        scheduler.advance(to: 59)
        await Task.yield()
        #expect(!resumed)
        #expect(scheduler.nextDeadline == 60)
        scheduler.advance(to: 60)
        try await task.value
        #expect(resumed)
        #expect(scheduler.nextDeadline == nil)
    }

    @Test
    func sleep_whenTaskCancelled_thenWaiterRemovedAndDoesNotResumeSuccessfully() async {
        let scheduler = ReplayDwellScheduler()
        let task = Task { try await scheduler.sleep(nanoseconds: 60000000000) }
        #expect(await settleOnMain { scheduler.nextDeadline != nil })
        task.cancel()
        do {
            try await task.value
            Issue.record("cancelled deadline returned successfully")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(scheduler.nextDeadline == nil)
    }

    @Test
    func stop_whenOldProcessSchedulesMoreWork_thenEveryWaitIsCancelled() async {
        let scheduler = ReplayDwellScheduler()
        let parked = Task { try await scheduler.sleep(nanoseconds: 60000000000) }
        #expect(await settleOnMain { scheduler.pendingCount == 1 })
        scheduler.stop()
        do {
            try await parked.value
            Issue.record("the dead process's waiter resumed successfully")
        } catch {
            #expect(error is CancellationError)
        }
        for delay: UInt64 in [0, 60000000000] {
            do {
                try await scheduler.sleep(nanoseconds: delay)
                Issue.record("the dead process scheduled another deadline")
            } catch {
                #expect(error is CancellationError)
            }
        }
        #expect(scheduler.pendingCount == 0)
    }

    @Test
    @available(iOS 17.0, *)
    func advance_whenBoundaryCreatesDeadline_thenRunsDeadlineBeforeNextInput() async throws {
        let harness = ReplayHarness()
        defer { harness.detachFromBootstrap()
            harness.dwellScheduler.cancelAll()
        }
        var firedAt: TimeInterval?
        Task {
            await harness.gate.park(at: 5, what: "fetch") {
                Task {
                    try await harness.dwellScheduler.sleep(nanoseconds: 60000000000)
                    firedAt = harness.now.timeIntervalSince(harness.epoch)
                }
            }
        }
        #expect(await settleOnMain { harness.gate.hasParked })
        await harness.advance(to: 500)
        #expect(firedAt == 65)
    }

    @Test
    @available(iOS 17.0, *)
    func releaseRemainingBoundaries_whenBoundaryCreatesDeadline_thenRunsDeadlineBeforeLaterAnswer() async throws {
        let harness = ReplayHarness()
        defer { harness.detachFromBootstrap()
            harness.dwellScheduler.cancelAll()
        }
        var firedAt: TimeInterval?
        Task {
            await harness.gate.park(at: 5, what: "fetch") {
                Task {
                    try await harness.dwellScheduler.sleep(nanoseconds: 60000000000)
                    firedAt = harness.now.timeIntervalSince(harness.epoch)
                }
                await harness.gate.park(at: 200, what: "later fetch") {}
            }
        }
        #expect(await settleOnMain { harness.gate.hasParked })
        try await harness.releaseRemainingBoundaries { try await ReplayHarness.letAsyncWorkRun() }
        #expect(firedAt == 65)
    }

    @Test
    func advance_whenSeveralWaitersAreParked_thenResumesOnlyThoseWhoseDeadlineHasPassed() async throws {
        let scheduler = ReplayDwellScheduler()
        // A failed step leaves waiters parked; release them rather than leak their tasks.
        defer { scheduler.cancelAll() }
        var resumed: Set<Int> = []
        var tasks: [Int: Task<Void, Error>] = [:]
        for (deadline, id) in [(90, 90), (60, 60), (60, 61), (120, 120), (45, 45), (90, 91)] {
            tasks[id] = Task {
                try await scheduler.sleep(nanoseconds: UInt64(deadline) * 1000000000)
                resumed.insert(id)
            }
            #expect(await settleOnMain { scheduler.pendingCount == tasks.count })
        }
        // Tasks one advance resumes run in whatever order the executor picks, so each step asserts
        // a set. A waiter not yet due is still held by the scheduler, so every set is exact.
        let steps = [
            DueStep(moment: 44, due: [], nextDeadline: 45, pendingCount: 6),
            DueStep(moment: 45, due: [45], nextDeadline: 60, pendingCount: 5),
            DueStep(moment: 60, due: [60, 61], nextDeadline: 90, pendingCount: 3),
            DueStep(moment: 90, due: [90, 91], nextDeadline: 120, pendingCount: 1),
            DueStep(moment: 130, due: [120], nextDeadline: nil, pendingCount: 0)
        ]
        var expected: Set<Int> = []
        for step in steps {
            scheduler.advance(to: step.moment)
            // Required: awaiting a due waiter the scheduler still holds would hang instead of fail.
            try #require(scheduler.pendingCount == step.pendingCount)
            #expect(scheduler.nextDeadline == step.nextDeadline)
            // Required too: a due waiter removed but never resumed would hang the same way.
            expected.formUnion(step.due)
            try #require(await settleOnMain { resumed == expected })
            for id in step.due {
                let task = try #require(tasks[id])
                try await task.value
            }
        }
    }

    /// One `advance(to:)` and what it must leave: the waiters it resumed and the deadlines still held.
    private struct DueStep {
        let moment: TimeInterval
        let due: Set<Int>
        let nextDeadline: TimeInterval?
        let pendingCount: Int
    }
}
