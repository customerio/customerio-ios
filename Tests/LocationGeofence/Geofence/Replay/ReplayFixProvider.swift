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

    private var stimulusTimes: [TimeInterval] = []
    private var samplesByWindow: [Int: [CachedRead]] = [:]
    private var cursorByWindow: [Int: Int] = [:]
    private var carriedByWindow: [Int: CachedRead] = [:]
    private var requestedAnswers: [CachedRead] = []
    private var answerCursor = 0

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

    func loadRequestedAnswers(_ answers: [CachedRead]) {
        requestedAnswers = answers.sorted { $0.at < $1.at }
        answerCursor = 0
    }

    /// Looked up ahead, not delivered at its recorded time: the replay's timeout fires immediately,
    /// while on the device the answer arrived later and was what the pass decided from.
    func requestedAnswer(within timeout: TimeInterval) -> CLLocation? {
        while answerCursor < requestedAnswers.count, requestedAnswers[answerCursor].at < now {
            answerCursor += 1
        }
        guard answerCursor < requestedAnswers.count,
              requestedAnswers[answerCursor].at <= now + timeout,
              let location = requestedAnswers[answerCursor].location
        else { return nil }
        let answer = requestedAnswers[answerCursor]
        answerCursor += 1
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
            altitude: 0,
            horizontalAccuracy: answer.accuracy,
            verticalAccuracy: -1,
            timestamp: epoch.addingTimeInterval(now - answer.age)
        )
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
            timestamp: epoch.addingTimeInterval(now - read.age)
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
