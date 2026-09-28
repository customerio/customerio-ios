@testable import CioInternalCommon
@testable import CioLocationGeofence
import CoreLocation
import Foundation

/// What `CLLocationManager.location` answered, as the drive recorded it.
///
/// The answer book behind `FakeLocationAuthority`. The SDK's own `FixSelection` code decides what
/// an answer means (cache vs resolver, provenance, logging); nothing here labels or picks a fix.
///
/// **A pulled fix is state, not an event.** The log line is written at the *read*, which happens
/// inside work an earlier stimulus started (e.g. the registration ledger reading mid-sync).
/// Replaying those records as stimuli would deliver the value after the decision that needed it.
///
/// **Indexed by stimulus window, not by clock.** Virtual time only advances at stimulus
/// boundaries, so while the SDK works on the stimulus at `t` the clock reads `t`, and every sample
/// that work produced was recorded *after* `t`. "Newest sample at or before the clock" would
/// answer from the previous phase of the drive. A window the SDK reads in but the drive recorded
/// nothing for is reported, not approximated.
///
/// **Not asserted:** how many times, in what order, or from where the SDK reads within a window —
/// samples are served in recorded order and the last repeats. What is caught is the SDK reading
/// in a phase of the drive where it did not read at all.
@MainActor
final class ReplayFixProvider {
    /// One recorded read of the OS cache.
    ///
    /// `at` is when the SDK looked, and only picks the stimulus window. `age` is how stale the
    /// position already was, and is the only part the SDK reasons about.
    struct CachedRead {
        let at: TimeInterval
        /// `nil` is a read that found nothing (`prov=none`): a recorded answer, not a missing record.
        let location: LocationData?
        let accuracy: Double
        let age: TimeInterval
    }

    /// The stimuli that drive work, in order. See `ReplayRunner.isStimulus`.
    private var stimulusTimes: [TimeInterval] = []
    /// Recorded answers, grouped by the window they were recorded in.
    private var samplesByWindow: [Int: [CachedRead]] = [:]
    /// How far through each window's samples the SDK has read.
    private var cursorByWindow: [Int: Int] = [:]
    /// The read an `os.callback` record carries in its own fields, by window. Last resort.
    private var carriedByWindow: [Int: CachedRead] = [:]
    /// The fixes the drive's own fresh-fix requests were answered with (`fix.received`
    /// `prov=movement_resolver`), in recorded order, and how far through them requests have got.
    private var requestedAnswers: [CachedRead] = []
    private var answerCursor = 0

    /// `t0`, so an age can be turned into a timestamp on the replay's own timeline.
    private let epoch: Date
    /// Virtual seconds since `t0`, driven by the harness clock.
    var now: TimeInterval = 0

    private(set) var pullCount = 0
    /// Windows the SDK read in that the drive recorded no position for.
    private(set) var unansweredWindows: Set<Int> = []

    init(epoch: Date) {
        self.epoch = epoch
    }

    /// Loads the drive's recorded answers, before the first stimulus runs.
    ///
    /// - Parameters:
    ///   - stimuli: the `at` of every stimulus that drives work; see `ReplayRunner.isStimulus`.
    ///   - samples: every recorded read, in any order.
    ///   - carried: the read each OS callback record carries in its own fields. See `carriedByWindow`.
    func load(stimuli: [TimeInterval], samples: [CachedRead], carried: [CachedRead] = []) {
        stimulusTimes = stimuli.sorted()
        samplesByWindow = [:]
        cursorByWindow = [:]
        carriedByWindow = [:]
        // Accounting belongs to the drive being loaded, not a previous `load`.
        pullCount = 0
        unansweredWindows = []
        for sample in samples.sorted(by: { $0.at < $1.at }) {
            samplesByWindow[window(at: sample.at), default: []].append(sample)
        }
        for sample in carried.sorted(by: { $0.at < $1.at }) {
            carriedByWindow[window(at: sample.at)] = sample
        }
    }

    /// One read of the OS cache, answered from the drive.
    ///
    /// **The timestamp is built at the moment of the read, never at load time.** Virtual time
    /// stands still while the SDK reacts, so dating a fix from the drive's clock would put it after
    /// the SDK's `now`. The negative age then fails `BaselineHealDecision`'s `fixAge >= 0` guard,
    /// silently disabling the contradiction gate and the heal. `now - age` gives the SDK exactly
    /// the staleness the phone measured.
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
            // Absent from every capture, and the SDK reads it only to report it.
            verticalAccuracy: -1,
            timestamp: epoch.addingTimeInterval(now - sample.age)
        )
    }

    /// Loads the answers the drive's fresh-fix requests received. Captures whose `fix.received`
    /// lacks accuracy load none, and every request falls back to `currentPosition()`.
    func loadRequestedAnswers(_ answers: [CachedRead]) {
        requestedAnswers = answers.sorted { $0.at < $1.at }
        answerCursor = 0
    }

    /// The fix the drive received for a request made now: the first recorded answer inside the
    /// request's timeout. Consumed, so one answer serves one request.
    ///
    /// Looked up ahead rather than delivered at its recorded time, because the replay's request
    /// timeout fires immediately while in the car the answer arrived seconds later and was what the
    /// pass decided from. Answers the replay has already moved past are skipped, never handed to a
    /// later request.
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

    /// The drive's position right now, WITHOUT consuming a cache read.
    ///
    /// A fresh-fix request is the OS answering from current GPS, not a cache read, so it must not
    /// advance the cursor or count as a pull (it would eat the window's only sample). Prefers the
    /// callback's carried position, then the window's first `location.fix` sample.
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

    /// Whether every read the SDK made landed in a window the drive actually recorded.
    func pullAccounting() -> String? {
        // Only a drive that records cache reads can be accounted against them. An Android capture
        // has none (every `location.fix` there is an arrival), so its uncovered windows are a gap in
        // what that platform records, not a replay that wandered off the drive.
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

    /// The stimulus a moment belongs to. Reads before the first stimulus share window 0 with it.
    private func window(at time: TimeInterval) -> Int {
        stimulusTimes.lastIndex { $0 <= time } ?? 0
    }

    private func nextSampleInCurrentWindow() -> CachedRead? {
        let index = window(at: now)
        guard let samples = samplesByWindow[index], !samples.isEmpty else {
            // `logReceivedCallback` reads and *then* logs, so the read's `location.fix` line can land
            // a millisecond tick before the callback and be filed under the previous stimulus. The
            // callback's carried read covers that. Last resort only, so a window with genuinely no
            // recorded read is still reported.
            if let carried = carriedByWindow[index] { return carried }
            unansweredWindows.insert(index)
            return nil
        }
        // Served in recorded order; the last repeats once exhausted.
        let cursor = min(cursorByWindow[index, default: 0], samples.count - 1)
        cursorByWindow[index] = cursor + 1
        return samples[cursor]
    }
}
