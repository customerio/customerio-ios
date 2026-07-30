#if os(iOS)
import ActivityKit
import CioLiveActivities_Attributes
import Foundation

/// `ActivityAttributes` for the Customer.io **Countdown Timer** Live Activity template.
///
/// Shows a status headline with a large, live-updating countdown to a target time — the kind used
/// for sales/drops, auctions, appointment windows, or "starts in …" moments. Register this type
/// with the SDK and render it with ``CIOCountdownTimerLiveActivity``; the SDK handles push tokens,
/// lifecycle reporting, and (via `CIOActivityAttribute`) remote push-to-start.
///
/// Add this one source file to **both** your app target and your widget extension target. Visual
/// styling (colors, logo) is supplied locally to the widget via ``CIOCountdownTimerBranding`` —
/// everything on this type is content: ``header`` is fixed for the activity, and ``ContentState``
/// is what you change on every update.
@available(iOS 16.2, *)
public struct CIOCountdownTimerAttributes: CIOActivityTemplate {
    /// Reverse-DNS identifier registered with the SDK and matched server-side to route pushes.
    public static let identifier = "io.customer.livenotifications.countdowntimer"

    // MARK: - Static attributes (set once at start, immutable for the activity)

    /// SDK/backend-managed correlation id. Declared with a default and never set by you — the SDK
    /// fills it in on local `start`, the backend fills it in for push-to-start.
    public var cioInstanceId: String = ""

    /// Top-row label shown next to the logo (e.g. a brand or campaign label). Rendered verbatim and
    /// fixed for the life of the activity.
    public var header: String

    public init(header: String) {
        self.header = header
    }

    // MARK: - Dynamic content state (change on every update / push)

    /// The parts of the activity that change as it counts down.
    public struct ContentState: Codable, Hashable, Sendable, CIOMetadataCarrying {
        /// Primary status line, e.g. `"Flash sale ends in"` or, when finished, `"Done"`. Rendered verbatim.
        public var title: String
        /// Optional secondary line under the title. Rendered verbatim.
        public var statusMessage: String?
        /// Target time for the countdown. While it is in the future, the template renders a live
        /// countdown; if absent (or already past) at render time, no timer is shown.
        ///
        /// > Important: the countdown does not vanish on its own when it reaches zero — a Live
        /// > Activity view isn't re-evaluated per second, so the clock rests at "0:00". Drive the
        /// > finished state by **pushing** a new content-state with a "done" `title`/`statusMessage`
        /// > and no `endTime`.
        public var endTime: EpochSecondsDate?
        /// Customer.io delivery + deep-link metadata for the push that produced this state.
        /// `nil` for a locally-driven update (no push to attribute).
        public var cioMetadata: CIOLiveActivityMetadata?

        public init(
            title: String,
            statusMessage: String? = nil,
            endTime: EpochSecondsDate? = nil,
            cioMetadata: CIOLiveActivityMetadata? = nil
        ) {
            self.title = title
            self.statusMessage = statusMessage
            self.endTime = endTime
            self.cioMetadata = cioMetadata
        }
    }
}
#endif
