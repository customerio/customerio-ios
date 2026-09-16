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
        await advance(to: at) { await ReplayHarness.letAsyncWorkRun() }
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
            await ReplayHarness.letAsyncWorkRun()
            guard gate.hasParked else {
                quietRounds += 1
                continue
            }
            quietRounds = 0
            await releaseRemainingBoundaries { await ReplayHarness.letAsyncWorkRun() }
        }
    }

    /// Gives the `Task`s the SDK started a chance to execute.
    ///
    /// Not "run to stillness" — that is what the boundaries are for. Work the SDK starts still
    /// reaches a parked network call and stops there; this only lets it get that far, because Swift
    /// concurrency will not run those tasks otherwise.
    static func letAsyncWorkRun() async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50000000)
    }

    /// Virtual time, in the one place that writes it.
    private func setClock(_ at: TimeInterval) {
        let moment = max(at, clock.givenNow.timeIntervalSince(epoch))
        clock.givenNow = epoch.addingTimeInterval(moment)
        fixes.now = moment
    }

    var now: Date { clock.givenNow }
}
