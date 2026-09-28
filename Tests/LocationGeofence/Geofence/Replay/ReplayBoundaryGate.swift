@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation

/// Holds work the network had not finished yet, and lets it finish when the drive says it did.
///
/// Instantaneous doubles reorder a drive. CoreLocation can deliver a crossing twice, with the
/// second copy arriving while a re-registration is still in flight, so it finds the old baseline
/// and is dropped as no change. Letting the re-registration land before the next stimulus
/// reverses that: the duplicate finds the *new* baseline, reads as a state change, and the drive
/// diverges. Only fetches park today; see
/// `load(fetchAnswers:)`.
///
/// **Nothing sleeps.** Release is driven by the scenario's timestamps, so the outcome depends on
/// the recording rather than on machine speed.
@MainActor
final class ReplayBoundaryGate {
    /// A boundary whose answer is owed.
    ///
    /// Carries an `id` because two boundaries can share a moment and a name; removing by value
    /// would drop both and answer one.
    private struct Parked {
        let id: Int
        let at: TimeInterval
        let what: String
        let answer: () async -> Void
    }

    private var parked: [Parked] = []
    private var nextId = 0

    /// The moment this gate last moved the clock to, so `park` can tell a future boundary from a
    /// past one. Clamped like `setClock`.
    private var virtualNow: TimeInterval = 0

    /// Boundaries the scenario ended while still waiting on. Diagnostic, not a failure: a capture
    /// can legitimately stop mid-sync.
    private(set) var abandonedAtEnd: [String] = []

    // MARK: - Recorded answer times

    /// When the network answered each fetch, in order — the `at` of every `fixture.api.fetch`.
    ///
    /// Stamped when the response *arrived*, so it is wrong as a fixture's install time but exactly
    /// right as a release time: the round trip becomes virtual time in which other inputs can land.
    private var fetchAnswers: [TimeInterval] = []

    /// Fetches only. `registration.applied` is a `then` stamped when the coordinator finishes
    /// issuing, not when CoreLocation applied it, and the transform strips the OS round trip
    /// (`ms`), so condition adds answer immediately rather than on a fabricated schedule.
    func load(fetchAnswers: [TimeInterval]) {
        self.fetchAnswers = fetchAnswers.sorted()
    }

    /// The next recorded answer at or after `now`, or `now` plus a fallback when none is left.
    ///
    /// Answers already behind the clock are discarded: honouring one would return in the past.
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

    /// Owes `answer` until virtual time reaches `at`.
    ///
    /// A boundary whose moment has already passed answers immediately rather than parking, which is
    /// also what keeps `advance` from looping: work resumed inside it can only park in the future.
    func park(at: TimeInterval, what: String, answer: @escaping () async -> Void) async {
        // Unreachable from `fetchAnswerTime`, which never looks back; the round limit in `advance`
        // is a backstop, not the reason it terminates.
        guard at > virtualNow else {
            await answer()
            return
        }
        nextId += 1
        parked.append(Parked(id: nextId, at: at, what: what, answer: answer))
    }

    /// Moves the clock and remembers where it went, clamped identically to `setClock` so `park`
    /// never compares against a moment the clock never took.
    private func moveClock(to moment: TimeInterval, _ setClock: (TimeInterval) -> Void) {
        virtualNow = max(moment, virtualNow)
        setClock(moment)
    }

    /// Runs the clock forward to `target`, answering each boundary **at its own moment** on the way.
    ///
    /// Releasing everything at the target would date the unblocked work to the next stimulus. So
    /// each release steps the clock to that boundary's own moment, and `settle` runs what it made
    /// runnable before the next is considered.
    func advance(
        to target: TimeInterval,
        setClock: (TimeInterval) -> Void,
        settle: () async -> Void
    ) async {
        var guardCount = 0
        while let next = parked.filter({ $0.at <= target }).min(by: { ($0.at, $0.id) < ($1.at, $1.id) }) {
            guard guardCount < Self.maxReleaseRounds else {
                fatalError("replay: boundary releases did not settle after \(Self.maxReleaseRounds) rounds (\(next.what))")
            }
            guardCount += 1
            parked.removeAll { $0.id == next.id }
            // Never backwards: two boundaries can answer at the same recorded moment, and a
            // recorded time can sit fractionally behind where the clock already stands.
            moveClock(to: next.at, setClock)
            await next.answer()
            await settle()
        }
        moveClock(to: target, setClock)
    }

    /// Ends the drive: answers whatever is still outstanding so the run finishes rather than stalls.
    func releaseAll(setClock: (TimeInterval) -> Void, settle: () async throws -> Void) async rethrows {
        var abandoned: [String] = []
        var guardCount = 0
        while let next = parked.min(by: { ($0.at, $0.id) < ($1.at, $1.id) }) {
            guard guardCount < Self.maxReleaseRounds else { break }
            guardCount += 1
            parked.removeAll { $0.id == next.id }
            abandoned.append(next.what)
            moveClock(to: next.at, setClock)
            await next.answer()
            try await settle()
        }
        // Includes what the round limit cut short, so a break does not read as a clean end.
        abandonedAtEnd = abandoned + parked.map(\.what)
    }

    /// Whether anything is owed. See `ReplayHarness.settleBoundaries`.
    var hasParked: Bool { !parked.isEmpty }

    /// Between scenarios: a boundary parked by the previous drive would answer inside the next.
    func reset() {
        parked.removeAll()
        nextId = 0
        fetchAnswers.removeAll()
        abandonedAtEnd = []
        // Left standing, the next drive's early boundaries would read as already past.
        virtualNow = 0
    }

    // MARK: - Fallbacks

    /// Used only when a fetch has no recorded answer left. Non-zero so the call still leaves a
    /// window, and far below any interval the SDK gates on.
    static let fallbackNetworkSeconds: TimeInterval = 0.250

    private static let maxReleaseRounds = 512
}
