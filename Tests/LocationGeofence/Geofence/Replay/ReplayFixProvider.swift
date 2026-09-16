@testable import CioInternalCommon
@testable import CioLocationGeofence
import CoreLocation
import Foundation

/// What `CLLocationManager.location` answered, as the drive recorded it.
///
/// This is one half of `FakeLocationAuthority`: the authority is the seam, this is the answer
/// book behind it. The SDK's own `+Fixes` code then decides what the answer means — whether the
/// cache or the resolver's fix is fresher, what provenance to stamp on it, and whether to log it.
/// Nothing here labels a fix or picks between fixes; a replay that did either would be deciding
/// something the SDK is supposed to decide.
///
/// **A pulled fix is state, not an event.** `CLLocationManager.location` is a value the OS keeps and
/// the SDK reads whenever it needs one. The log line is written at the moment of the *read*, and
/// the read happens inside work an earlier stimulus started — the registration ledger reads the
/// cache in the middle of a sync that a bus fix kicked off a second earlier. Replaying those records
/// as stimuli in sequence would deliver the value after the decision that needed it.
///
/// **Indexed by stimulus window, not by clock.** The obvious rule — "the newest sample at or before
/// the clock" — is off by one window and quietly wrong. Virtual time only advances at stimulus
/// boundaries, so while the SDK does the work triggered by the stimulus at `t`, the clock still
/// reads `t`, and every sample that work produced was recorded *after* `t`. Looking backwards
/// therefore never finds the current window's own samples; it reaches into the previous phase of
/// the drive. On the 2026-09-09 iPhone drive that answered a registration-time read with a position
/// recorded thirty minutes and two kilometres later, and the SDK confidently decided it was inside
/// the wrong fence.
///
/// So samples are grouped by the stimulus they were recorded under, and a read is answered from the
/// window it happens in. A window the SDK reads in but the drive recorded nothing for is not
/// approximated — it is reported, because that is the replay having no answer rather than a
/// different one.
///
/// **What this deliberately does not assert.** Not how many times the SDK reads, not in what order,
/// and not from which call site. Within a window the samples are served in recorded order and the
/// last one repeats once exhausted, so adding, removing or reordering reads inside a window changes
/// nothing. Those are implementation. What it does catch is the SDK reading during a phase of the
/// drive where it previously did not read at all — a change in behaviour, not a refactor.
@MainActor
final class ReplayFixProvider {
    /// One recorded read of the OS cache.
    ///
    /// **`at` places it, `age` describes it, and the two must not be mixed.** `at` is the drive's
    /// clock saying *when the SDK looked*; it decides which stimulus window the answer belongs to
    /// and nothing else. `age` is *how stale the position already was* when it was looked at, and
    /// it is the only part the SDK ever reasons about.
    struct CachedRead {
        let at: TimeInterval
        /// `nil` is a read that found nothing — the capture writes it `prov=none`, and it is a
        /// recorded answer rather than a missing record.
        let location: LocationData?
        let accuracy: Double
        let age: TimeInterval
    }

    /// The stimuli that drive work, in order. Pull records are excluded: the runner treats them as
    /// no-ops, and letting them define boundaries would fragment the windows they sit inside.
    private var stimulusTimes: [TimeInterval] = []
    /// Recorded answers, grouped by the window they were recorded in.
    private var samplesByWindow: [Int: [CachedRead]] = [:]
    /// How far through each window's samples the SDK has read.
    private var cursorByWindow: [Int: Int] = [:]
    /// The read an `os.callback` record carries in its own fields, by window. Last resort.
    private var carriedByWindow: [Int: CachedRead] = [:]

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
    ///   - stimuli: the `at` of every stimulus that drives work, pull records excluded.
    ///   - samples: every recorded read, in any order.
    ///   - carried: the read each OS callback record carries in its own fields. See `carriedByWindow`.
    func load(stimuli: [TimeInterval], samples: [CachedRead], carried: [CachedRead] = []) {
        stimulusTimes = stimuli.sorted()
        samplesByWindow = [:]
        cursorByWindow = [:]
        carriedByWindow = [:]
        for sample in samples.sorted(by: { $0.at < $1.at }) {
            samplesByWindow[window(at: sample.at), default: []].append(sample)
        }
        for sample in carried.sorted(by: { $0.at < $1.at }) {
            carriedByWindow[window(at: sample.at)] = sample
        }
    }

    /// One read of the OS cache, answered from the drive.
    ///
    /// A `CLLocation` rather than a `GeofenceFix`, because that is what the OS hands over and the
    /// SDK's own `selectFix()` is what turns one into the other.
    ///
    /// **The timestamp is built here, at the moment of the read, and never at load time.** The
    /// recording and the replay run on different clocks: virtual time only moves at a stimulus or a
    /// boundary release, so it stands still while the SDK reacts, while the drive went on recording.
    /// Dating a fix from the drive's clock therefore hands the SDK a position born *after* its own
    /// `now` — and with `age=0` on nearly every recorded read, that is not an edge case but the
    /// normal one. The SDK measures staleness as `now - timestamp`, gets a negative number, and
    /// every rule that reads it (`BaselineHealDecision`'s `fixAge >= 0`, and so the contradiction
    /// gate and the baseline heal above it) fails open without saying so. Applying the recorded age
    /// against the clock at the instant of the read gives the SDK exactly the staleness the phone
    /// measured, whatever the clock is quantised to.
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

    /// Whether every read the SDK made landed in a window the drive actually recorded.
    func pullAccounting() -> String? {
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
            // The callback's own line carries the read the SDK made to write it, so a callback
            // window is never legitimately empty — `logReceivedCallback` calls `bestKnownFixDetail`
            // and *then* logs, which is exactly why the two can land on either side of a
            // millisecond in a capture that stamps to the millisecond. On the 2026-09-12 iPhone
            // drive two of fifteen callbacks in one relaunch storm straddled a tick that way, and
            // the read the transform filed under the previous stimulus left theirs with nothing.
            //
            // Last resort, never a supplement: the recorded `location.fix` lines stay the answer
            // wherever the window has them, so a window the SDK reads in and the drive genuinely
            // recorded nothing for is still reported.
            if let carried = carriedByWindow[index] { return carried }
            unansweredWindows.insert(index)
            return nil
        }
        // Served in recorded order; the last repeats once exhausted, so the number of reads the SDK
        // makes is not an assertion.
        let cursor = min(cursorByWindow[index, default: 0], samples.count - 1)
        cursorByWindow[index] = cursor + 1
        return samples[cursor]
    }
}
