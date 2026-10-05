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
    func advance_whenSeveralWaitersAreDue_thenResumesInDeadlineAndRegistrationOrder() async throws {
        let scheduler = ReplayDwellScheduler()
        var resumed: [Int] = []
        var tasks: [Task<Void, Error>] = []
        for (deadline, id) in [(90, 90), (60, 60), (60, 61), (120, 120), (45, 45), (90, 91)] {
            tasks.append(Task {
                try await scheduler.sleep(nanoseconds: UInt64(deadline) * 1000000000)
                resumed.append(id)
            })
            #expect(await settleOnMain { scheduler.pendingCount == tasks.count })
        }
        scheduler.advance(to: 130)
        for task in tasks {
            try await task.value
        }
        #expect(resumed == [45, 60, 61, 90, 91, 120])
    }
}
