@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import CoreLocation
import Foundation
import SharedTests
import Testing
#if canImport(UIKit)
import UIKit
#endif

@available(iOS 17.0, *)
@MainActor
extension ReplayHarness {
    func advance(to at: TimeInterval, settle: () async -> Void) async {
        // A check already running must park its retry before the first scan, or the scan misses it.
        await awaitQuiescence()
        // Re-scan after every boundary and deadline: a fetch answer can schedule a timer before
        // the next stimulus, and evidence can schedule a retry before the target is reached.
        await gate.advance(
            to: at,
            setClock: { [weak self] moment in self?.setClock(moment) },
            nextWakeup: { [dwellScheduler] in dwellScheduler.nextDeadline }
        ) {
            for _ in 0 ..< 3 {
                await settle()
            }
            await awaitQuiescence()
        }
    }

    /// Until the work `advance` cannot see has ended or waits on drive time: an OS event not yet
    /// handled, a routing task, or an evidence check, each started by this process. Waiting on
    /// drive time means a reply parked on the gate or a wait on the scheduler (a request's timeout,
    /// or a retry). The real-time grace in `settle` cannot tell slow work from finished work; this
    /// can. Real time only bounds work that never ends.
    func awaitQuiescence() async {
        let limit = Date().addingTimeInterval(Self.quiescenceLimit)
        while evidenceChecksInFlight > 0 || routingsInFlight > 0 || eventsUnhandled > 0,
              !gate.hasParked, dwellScheduler.pendingCount == 0 {
            guard Date() < limit else {
                Issue.record("work neither ended nor waited on drive time within \(Self.quiescenceLimit) s")
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1000000)
        }
    }

    static let quiescenceLimit: TimeInterval = 60

    func releaseRemainingBoundaries(settle: () async throws -> Void) async rethrows {
        try await gate.releaseAll(
            setClock: { [weak self] moment in self?.setClock(moment) },
            nextWakeup: { [dwellScheduler] in dwellScheduler.nextDeadline }
        ) {
            for _ in 0 ..< 3 {
                try await settle()
            }
        }
    }

    func advance(to at: TimeInterval) async {
        // `try?`: unwinding mid-advance would leave the clock half-moved.
        await advance(to: at) { try? await ReplayHarness.letAsyncWorkRun() }
    }

    // MARK: - Execution suspension

    /// A deterministic freeze, not a model of when the OS wakes the app. `app.background` never
    /// freezes: a recorded drive backgrounds without suspending.
    var isExecutionSuspended: Bool { gate.isSuspended }

    func suspendExecution() {
        dwellScheduler.suspendExecution()
        gate.suspend()
    }

    /// Replies that came due while frozen arrive first, at the thaw moment; overdue deadlines then run
    /// and can see them. The scheduler stays frozen while the gate delivers, so the order is fixed.
    /// Real OS ordering is not modelled.
    func resumeExecution() async {
        guard isExecutionSuspended else { return }
        await gate.resume(setClock: { [weak self] moment in self?.setClock(moment) }) {
            for _ in 0 ..< 3 {
                try? await ReplayHarness.letAsyncWorkRun()
            }
        }
        dwellScheduler.resumeExecution()
        for _ in 0 ..< 3 {
            try? await ReplayHarness.letAsyncWorkRun()
        }
    }

    /// `quietRounds` resets on every park, so without this bound a park chain would hang, not fail.
    static let maxSettleRounds = 256

    /// Settles before releasing: the fetch parks a hop after the coordinator issues it. Cancellation
    /// isn't swallowed: a `try?` would spin this loop instead of unwinding.
    func settleBoundaries() async throws {
        var quietRounds = 0
        var totalRounds = 0
        while quietRounds < 3 {
            totalRounds += 1
            guard totalRounds <= Self.maxSettleRounds else {
                Issue.record(
                    "settleBoundaries gave up after \(Self.maxSettleRounds) rounds — answering a boundary keeps parking another"
                )
                return
            }
            try await ReplayHarness.letAsyncWorkRun()
            // Held answers count as quiet: a frozen process has nothing to settle.
            guard gate.hasReleasable else {
                quietRounds += 1
                continue
            }
            quietRounds = 0
            try await releaseRemainingBoundaries { try await ReplayHarness.letAsyncWorkRun() }
        }
    }

    /// Real time, the only place the harness spends any. If a scenario diverges only under load,
    /// suspect this.
    static let asyncWorkGrace: Duration = .milliseconds(50)

    static func letAsyncWorkRun() async throws {
        await Task.yield()
        try await Task.sleep(for: asyncWorkGrace)
    }

    /// The only writer of virtual time.
    private func setClock(_ at: TimeInterval) {
        let moment = max(at, clock.givenNow.timeIntervalSince(epoch))
        clock.givenNow = epoch.addingTimeInterval(moment)
        fixes.now = moment
        dwellScheduler.advance(to: moment)
    }

    var now: Date { clock.givenNow }
}
