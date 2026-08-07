import CoreGraphics
import Foundation

/// Outcome of inspecting a height reported by the message renderer for a modal message.
enum ModalSizeVerdict: Equatable {
    /// Height looks sane; apply it as usual.
    case apply

    /// Height has stayed collapsed for long enough that the message can never become visible. The
    /// modal is still on screen blocking touches, so the caller is expected to fail the message
    /// rather than keep waiting.
    case degenerate

    /// Reported height is growing by a constant amount per report, which means the message sizes
    /// itself from the WebView height that the SDK derives from it. The height is still applied, but
    /// the caller should surface the cause once.
    case viewportDependent(delta: CGFloat)
}

/// Detects message HTML whose height cannot be resolved by the SDK's content-sizing contract.
///
/// The renderer reports the message's content height and the SDK sizes the WebView to it. When the
/// message CSS instead derives its own height from the viewport (for example `height: 100vh` or
/// `height: 100%` on `html`/`body`) the two are mutually recursive and there is no useful fixed
/// point:
///
/// - reported == container: every value is a fixed point, including zero. The WebView starts at
///   zero, so the message stays collapsed forever behind a full screen, touch blocking overlay.
/// - reported == container + constant: the height grows by that constant on every report until the
///   container clamps it.
///
/// Deliberately free of UIKit so the decision logic can be unit tested directly. Used only for
/// modal messages: inline messages legitimately report a zero height to collapse themselves.
///
/// Mirrors `ModalSizePolicy` on Android; keep the two in step.
class ModalSizePolicy {
    /// Heights at or below this are treated as collapsed. No message can render usable content in
    /// this space, and it covers the values seen in the field: zero, and the few points left by a
    /// collapsed default body margin.
    static let degenerateMaxPoints: CGFloat = 20

    /// Reports needed before a collapsed verdict is possible.
    static let sampleCount: Int = 4

    /// How long the collapsed reports must span. The renderer polls about once per second, so this
    /// clears a burst of reports triggered by layout without waiting much beyond the poll.
    static let degenerateMinElapsed: TimeInterval = 2.5

    /// Growth deltas are compared with a small tolerance because reported heights are rounded from
    /// CSS pixels.
    private static let deltaTolerance: CGFloat = 0.5

    /// At least two heights are needed to compute a delta at all.
    private static let minSamplesForGrowth: Int = 2

    let degenerateMaxPoints: CGFloat
    let sampleCount: Int
    let degenerateMinElapsed: TimeInterval

    private let now: () -> TimeInterval
    private var samples: [Sample] = []

    /// Heights reported before the message is displayed are not evaluated: the WebView may still be
    /// unlaid out and legitimately measure zero.
    private var isArmed = false
    private var hasReportedDegenerate = false
    private var hasReportedViewportDependent = false

    init(
        degenerateMaxPoints: CGFloat = ModalSizePolicy.degenerateMaxPoints,
        sampleCount: Int = ModalSizePolicy.sampleCount,
        degenerateMinElapsed: TimeInterval = ModalSizePolicy.degenerateMinElapsed,
        now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }
    ) {
        self.degenerateMaxPoints = degenerateMaxPoints
        self.sampleCount = sampleCount
        self.degenerateMinElapsed = degenerateMinElapsed
        self.now = now
    }

    /// Starts evaluating reported heights. Idempotent: repeat calls are ignored rather than
    /// discarding progress, so callers that fire on every display state emission do not need to
    /// guard it, and the instance can never be left half-reset.
    func arm() {
        guard !isArmed else { return }

        isArmed = true
        samples.removeAll()
        hasReportedDegenerate = false
        hasReportedViewportDependent = false
    }

    func onHeightReported(_ height: CGFloat) -> ModalSizeVerdict {
        guard isArmed else { return .apply }

        samples.append(Sample(height: height, timestamp: now()))
        if samples.count > sampleCount {
            samples.removeFirst(samples.count - sampleCount)
        }

        if !hasReportedDegenerate, isCollapsed {
            return .degenerate
        }

        if !hasReportedViewportDependent, let delta = constantGrowthDelta {
            return .viewportDependent(delta: delta)
        }

        return .apply
    }

    /// Confirms the caller acted on `.degenerate` so it is not reported again. Kept separate from
    /// `onHeightReported` so a verdict the caller cannot act on yet does not silently disable the
    /// guard.
    func onDegenerateHandled() {
        hasReportedDegenerate = true
    }

    /// Confirms the caller acted on `.viewportDependent` so it is not reported again.
    func onViewportDependentHandled() {
        hasReportedViewportDependent = true
    }

    /// True when every recent report is too small to show anything *and* they span enough time to
    /// rule out a transient.
    ///
    /// Both conditions matter. `sizeChanged` arrives multiple times, and the renderer also reports on
    /// every window resize, so a burst of collapsed reports can arrive within milliseconds while the
    /// message is merely still being laid out.
    private var isCollapsed: Bool {
        guard samples.count >= sampleCount,
              let first = samples.first,
              let last = samples.last else { return false }
        guard samples.allSatisfy({ $0.height <= degenerateMaxPoints }) else { return false }

        return last.timestamp - first.timestamp >= degenerateMinElapsed
    }

    /// The shared delta when recent reports grow by the same positive amount each time, otherwise
    /// nil. A message whose height legitimately settles while images and fonts load grows by
    /// irregular amounts, so requiring a constant delta avoids flagging it.
    private var constantGrowthDelta: CGFloat? {
        guard samples.count >= sampleCount, samples.count >= Self.minSamplesForGrowth else {
            return nil
        }

        let first = samples[1].height - samples[0].height
        guard first > 0 else { return nil }

        for index in 2 ..< samples.count {
            let delta = samples[index].height - samples[index - 1].height
            if abs(delta - first) > Self.deltaTolerance { return nil }
        }
        return first
    }

    private struct Sample {
        let height: CGFloat
        let timestamp: TimeInterval
    }
}
