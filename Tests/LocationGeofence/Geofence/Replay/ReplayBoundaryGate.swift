@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation

/// Parks fetches until their recorded answer time. Answering instantly lets a re-registration land
/// before a duplicate crossing, which then reads as a change. Release follows scenario time, never
/// sleeps.
@MainActor
final class ReplayBoundaryGate {
    /// `id`: two boundaries can share a moment and name; removing by value would drop both.
    private struct Parked {
        let id: Int
        let at: TimeInterval
        let what: String
        let answer: () async -> Void
    }

    private var parked: [Parked] = []
    private var nextId = 0

    private var virtualNow: TimeInterval = 0

    /// Diagnostic, not a failure: a capture can legitimately stop mid-sync.
    private(set) var abandonedAtEnd: [String] = []

    // MARK: - Recorded answer times

    /// Stamped on arrival: wrong as a fixture's install time, right as a release time.
    private var fetchAnswers: [TimeInterval] = []

    /// Fetches only: `registration.applied` is stamped when issuing ends, not when the OS applied it.
    func load(fetchAnswers: [TimeInterval]) {
        self.fetchAnswers = fetchAnswers.sorted()
    }

    private func nextAnswer(_ answers: inout [TimeInterval], after now: TimeInterval, fallback: TimeInterval) -> TimeInterval {
        while let first = answers.first, first < now {
            answers.removeFirst()
        }
        guard let next = answers.first else { return now + fallback }
        answers.removeFirst()
        return next
    }

    func fetchAnswerTime(after now: TimeInterval) -> TimeInterval {
        nextAnswer(&fetchAnswers, after: now, fallback: Self.fallbackNetworkSeconds)
    }

    // MARK: - Parking

    /// A past moment answers immediately, which also keeps `advance` from looping.
    func park(at: TimeInterval, what: String, answer: @escaping () async -> Void) async {
        guard at > virtualNow else {
            await answer()
            return
        }
        nextId += 1
        parked.append(Parked(id: nextId, at: at, what: what, answer: answer))
    }

    /// Clamped like `setClock`, so `park` never compares against a moment the clock never took.
    private func moveClock(to moment: TimeInterval, _ setClock: (TimeInterval) -> Void) {
        virtualNow = max(moment, virtualNow)
        setClock(moment)
    }

    /// Answers each boundary at its own moment, not at `target`, so unblocked work isn't dated to the
    /// next stimulus.
    func advance(
        to target: TimeInterval,
        setClock: (TimeInterval) -> Void,
        nextWakeup: () -> TimeInterval? = { nil },
        settle: () async -> Void
    ) async {
        var guardCount = 0
        while true {
            let next = parked.min(by: { ($0.at, $0.id) < ($1.at, $1.id) })
            guard let moment = [next?.at, nextWakeup()].compactMap({ $0 }).filter({ $0 <= target }).min() else { break }
            guard guardCount < Self.maxReleaseRounds else {
                fatalError("replay: releases did not settle after \(Self.maxReleaseRounds) rounds (boundary=\(next?.what ?? "none"), deadline=\(String(describing: nextWakeup())))")
            }
            guardCount += 1
            moveClock(to: moment, setClock)
            if let next, next.at <= virtualNow {
                parked.removeAll { $0.id == next.id }
                await next.answer()
            }
            await settle()
        }
        moveClock(to: target, setClock)
    }

    func releaseAll(
        setClock: (TimeInterval) -> Void,
        nextWakeup: () -> TimeInterval? = { nil },
        settle: () async throws -> Void
    ) async rethrows {
        var abandoned: [String] = []
        var guardCount = 0
        while let next = parked.min(by: { ($0.at, $0.id) < ($1.at, $1.id) }) {
            guard guardCount < Self.maxReleaseRounds else { break }
            guardCount += 1
            moveClock(to: min(next.at, nextWakeup() ?? next.at), setClock)
            if next.at <= virtualNow {
                parked.removeAll { $0.id == next.id }
                abandoned.append(next.what)
                await next.answer()
            }
            try await settle()
        }
        // Includes what the round limit cut short.
        abandonedAtEnd = abandoned + parked.map(\.what)
    }

    var hasParked: Bool { !parked.isEmpty }

    func reset() {
        parked.removeAll()
        nextId = 0
        fetchAnswers.removeAll()
        abandonedAtEnd = []
        virtualNow = 0
    }

    // MARK: - Fallbacks

    /// Non-zero so the call still leaves a window; far below any interval the SDK gates on.
    static let fallbackNetworkSeconds: TimeInterval = 0.250

    private static let maxReleaseRounds = 512
}
