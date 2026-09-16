@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import CoreLocation
import Foundation
import SharedTests
#if canImport(UIKit)
import UIKit
#endif

@available(iOS 17.0, *)
@MainActor
extension ReplayHarness {
    /// Moves virtual time to `t0 + at`, answering on the way every boundary that answered before it.
    ///
    /// The only way the harness advances time. It is `async` because a release usually reaches the
    /// next boundary straight away, and each one needs the SDK's own async work to run before the
    /// next is considered.
    func advance(to at: TimeInterval, settle: () async -> Void) async {
        await gate.advance(to: at, setClock: { [weak self] moment in self?.setClock(moment) }, settle: settle)
    }

    /// Ends the drive: answers whatever the recording left outstanding.
    func releaseRemainingBoundaries(settle: () async -> Void) async {
        await gate.releaseAll(setClock: { [weak self] moment in self?.setClock(moment) }, settle: settle)
    }

    /// Moves virtual time, letting the SDK's own async work run between releases.
    ///
    /// The convenience form, for tests that drive the harness by hand. The recorded suite passes
    /// its own `settle` so the runner owns the pacing in one place.
    func advance(to at: TimeInterval) async {
        await advance(to: at) { try? await ReplayHarness.letAsyncWorkRun() }
    }

    /// Answers every outstanding boundary, and every boundary answering one leads to.
    ///
    /// Used where there is no recording to take moments from: a hand-written test, and the end of a
    /// drive whose capture stopped mid-sync. "Answer them all" is the only meaning available there.
    ///
    /// **It has to settle before it releases, and keep going until nothing new appears.** The SDK
    /// reaches a boundary asynchronously — the fetch is issued from the coordinator's own executor
    /// and parks a hop later — so releasing the instant a stimulus is fed finds nothing parked yet,
    /// returns, and leaves the fetch owed forever.
    func settleBoundaries() async {
        var quietRounds = 0
        while quietRounds < 3 {
            try? await ReplayHarness.letAsyncWorkRun()
            guard gate.hasParked else {
                quietRounds += 1
                continue
            }
            quietRounds = 0
            await releaseRemainingBoundaries { try? await ReplayHarness.letAsyncWorkRun() }
        }
    }

    /// How long a round of `letAsyncWorkRun` waits for the SDK's tasks to get going.
    ///
    /// Real time, and the one place the harness spends any. The virtual clock decides *what the
    /// SDK sees*; this decides *how long we wait for Swift to run work we have already started*,
    /// which no amount of virtual time can substitute for. Long enough that a storage read and a
    /// dispatcher hop land on a loaded machine, short enough that a long drive is not dominated by
    /// it. If a scenario ever diverges only under load, this is the number to suspect.
    static let asyncWorkGrace: Duration = .milliseconds(50)

    /// Gives the `Task`s the SDK started a chance to execute.
    ///
    /// Not "run to stillness" — that is what the boundaries are for. Work the SDK starts still
    /// reaches a parked network call and stops there; this only lets it get that far, because Swift
    /// concurrency will not run those tasks otherwise.
    ///
    /// Cancellation is propagated rather than swallowed, for the reason `Settle.swift` gives: a
    /// `try?` here drops the `CancellationError` and every bounded loop built on this spins at full
    /// speed through the SDK instead of unwinding.
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
