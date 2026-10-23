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

    /// The closure doesn't inherit the caller's main actor: it runs while the main thread is held.
    @Test(arguments: Kind.allCases)
    func spawnDetached_givenBusyMainActor_expectOperationStillRuns(_ kind: Kind) async {
        let ran = DispatchSemaphore(value: 0)

        let task = kind.make().spawnDetached { ran.signal() }

        #expect(Self.holdMainThread(until: ran), "the detached work waited for the main actor")
        await task.value
    }

    /// Holds the calling thread until `semaphore` is signalled or 10 s pass. Whether it was.
    private nonisolated static func holdMainThread(until semaphore: DispatchSemaphore) -> Bool {
        semaphore.wait(timeout: .now() + 10) == .success
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
