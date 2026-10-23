@testable import CioLocationGeofence
import Foundation
import SharedTests
import Testing

@Suite("Pending dwell background collection", .serialized)
@MainActor
struct PendingDwellBackgroundCollectionTests {
    @Test
    func update_whenSameVisitRearmsLater_thenOriginalCapHoldsAndExpiredVisitIsNotRevived() async throws {
        let env = CollectionEnv(), collection = env.make()
        defer { env.scheduler.cancelAll() }
        collection.update(leases: ["visit": seconds(60)], enabled: true, eligible: true)
        try await env.parked(requests: 1, nextDeadline: 60)
        env.scheduler.advance(to: 30)
        collection.update(leases: ["visit": seconds(300)], enabled: true, eligible: true)
        try await env.parked(requests: 2, nextDeadline: 60)
        env.scheduler.advance(to: 60)
        try #require(await settleOnMain { !collection.isRunning })
        collection.update(leases: ["visit": seconds(300)], enabled: true, eligible: true)
        #expect(!collection.isRunning)
        #expect(env.events == ["start", "stop"])
    }

    @Test
    func update_whenVisitsAreReleasedAndReplaced_thenSessionRunsUntilLastRemainingVisitExpires() async throws {
        let env = CollectionEnv(), collection = env.make()
        defer { env.scheduler.cancelAll() }
        collection.update(leases: ["a": seconds(60), "b": seconds(120)], enabled: true, eligible: true)
        try await env.parked(requests: 1, nextDeadline: 60)
        // Visit a ends and visit c begins: a's withdrawn deadline neither stops nor caps c.
        collection.update(leases: ["b": seconds(120), "c": seconds(300)], enabled: true, eligible: true)
        try await env.parked(requests: 2, nextDeadline: 120)
        env.scheduler.advance(to: 120)
        // b's expiry wake re-arms for c instead of stopping the session c still needs.
        try await env.parked(requests: 3, nextDeadline: 300)
        #expect(collection.isRunning)
        env.scheduler.advance(to: 300)
        try #require(await settleOnMain { !collection.isRunning })
        #expect(env.events == ["start", "stop"])
    }

    @Test(arguments: zip([false, true], [true, false]))
    func update_whenOptedOutOrPermissionLost_thenStopsAndReleasesExpiryWait(enabled: Bool, eligible: Bool) async throws {
        let env = CollectionEnv(), collection = env.make()
        defer { env.scheduler.cancelAll() }
        collection.update(leases: ["visit": seconds(60)], enabled: true, eligible: true)
        try await env.parked(requests: 1, nextDeadline: 60)
        collection.update(leases: ["visit": seconds(60)], enabled: enabled, eligible: eligible)
        #expect(!collection.isRunning)
        #expect(env.events == ["start", "stop"])
        try #require(await settleOnMain { env.scheduler.pendingCount == 0 })
    }

    @Test
    func deinit_whenOwnerReleasesRunningCollection_thenPendingExpiryWaitIsCancelled() async throws {
        let env = CollectionEnv()
        defer { env.scheduler.cancelAll() }
        var collection: PendingDwellBackgroundCollection<String>? = env.make()
        collection?.update(leases: ["visit": seconds(60)], enabled: true, eligible: true)
        try await env.parked(requests: 1, nextDeadline: 60)
        // This read also keeps the collection alive until its wait has parked.
        #expect(collection?.isRunning == true)
        collection = nil
        try #require(await settleOnMain { env.scheduler.pendingCount == 0 })
        // The owner stops its own location session; release does not call back into it.
        #expect(env.events == ["start"])
    }

    /// Lease deadlines are read on one clock and the expiry wait parks on another that stands still,
    /// as an awake-time wait does through device sleep. Expiry is judged on `now`, never on the wait
    /// having fired, so the next reconcile stops the session and releases the stalled wait. This does
    /// not show that production waits keep counting through sleep; only a device run can.
    @Test
    func update_whenNowPassesCapWhileExpiryWaitIsStalled_thenStopsAndReleasesTheWait() async throws {
        let env = TwoClockEnv(), collection = env.make()
        defer { env.awake.cancelAll() }
        collection.update(leases: ["visit": seconds(60)], enabled: true, eligible: true)
        try #require(await settleOnMain { env.awake.pendingCount == 1 && env.awake.nextDeadline == 60 })
        env.continuous = seconds(4000)
        // The clocks have diverged and nothing has reconciled: the collection cannot see its cap pass.
        #expect(collection.isRunning)
        #expect(env.awake.pendingCount == 1)
        // Any reconcile, here the same lease set again, judges expiry on `now`.
        collection.update(leases: ["visit": seconds(60)], enabled: true, eligible: true)
        #expect(!collection.isRunning)
        #expect(env.events == ["start", "stop"])
        try #require(await settleOnMain { env.awake.pendingCount == 0 })
    }
}

private func seconds(_ value: UInt64) -> UInt64 {
    value * 1000000000
}

@MainActor
private final class CollectionEnv {
    let scheduler = ReplayDwellScheduler()
    private(set) var events: [String] = []
    private var sleeps = 0

    func make() -> PendingDwellBackgroundCollection<String> {
        PendingDwellBackgroundCollection(
            now: { [scheduler] in UInt64(scheduler.now * 1000000000) },
            sleep: { @MainActor [self] delay in
                // Counted in the main-actor job that parks the waiter, so `parked` cannot match
                // before the new wait parks or while a replaced wait is still held.
                sleeps += 1
                try await scheduler.sleep(nanoseconds: delay)
            },
            start: { [self] in events.append("start") },
            stop: { [self] in events.append("stop") }
        )
    }

    /// The collection has requested `requests` waits in total and only the latest is parked.
    func parked(requests: Int, nextDeadline: TimeInterval, at location: SourceLocation = #_sourceLocation) async throws {
        try #require(await settleOnMain {
            self.sleeps == requests && self.scheduler.pendingCount == 1 && self.scheduler.nextDeadline == nextDeadline
        }, sourceLocation: location)
    }
}

/// Deadlines on one clock, waits on another: continuous uptime against an awake-time wait.
@MainActor
private final class TwoClockEnv {
    /// Where expiry waits park. It stands still while `continuous` jumps, as awake time does in device sleep.
    let awake = ReplayDwellScheduler()
    /// The collection's `now`, in nanoseconds of continuous uptime.
    var continuous: UInt64 = 0
    private(set) var events: [String] = []

    func make() -> PendingDwellBackgroundCollection<String> {
        PendingDwellBackgroundCollection(
            now: { [self] in continuous },
            sleep: { @MainActor [self] delay in try await awake.sleep(nanoseconds: delay) },
            start: { [self] in events.append("start") },
            stop: { [self] in events.append("stop") }
        )
    }
}

extension PendingDwellBackgroundCollectionTests {
    @Test
    func update_whenExpiryWaitFirstRunsAfterTheCap_thenStopsWithoutParkingAFreshDelay() async throws {
        let env = CollectionEnv(), collection = env.make()
        defer { env.scheduler.cancelAll() }
        collection.update(leases: ["visit": seconds(60)], enabled: true, eligible: true)
        // Still in this main-actor job, so before the expiry wait's first job: the clock passes the
        // cap, as it does while the process is suspended between the update and that job.
        env.scheduler.advance(to: 90)
        // No later update or advance: only the wait itself can notice the cap has passed.
        try #require(await settleOnMain { !collection.isRunning })
        #expect(env.events == ["start", "stop"])
        #expect(env.scheduler.pendingCount == 0)
    }

    @Test
    func update_whenExpiryWaitFirstRunsLateBeforeTheCap_thenParksOnlyUntilTheCap() async throws {
        let env = CollectionEnv(), collection = env.make()
        defer { env.scheduler.cancelAll() }
        collection.update(leases: ["visit": seconds(60)], enabled: true, eligible: true)
        env.scheduler.advance(to: 40)
        // Parked until the cap at 60, not 100: the lag before the first job does not extend it.
        try await env.parked(requests: 1, nextDeadline: 60)
        env.scheduler.advance(to: 60)
        try #require(await settleOnMain { !collection.isRunning })
        #expect(env.events == ["start", "stop"])
    }
}
