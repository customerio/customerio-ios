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
    /// Moves virtual time to `t0 + at`, answering on the way every boundary that answered before it.
    /// `settle` runs the SDK's async work after each release, before the next is considered.
    func advance(to at: TimeInterval, settle: () async -> Void) async {
        await gate.advance(to: at, setClock: { [weak self] moment in self?.setClock(moment) }, settle: settle)
    }

    /// Ends the drive: answers whatever the recording left outstanding.
    func releaseRemainingBoundaries(settle: () async throws -> Void) async rethrows {
        try await gate.releaseAll(setClock: { [weak self] moment in self?.setClock(moment) }, settle: settle)
    }

    /// Convenience form for hand-driven tests; the runner passes its own `settle`.
    func advance(to at: TimeInterval) async {
        // Cancellation is swallowed: unwinding mid-advance would leave the clock half-moved.
        await advance(to: at) { try? await ReplayHarness.letAsyncWorkRun() }
    }

    /// The most rounds `settleBoundaries` will take before giving up.
    ///
    /// `quietRounds` resets whenever something is parked, so without a global bound a composition
    /// where answering one boundary parks another would hang the test rather than fail it.
    static let maxSettleRounds = 256

    /// Answers every outstanding boundary, and every boundary answering one leads to.
    ///
    /// Used where there is no recording to take moments from: a hand-written test, and the end of a
    /// drive whose capture stopped mid-sync.
    ///
    /// **Settles before it releases, and keeps going until nothing new appears.** The SDK reaches a
    /// boundary asynchronously (the fetch parks a hop after the coordinator issues it), so
    /// releasing immediately would find nothing parked and leave the fetch owed forever.
    ///
    /// - Throws: `CancellationError` if the test task is cancelled while settling. Not swallowed:
    ///   a `try?` would spin this loop at full speed instead of unwinding (see `Settle.swift`).
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
            guard gate.hasParked else {
                quietRounds += 1
                continue
            }
            quietRounds = 0
            try await releaseRemainingBoundaries { try await ReplayHarness.letAsyncWorkRun() }
        }
    }

    /// How long a round of `letAsyncWorkRun` waits for the SDK's tasks to get going.
    ///
    /// Real time, and the one place the harness spends any: long enough for a storage read and a
    /// dispatcher hop on a loaded machine. If a scenario diverges only under load, suspect this.
    static let asyncWorkGrace: Duration = .milliseconds(50)

    /// Gives the `Task`s the SDK started a chance to execute, up to any parked boundary.
    ///
    /// Cancellation is propagated, not swallowed, for the reason `Settle.swift` gives.
    static func letAsyncWorkRun() async throws {
        await Task.yield()
        try await Task.sleep(for: asyncWorkGrace)
    }

    /// Virtual time, in the one place that writes it.
    private func setClock(_ at: TimeInterval) {
        let moment = max(at, clock.givenNow.timeIntervalSince(epoch))
        clock.givenNow = epoch.addingTimeInterval(moment)
        fixes.now = moment
    }

    var now: Date { clock.givenNow }
}
