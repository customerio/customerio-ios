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
        await gate.advance(to: at, setClock: { [weak self] moment in self?.setClock(moment) }, settle: settle)
    }

    func releaseRemainingBoundaries(settle: () async throws -> Void) async rethrows {
        try await gate.releaseAll(setClock: { [weak self] moment in self?.setClock(moment) }, settle: settle)
    }

    func advance(to at: TimeInterval) async {
        // `try?`: unwinding mid-advance would leave the clock half-moved.
        await advance(to: at) { try? await ReplayHarness.letAsyncWorkRun() }
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
            guard gate.hasParked else {
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
    }

    var now: Date { clock.givenNow }
}
