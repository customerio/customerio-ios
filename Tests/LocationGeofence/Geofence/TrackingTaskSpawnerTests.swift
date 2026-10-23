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
        let patient = Task { await spawner.awaitIdle(timeout: 30) }
        let timeout = await spawner.awaitIdle(timeout: 0.02)
        #expect(timeout == TrackingTaskSpawner.IdleTimeout(inFlight: 1, parked: 0))

        spawner.workFinished()
        #expect(await patient.value == nil)
    }

    @Test
    func awaitIdle_givenSpawnedTask_expectResultAndIdle() async {
        let spawner = TrackingTaskSpawner()
        let task = spawner.spawn { 42 }
        #expect(await task.value == 42)
        #expect(await spawner.awaitIdle(timeout: 30) == nil)
        #expect(spawner.inFlight == 0)
    }
}
