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
        await awaitIdle()
        // Re-scan after every boundary and deadline: a fetch answer can schedule a timer before
        // the next stimulus, and evidence can schedule a retry before the target is reached.
        await gate.advance(
            to: at,
            setClock: { [weak self] moment in self?.setClock(moment) },
            nextWakeup: { [dwellScheduler] in dwellScheduler.nextDeadline }
        ) {
            await settle()
            await awaitIdle()
        }
    }

    func releaseRemainingBoundaries(settle: () async throws -> Void) async rethrows {
        try await gate.releaseAll(
            setClock: { [weak self] moment in self?.setClock(moment) },
            nextWakeup: { [dwellScheduler] in dwellScheduler.nextDeadline },
            settle: settle
        )
    }

    func advance(to at: TimeInterval) async {
        await advance(to: at) { await self.awaitIdle() }
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
        await gate.resume(setClock: { [weak self] moment in self?.setClock(moment) }) { await self.awaitIdle() }
        dwellScheduler.resumeExecution()
        await awaitIdle()
    }

    /// Without this bound a park chain would hang, not fail.
    static let maxSettleRounds = 256

    /// Answers every parked boundary in time order, idling after each, until none is left. Idles
    /// first: the fetch parks a hop after the coordinator issues it.
    func settleBoundaries() async {
        for _ in 0 ..< Self.maxSettleRounds {
            await awaitIdle()
            // Held answers count as settled: a frozen process has nothing to settle.
            guard gate.hasReleasable else { return }
            await releaseRemainingBoundaries { await self.awaitIdle() }
        }
        Issue.record(
            "settleBoundaries gave up after \(Self.maxSettleRounds) rounds — answering a boundary keeps parking another"
        )
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
