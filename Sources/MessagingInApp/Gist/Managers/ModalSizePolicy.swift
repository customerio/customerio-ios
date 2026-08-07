import CoreGraphics
import Foundation

/// Outcome of inspecting a height reported by the message renderer for a modal message.
enum ModalSizeVerdict: Equatable {
    /// Height looks sane; apply it as usual.
    case apply(height: CGFloat)

    /// Height has stayed collapsed for `ModalSizePolicy.sampleCount` consecutive reports, so the
    /// message can never become visible. The modal is still on screen blocking touches, so the
    /// caller is expected to fail the message rather than keep waiting.
    case degenerate

    /// Reported height is growing by a constant amount per report, which means the message sizes
    /// itself from the WebView height that the SDK derives from it. The height is still applied
    /// (the container clamps it), but the caller should surface the cause once.
    case viewportDependent(height: CGFloat, delta: CGFloat)
}

/// Detects message HTML whose height cannot be resolved by the SDK's content-sizing contract.
///
/// The renderer reports the message's content height roughly once per second and the SDK sizes the
/// WebView to it. When the message CSS instead derives its own height from the viewport (for
/// example `height: 100vh` or `height: 100%` on `html`/`body`) the two are mutually recursive and
/// there is no useful fixed point:
///
/// - reported == container: every value is a fixed point, including zero. The WebView starts at
///   zero, so the message stays collapsed behind a full screen, touch blocking overlay.
/// - reported == container + constant: the height grows by that constant on every report until the
///   container clamps it, and the message renders at full screen with its content pinned to the top.
///
/// Deliberately free of UIKit so the decision logic can be unit tested directly. Used only for
/// modal messages: inline messages legitimately report a zero height to collapse themselves.
class ModalSizePolicy {
    /// Heights at or below this are treated as collapsed. No message can render usable content in
    /// this space, and it covers the values seen in the field: zero, and the few points left by a
    /// collapsed default body margin.
    static let degenerateMaxPoints: CGFloat = 20

    /// Reports needed before a verdict is returned. The renderer reports about once per second.
    static let sampleCount: Int = 4

    /// Growth deltas are compared with a small tolerance because reported heights are rounded from
    /// CSS pixels.
    private static let deltaTolerance: CGFloat = 0.5

    private let degenerateMaxPoints: CGFloat
    private let sampleCount: Int

    private var samples: [CGFloat] = []

    /// Heights reported before the message is displayed are not evaluated: the WebView is still
    /// detached and legitimately measures zero while it loads.
    private var isArmed = false
    private var hasReportedDegenerate = false
    private var hasReportedViewportDependent = false

    init(
        degenerateMaxPoints: CGFloat = ModalSizePolicy.degenerateMaxPoints,
        sampleCount: Int = ModalSizePolicy.sampleCount
    ) {
        self.degenerateMaxPoints = degenerateMaxPoints
        self.sampleCount = sampleCount
    }

    /// Starts evaluating reported heights. Called once the message is displayed.
    func arm() {
        isArmed = true
        samples.removeAll()
    }

    func onHeightReported(_ height: CGFloat) -> ModalSizeVerdict {
        guard isArmed else { return .apply(height: height) }

        samples.append(height)
        if samples.count > sampleCount {
            samples.removeFirst(samples.count - sampleCount)
        }

        if !hasReportedDegenerate, isCollapsed {
            hasReportedDegenerate = true
            return .degenerate
        }

        if !hasReportedViewportDependent, let delta = constantGrowthDelta {
            hasReportedViewportDependent = true
            return .viewportDependent(height: height, delta: delta)
        }

        return .apply(height: height)
    }

    /// True when every recent report is too small to show anything. A single small report is not
    /// enough: a multi step message can momentarily measure small while switching steps.
    private var isCollapsed: Bool {
        samples.count >= sampleCount && samples.allSatisfy { $0 <= degenerateMaxPoints }
    }

    /// The shared delta when recent reports grow by the same positive amount each time, otherwise
    /// nil. A message whose height legitimately settles while images and fonts load grows by
    /// irregular amounts, so requiring a constant delta avoids flagging it.
    private var constantGrowthDelta: CGFloat? {
        guard samples.count >= sampleCount else { return nil }

        let first = samples[1] - samples[0]
        guard first > 0 else { return nil }

        for index in 2 ..< samples.count {
            let delta = samples[index] - samples[index - 1]
            if abs(delta - first) > Self.deltaTolerance { return nil }
        }
        return first
    }
}
