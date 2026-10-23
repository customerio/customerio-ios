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
        /// Whether a task the harness tracks waits on this answer, and so counts as parked.
        let holdsTrackedWork: Bool
        let answer: () async -> Void
    }

    private var parked: [Parked] = [] {
        didSet { onParkedCountChanged?(parked.filter(\.holdsTrackedWork).count) }
    }

    /// So the harness can tell work parked here from work still running.
    var onParkedCountChanged: ((Int) -> Void)?
    /// Whether the task parking an answer is tracked work. Unset, every park counts.
    var isTrackedWork: () -> Bool = { true }
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

    /// A past moment answers immediately, which also keeps `advance` from looping. A frozen process
    /// receives nothing: while suspended every answer is held, even an overdue one.
    /// - Parameter holdsTask: false when no task waits on the answer itself: a requested fix, whose
    ///   callers count as parked where they wait.
    func park(at: TimeInterval, what: String, holdsTask: Bool = true, answer: @escaping () async -> Void) async {
        guard isSuspended || at > virtualNow else {
            await answer()
            return
        }
        nextId += 1
        let holdsTrackedWork = holdsTask && isTrackedWork()
        parked.append(Parked(id: nextId, at: at, what: what, holdsTrackedWork: holdsTrackedWork, answer: answer))
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
        // Suspended: drive time still reaches `target`, but nothing is answered into a frozen process.
        while !isSuspended {
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
        // Frozen: nothing wakes the process to receive these, so name them instead of answering.
        guard !isSuspended else {
            abandonedAtEnd = parked.map { "\($0.what) (held: process suspended)" }
            return
        }
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
    /// What `settleBoundaries` may answer now. Counting held answers would spin it to its round limit.
    var hasReleasable: Bool { !isSuspended && !parked.isEmpty }

    // MARK: - Suspension

    /// The OS froze the process: drive time moves, no answer is delivered.
    private(set) var isSuspended = false

    func suspend() {
        isSuspended = true
    }

    /// Answers that came due while frozen arrive now, in recorded order. The clock never rewinds, so
    /// none is dated to its recorded moment; later answers stay parked for `advance`.
    func resume(setClock: (TimeInterval) -> Void, settle: () async -> Void) async {
        isSuspended = false
        await advance(to: virtualNow, setClock: setClock, settle: settle)
    }

    func reset() {
        parked.removeAll()
        nextId = 0
        fetchAnswers.removeAll()
        abandonedAtEnd = []
        virtualNow = 0
        isSuspended = false
    }

    // MARK: - Fallbacks

    /// Non-zero so the call still leaves a window; far below any interval the SDK gates on.
    static let fallbackNetworkSeconds: TimeInterval = 0.250

    private static let maxReleaseRounds = 512
}
