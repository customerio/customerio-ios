@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

@Suite("GeofenceTaskSpawning")
@MainActor
struct GeofenceTaskSpawningTests {
    enum Kind: String, CaseIterable, Sendable {
        case live
        case tracking

        func make() -> any GeofenceTaskSpawning {
            switch self {
            case .live: LiveGeofenceTaskSpawner()
            case .tracking: TrackingTaskSpawner()
            }
        }
    }

    @MainActor
    final class OrderLog {
        var entries: [Int] = []
    }

    enum WaiterStep: Sendable {
        case registered
        case returned
    }

    actor ActorLog {
        var entries: [Int] = []

        /// The `spawn` closures touch `entries` without `await`, which compiles only if they inherit
        /// this actor's isolation exactly as the `Task` closures do.
        func start(_ spawner: any GeofenceTaskSpawning) -> [Task<Void, Never>] {
            (0 ..< 20).map { index in
                index.isMultiple(of: 2)
                    ? Task { self.entries.append(index) }
                    : spawner.spawn { self.entries.append(index) }
            }
        }

        func snapshot() -> [Int] {
            entries
        }
    }

    /// The `spawn` closures call a main-actor method without `await`: this compiles only if they
    /// inherit the caller's main-actor isolation, as `Task { }` does.
    @Test(arguments: Kind.allCases)
    func spawn_givenMainActorCaller_expectTaskOrderAndIsolation(_ kind: Kind) async {
        let spawner = kind.make()
        let log = OrderLog()

        let tasks: [Task<Void, Never>] = (0 ..< 20).map { index in
            index.isMultiple(of: 2)
                ? Task { log.entries.append(index) }
                : spawner.spawn { log.entries.append(index) }
        }
        for task in tasks {
            await task.value
        }

        #expect(log.entries == Array(0 ..< 20))
    }

    @Test(arguments: Kind.allCases)
    func spawn_givenExplicitMainActorFromNonisolated_expectTaskOrder(_ kind: Kind) async {
        let spawner = kind.make()
        let log = OrderLog()

        let tasks = Self.startFromNonisolated(spawner, log)
        for task in tasks {
            await task.value
        }

        #expect(log.entries == Array(0 ..< 20))
    }

    private nonisolated static func startFromNonisolated(
        _ spawner: any GeofenceTaskSpawning,
        _ log: OrderLog
    ) -> [Task<Void, Never>] {
        (0 ..< 20).map { index in
            index.isMultiple(of: 2)
                ? Task { @MainActor in
                    log.entries.append(index)
                }
                : spawner.spawn { @MainActor in
                    log.entries.append(index)
                }
        }
    }

    @Test(arguments: Kind.allCases)
    func spawn_givenActorCaller_expectTaskOrderAndIsolation(_ kind: Kind) async {
        let log = ActorLog()

        let tasks = await log.start(kind.make())
        for task in tasks {
            await task.value
        }

        #expect(await log.snapshot() == Array(0 ..< 20))
    }

    /// The closure doesn't inherit the caller's main actor, so a busy main thread can't hold it up.
    /// Checked by thread, not by holding the main thread against a deadline a slow runner misses.
    @Test(arguments: Kind.allCases)
    func spawnDetached_givenMainActorCaller_expectOperationOffMainThread(_ kind: Kind) async {
        let ranOnMainThread = await kind.make().spawnDetached { pthread_main_np() != 0 }.value

        #expect(!ranOnMainThread, "the detached work ran on the main actor")
    }

    @Test
    func trackingSpawner_givenDetachedWork_expectCountedUntilItFinishes() async {
        let spawner = TrackingTaskSpawner()
        let gate = AsyncStream<Void>.makeStream()

        let task = spawner.spawnDetached {
            for await _ in gate.stream {}
        }
        #expect(spawner.inFlight == 1)

        gate.continuation.finish()
        await task.value
        #expect(await spawner.awaitIdle(timeout: TrackingTaskSpawner.noDeadline) == nil)

        #expect(spawner.inFlight == 0)
    }

    /// The sequence a replay fix request runs in one main-actor job: its caller is published as
    /// parked, which reads idle, and the job then starts the timeout and answer it waits on. The
    /// waiter woken in between must keep waiting until that work is done.
    @Test
    func trackingSpawner_givenParkedPublishedBeforeTheWorkItAwaits_expectWaiterKeepsWaiting() async throws {
        let spawner = TrackingTaskSpawner()
        let log = OrderLog()
        let callerHeld = AsyncStream<Void>.makeStream()
        let startedHeld = AsyncStream<Void>.makeStream()
        // Each step the waiter takes, awaited in order rather than polled against the wall clock.
        let (waiterSteps, waiterStep) = AsyncStream<WaiterStep>.makeStream()
        spawner.onWaiterRegistered = { waiterStep.yield(.registered) }
        var steps = waiterSteps.makeAsyncIterator()
        let caller = spawner.spawn {
            for await _ in callerHeld.stream {}
        }
        let waiter = Task {
            let timeout = await spawner.awaitIdle(timeout: TrackingTaskSpawner.noDeadline)
            log.entries.append(0)
            waiterStep.yield(.returned)
            return timeout
        }
        try #require(await steps.next() == .registered)

        spawner.setParked(1)
        let started = spawner.spawn {
            for await _ in startedHeld.stream {}
            log.entries.append(1)
        }

        #expect(await steps.next() == .registered, "the waiter returned while the work its caller waits on still ran")
        #expect(log.entries.isEmpty)
        startedHeld.continuation.finish()
        await started.value
        #expect(await waiter.value == nil)
        #expect(log.entries == [1, 0])
        callerHeld.continuation.finish()
        await caller.value
    }

    @Test
    func trackingSpawner_givenSuspendedWork_expectCountedUntilItFinishes() async {
        let spawner = TrackingTaskSpawner()
        let gate = AsyncStream<Void>.makeStream()

        let task = spawner.spawn {
            for await _ in gate.stream {}
        }
        #expect(spawner.inFlight == 1)

        gate.continuation.finish()
        await task.value
        #expect(await spawner.awaitIdle(timeout: TrackingTaskSpawner.noDeadline) == nil)

        #expect(spawner.inFlight == 0)
    }
}
