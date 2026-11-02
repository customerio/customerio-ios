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

    /// The closure doesn't inherit the caller's main actor, so a busy main actor can't hold it back.
    /// Checked by where it runs, not by how soon: work that waited for the main actor would run on
    /// the main thread. Blocking the main thread until it ran needed a time limit, and a slow runner
    /// outlasted it while every other main-actor test waited behind the blocked thread.
    @Test(arguments: Kind.allCases)
    func spawnDetached_givenMainActorCaller_expectOperationRunsOffTheMainThread(_ kind: Kind) async {
        let probe = await Task { @MainActor in Thread.isMainThread }.value
        let ranOnMainThread = await kind.make().spawnDetached { Thread.isMainThread }.value

        #expect(probe, "the probe can't tell the main thread from another")
        #expect(!ranOnMainThread, "the detached work ran on the main thread")
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
        await spawner.awaitIdle()

        #expect(spawner.inFlight == 0)
    }

    /// The sequence a replay fix request runs in one main-actor job: its caller is published as
    /// parked, which reads idle, and the job then starts the timeout and answer it waits on. The
    /// waiter woken in between must keep waiting until that work is done.
    ///
    /// The test awaits the waiter's own events, registering and returning, and not a timed poll. It
    /// can't hang: `awaitIdle` returns at its own deadline if the waiter never registers again.
    @Test
    func trackingSpawner_givenParkedPublishedBeforeTheWorkItAwaits_expectWaiterKeepsWaiting() async throws {
        enum WaiterEvent { case registered, returned }

        let spawner = TrackingTaskSpawner()
        let log = OrderLog()
        let callerHeld = AsyncStream<Void>.makeStream()
        let startedHeld = AsyncStream<Void>.makeStream()
        let events = AsyncStream<WaiterEvent>.makeStream()
        var nextEvent = events.stream.makeAsyncIterator()
        spawner.observeWaiterRegistrations { events.continuation.yield(.registered) }
        let caller = spawner.spawn {
            for await _ in callerHeld.stream {}
        }
        let waiter = Task {
            await spawner.awaitIdle()
            log.entries.append(0)
            events.continuation.yield(.returned)
        }
        try #require(await nextEvent.next() == .registered)

        spawner.setParked(1)
        let started = spawner.spawn {
            for await _ in startedHeld.stream {}
            log.entries.append(1)
        }

        // The woken waiter either keeps waiting, which registers it again, or returns.
        #expect(await nextEvent.next() == .registered, "the waiter returned while the work its caller waits on still ran")
        #expect(log.entries.isEmpty, "the waiter returned while the work its caller waits on still ran")
        startedHeld.continuation.finish()
        await started.value
        await waiter.value
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
        await spawner.awaitIdle()

        #expect(spawner.inFlight == 0)
    }
}
