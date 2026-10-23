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
        await advance(to: at) { await self.awaitIdle() }
    }

    /// Without this bound a park chain would hang, not fail.
    static let maxSettleRounds = 256

    /// Answers every parked boundary in time order, idling after each, until none is left. Idles
    /// first: the fetch parks a hop after the coordinator issues it.
    func settleBoundaries() async {
        for _ in 0 ..< Self.maxSettleRounds {
            await awaitIdle()
            guard gate.hasParked else { return }
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
    }

    var now: Date { clock.givenNow }
}
