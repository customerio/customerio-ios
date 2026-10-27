import Foundation
import Testing

struct TrackingTaskSpawnerTests {
    @Test
    func awaitIdle_givenNoWork_expectImmediateSuccess() async {
        let spawner = TrackingTaskSpawner()
        #expect(await spawner.awaitIdle(timeout: 0) == nil)
    }

    @Test
    func awaitIdle_givenWorkWaitingOnParkedWork_expectDeadlineCountsAndRecovery() async {
        let spawner = TrackingTaskSpawner()
        spawner.workStarted()
        spawner.workStarted()
        spawner.setParked(1)

        let timeout = await spawner.awaitIdle(timeout: 0.02)
        #expect(timeout == TrackingTaskSpawner.IdleTimeout(inFlight: 2, parked: 1))
        #expect(timeout?.description.contains("inFlight=2, parked=1") == true)

        spawner.workFinished()
        #expect(await spawner.awaitIdle(timeout: 0) == nil)
        spawner.setParked(0)
        spawner.workFinished()
        #expect(spawner.inFlight == 0)
    }

    @Test
    func awaitIdle_givenTwoWaiters_expectTimeoutDoesNotConsumeOtherWaiter() async {
        let spawner = TrackingTaskSpawner()
        spawner.workStarted()
        let patient = Task { await spawner.awaitIdle(timeout: TrackingTaskSpawner.noDeadline) }
        let timeout = await spawner.awaitIdle(timeout: 0.02)
        #expect(timeout == TrackingTaskSpawner.IdleTimeout(inFlight: 1, parked: 0))

        spawner.workFinished()
        #expect(await patient.value == nil)
    }

    @Test
    @MainActor
    func awaitIdle_givenTransientIdleOnMainActor_expectRecheckBeforeReturning() async throws {
        let spawner = TrackingTaskSpawner()
        // Each step the waiter takes, awaited in order rather than polled against the wall clock.
        let (waiterSteps, waiterStep) = AsyncStream<Bool>.makeStream()
        spawner.onWaiterRegistered = { waiterStep.yield(true) }
        var registered = waiterSteps.makeAsyncIterator()
        spawner.workStarted()
        let waiter = Task {
            let timeout = await spawner.awaitIdle(timeout: TrackingTaskSpawner.noDeadline)
            waiterStep.yield(false)
            return timeout
        }
        try #require(await registered.next() == true)

        // One actor job briefly publishes idle before starting the work it waits on.
        spawner.workFinished()
        spawner.workStarted()
        try #require(await registered.next() == true, "the waiter returned on a transient idle")
        try #require(spawner.idleWaiterCount == 1)
        spawner.workFinished()
        #expect(await waiter.value == nil)
    }

    @Test
    func awaitIdle_givenSpawnedTask_expectResultAndIdle() async {
        let spawner = TrackingTaskSpawner()
        let task = spawner.spawn { 42 }
        #expect(await task.value == 42)
        #expect(await spawner.awaitIdle(timeout: TrackingTaskSpawner.noDeadline) == nil)
        #expect(spawner.inFlight == 0)
    }
}
