@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation

/// Holds work the OS or the network had not finished yet, and lets it finish when the drive says it did.
///
/// The doubles this harness substitutes were faithful in *value* and instantaneous in *time*. The
/// real ones were neither, and the gap matters: CoreLocation delivers every crossing twice about
/// 10 ms apart, and on the 2026-09-10 iPhone drive the second copy arrived while a re-registration's
/// baseline write was still in flight:
///
/// ```
/// when  7581.379  os.callback cio_movement_trigger exit    ← first copy
/// when  7581.391  os.callback cio_movement_trigger exit    ← duplicate, 12 ms later
/// then  7581.393  os.callback.dropped why=no_state_change  ← duplicate finds the old baseline
/// note  7581.395  movement.exit tier=localRerank
/// then  7581.399  registration.applied                     ← reseed lands, 8 ms after the duplicate
/// ```
///
/// A harness that lets the write land before the next stimulus reverses that: the duplicate finds
/// the *new* baseline, reads as a state change, and the drive diverges from there. Every input that
/// arrives while the SDK is mid-reaction is unreachable that way, and on a geofencing SDK that is
/// most of the interesting behaviour.
///
/// **Nothing sleeps.** Release is driven by the scenario's own timestamps, so the outcome depends on
/// the recording rather than on how fast the machine runs — which is the difference between this
/// and replaying the recorded gaps in real time.
@MainActor
final class ReplayBoundaryGate {
    /// A boundary whose answer is owed.
    ///
    /// Carries an `id` because two boundaries can legitimately share a moment and a name — a drive
    /// with two registrations at the same recorded `registration.applied` would otherwise have both
    /// entries removed and only one of them answered, silently losing a baseline write.
    private struct Parked {
        let id: Int
        let at: TimeInterval
        let what: String
        let answer: () async -> Void
    }

    private var parked: [Parked] = []
    private var nextId = 0

    /// Boundaries the scenario ended while still waiting on. Diagnostic, not a failure: a capture
    /// can legitimately stop mid-sync.
    private(set) var abandonedAtEnd: [String] = []

    // MARK: - Recorded answer times

    /// When the network answered each fetch, in order — the `at` of every `fixture.api.fetch`.
    ///
    /// That timestamp is stamped when the response *arrived*, which is why a fixture cannot be
    /// placed on the timeline as a record: it always sits one round trip later in the capture than
    /// the fetch that asked for it, and installing it there starves the fetch. As a *release* time
    /// it is exactly right, and the 768 ms the iPhone drive spent waiting for its first response
    /// becomes 768 ms of virtual time in which other inputs can land.
    private var fetchAnswers: [TimeInterval] = []

    /// **There is no registration answer list, deliberately.** An earlier cut released the
    /// registration boundary at the `at` of each recorded `registration.applied`, which was wrong
    /// twice over: that record is a `then`, so the input schedule was being derived from the answer
    /// sheet, and it is stamped when the *coordinator finishes issuing* the registration, not when
    /// CoreLocation finished applying it. The capture measured the OS round trip and
    /// `capture2scenario.py` strips it as volatile (`ms`); until it stops, the honest position is
    /// that a replay does not know how long a condition add took, so the OS answers immediately
    /// rather than on a fabricated schedule.
    func load(fetchAnswers: [TimeInterval]) {
        self.fetchAnswers = fetchAnswers.sorted()
    }

    /// The next recorded answer at or after `now`, or `now` plus a fallback when none is left.
    ///
    /// Answers already behind the clock are discarded rather than used: they belong to a call this
    /// replay has already made, and honouring one would return in the past.
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
        nextId += 1
        parked.append(Parked(id: nextId, at: at, what: what, answer: answer))
    }

    /// Runs the clock forward to `target`, answering each boundary **at its own moment** on the way.
    ///
    /// Advancing straight to the target and releasing everything there would date all the work a
    /// boundary unblocks to whenever the next stimulus happened to be — 768 ms of the iPhone's
    /// reaction squeezed into the instant of the input it was supposed to precede. So each release
    /// steps the clock to the moment that boundary actually answered, and `settle` runs whatever it
    /// made runnable before the next one is considered.
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
            setClock(next.at)
            await next.answer()
            await settle()
        }
        setClock(target)
    }

    /// Ends the drive: answers whatever is still outstanding so the run finishes rather than stalls.
    func releaseAll(setClock: (TimeInterval) -> Void, settle: () async -> Void) async {
        var abandoned: [String] = []
        var guardCount = 0
        while let next = parked.min(by: { ($0.at, $0.id) < ($1.at, $1.id) }) {
            guard guardCount < Self.maxReleaseRounds else { break }
            guardCount += 1
            parked.removeAll { $0.id == next.id }
            abandoned.append(next.what)
            setClock(next.at)
            await next.answer()
            await settle()
        }
        abandonedAtEnd = abandoned
    }

    /// Whether anything is owed. The SDK reaches its boundaries asynchronously, so a caller that
    /// wants to answer them all has to let it get there first — see `ReplayHarness.settleBoundaries`.
    var hasParked: Bool { !parked.isEmpty }

    /// Between scenarios: a boundary parked by the previous drive would answer inside the next.
    func reset() {
        parked.removeAll()
        nextId = 0
        fetchAnswers.removeAll()
        abandonedAtEnd = []
    }

    // MARK: - Fallbacks

    /// Used only when a fetch has no recorded answer left to match — a replay that reached out
    /// more often than the drive did. Deliberately non-zero so such a call still leaves a window
    /// rather than closing instantly, and far below any interval the SDK gates on.
    static let fallbackNetworkSeconds: TimeInterval = 0.250

    private static let maxReleaseRounds = 512
}
