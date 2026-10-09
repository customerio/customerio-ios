@testable import CioInternalCommon
@testable import CioLocationGeofence
import CoreLocation
import Foundation

/// Recorded `CLLocationManager.location` answers. A pulled fix is state, not a stimulus: replaying it
/// as an event would land after the decision that needed it. Indexed by stimulus window, not clock:
/// the clock stands at the stimulus while the SDK works, so its samples are recorded after it.
@MainActor
final class ReplayFixProvider {
    /// `at` only picks the stimulus window; `age` is the part the SDK reasons about.
    struct CachedRead {
        let at: TimeInterval
        /// `nil`: the read found nothing (`prov=none`), a recorded answer rather than a missing one.
        let location: LocationData?
        let accuracy: Double
        let age: TimeInterval
    }

    struct RequestedAnswer {
        let at: TimeInterval
        let fix: CLLocation
    }

    private var stimulusTimes: [TimeInterval] = []
    private var samplesByWindow: [Int: [CachedRead]] = [:]
    private var cursorByWindow: [Int: Int] = [:]
    private var carriedByWindow: [Int: CachedRead] = [:]
    private var requestedAnswers: [CachedRead] = []
    private var requestedProcesses: [Int: Int] = [:]
    private var currentProcess = 0
    private var answerCursor = 0
    private(set) var allowsSyntheticRequestedAnswers = true

    private let epoch: Date
    var now: TimeInterval = 0

    private(set) var pullCount = 0
    private(set) var unansweredWindows: Set<Int> = []

    init(epoch: Date) {
        self.epoch = epoch
    }

    func load(stimuli: [TimeInterval], samples: [CachedRead], carried: [CachedRead] = []) {
        stimulusTimes = stimuli.sorted()
        samplesByWindow = [:]
        cursorByWindow = [:]
        carriedByWindow = [:]
        pullCount = 0
        unansweredWindows = []
        for sample in samples.sorted(by: { $0.at < $1.at }) {
            samplesByWindow[window(at: sample.at), default: []].append(sample)
        }
        for sample in carried.sorted(by: { $0.at < $1.at }) {
            carriedByWindow[window(at: sample.at)] = sample
        }
    }

    /// Timestamp built at read time as `now - age`. Dating from the drive's clock lands after the SDK's
    /// `now`, and the negative age silently disables `BaselineHealDecision`'s gate.
    func nextCachedLocation() -> CLLocation? {
        pullCount += 1
        guard let sample = nextSampleInCurrentWindow(), let location = sample.location else { return nil }
        return CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: location.latitude,
                longitude: location.longitude
            ),
            altitude: 0,
            horizontalAccuracy: sample.accuracy,
            verticalAccuracy: -1,
            timestamp: epoch.addingTimeInterval(now - sample.age)
        )
    }

    /// Imported notes inherit their producer from `process.start` boundaries. Direct synthetic
    /// answers without boundaries belong to the process that reserves them.
    func loadRequestedAnswers(
        _ answers: [CachedRead],
        allowSyntheticFallback: Bool = false,
        processStarts: [TimeInterval]? = nil
    ) {
        requestedAnswers = answers.sorted { $0.at < $1.at }
        answerCursor = 0
        allowsSyntheticRequestedAnswers = allowSyntheticFallback && answers.isEmpty
        requestedProcesses = [:]
        if let processStarts {
            let starts = processStarts.sorted()
            for (index, answer) in requestedAnswers.enumerated() {
                requestedProcesses[index] = starts.lastIndex { $0 <= answer.at } ?? 0
            }
        }
    }

    var requestedAnswerHorizon: TimeInterval? { requestedAnswers.last?.at }

    func beginNextProcess() {
        currentProcess += 1
    }

    /// Reserves an OS reply without delivering it. Arrival and measurement time are separate:
    /// CoreLocation's timestamp is the recorded arrival minus the age logged at that arrival.
    func reserveRequestedAnswer() -> RequestedAnswer? {
        while answerCursor < requestedAnswers.count {
            let process = requestedProcesses[answerCursor]
            if let process, process > currentProcess { return nil }
            if requestedAnswers[answerCursor].at < now || process.map({ $0 < currentProcess }) == true {
                answerCursor += 1
            } else {
                break
            }
        }
        guard answerCursor < requestedAnswers.count,
              let location = requestedAnswers[answerCursor].location
        else { return nil }
        let answer = requestedAnswers[answerCursor]
        answerCursor += 1
        let fix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
            altitude: 0,
            horizontalAccuracy: answer.accuracy,
            verticalAccuracy: -1,
            timestamp: epoch.addingTimeInterval(answer.at - answer.age)
        )
        return RequestedAnswer(at: answer.at, fix: fix)
    }

    /// Doesn't consume a cache read or count as a pull: it would eat the window's only sample.
    func currentPosition() -> CLLocation? {
        let index = window(at: now)
        guard let read = carriedByWindow[index] ?? samplesByWindow[index]?.first,
              let location = read.location else { return nil }
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
            altitude: 0,
            horizontalAccuracy: read.accuracy,
            verticalAccuracy: -1,
            // A repeated read must not refresh the recorded fix's timestamp. A read logged just
            // after its stimulus is clamped to that stimulus rather than dated in the future.
            timestamp: epoch.addingTimeInterval(min(read.at, now) - read.age)
        )
    }

    func pullAccounting() -> String? {
        // Android captures record no cache reads, so there is nothing to account against.
        guard !samplesByWindow.isEmpty else { return nil }
        guard !unansweredWindows.isEmpty else { return nil }
        let stamps = unansweredWindows.sorted().map { index -> String in
            stimulusTimes.indices.contains(index)
                ? String(format: "@%.3f", stimulusTimes[index])
                : "@start"
        }
        return "\(pullCount) cached-fix reads; \(unansweredWindows.count) stimulus window(s) "
            + "had a read but no recorded position (\(stamps.joined(separator: ", "))) — "
            + "the drive captured no position at that point in the run"
    }

    // MARK: - Windows

    private func window(at time: TimeInterval) -> Int {
        stimulusTimes.lastIndex { $0 <= time } ?? 0
    }

    private func nextSampleInCurrentWindow() -> CachedRead? {
        let index = window(at: now)
        guard let samples = samplesByWindow[index], !samples.isEmpty else {
            // The read's `location.fix` can land a tick before its callback, under the previous
            // stimulus; the callback's carried read covers that.
            if let carried = carriedByWindow[index] { return carried }
            unansweredWindows.insert(index)
            return nil
        }
        let cursor = min(cursorByWindow[index, default: 0], samples.count - 1)
        cursorByWindow[index] = cursor + 1
        return samples[cursor]
    }
}
