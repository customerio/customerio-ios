#if os(iOS)
import ActivityKit
import CioLiveActivities_Attributes
import Foundation

/// `ActivityAttributes` for the Customer.io **Segments** Live Activity template.
///
/// The Segments template shows a status headline with a discrete, multi-step progress bar — the
/// kind of "step N of M" indicator used for order/preparation/delivery flows. You register this
/// type with the SDK and render it with ``CIOSegmentsLiveActivity``; the SDK handles push tokens,
/// lifecycle reporting, and (because this type conforms to `CIOActivityAttribute`) remote
/// push-to-start.
///
/// Add this one source file to **both** your app target and your widget extension target. Visual
/// styling (colors, logo) is not carried here — it is supplied locally to the widget via
/// ``CIOSegmentsBranding``. Everything on this type is content: ``header`` is fixed for the life of
/// the activity, and ``ContentState`` is what you change on every update.
@available(iOS 16.2, *)
public struct CIOSegmentsAttributes: CIOActivityTemplate {
    /// Reverse-DNS identifier registered with the SDK and matched server-side to route pushes.
    public static let identifier = "io.customer.livenotifications.segments"

    // MARK: - Static attributes (set once at start, immutable for the activity)

    /// SDK/backend-managed correlation id. Declared with a default and never set by you — the SDK
    /// fills it in on local `start`, the backend fills it in for push-to-start.
    public var cioInstanceId: String = ""

    /// Top-row label shown next to the logo (e.g. a brand or order label). Rendered verbatim and
    /// fixed for the life of the activity.
    public var header: String

    public init(header: String) {
        self.header = header
    }

    // MARK: - Dynamic content state (change on every update / push)

    /// The parts of the activity that change as it progresses.
    public struct ContentState: Codable, Hashable, Sendable, CIOMetadataCarrying {
        /// Primary status line, e.g. `"Preparing your order"`. Rendered verbatim.
        public var status: String
        /// Optional secondary line under the status. Rendered verbatim.
        public var substatus: String?
        /// Total number of segments in the progress bar.
        public var segmentsTotal: Int
        /// Number of segments rendered in the "complete" color (the rest use the "incomplete"
        /// color). Clamped to `0...segmentsTotal` at render time.
        public var segmentsComplete: Int
        /// Optional short text shown on the Dynamic Island trailing edge (e.g. `"5 min"`).
        public var trailingText: String?
        /// Customer.io delivery + deep-link metadata for the push that produced this state.
        /// `nil` for a locally-driven update (no push to attribute).
        public var cioMetadata: CIOLiveActivityMetadata?

        public init(
            status: String,
            substatus: String? = nil,
            segmentsTotal: Int,
            segmentsComplete: Int,
            trailingText: String? = nil,
            cioMetadata: CIOLiveActivityMetadata? = nil
        ) {
            self.status = status
            self.substatus = substatus
            self.segmentsTotal = segmentsTotal
            self.segmentsComplete = segmentsComplete
            self.trailingText = trailingText
            self.cioMetadata = cioMetadata
        }

        /// `segmentsComplete` clamped into `0...segmentsTotal` so a malformed push can never draw an
        /// out-of-range or negative number of filled segments.
        var clampedComplete: Int {
            min(max(segmentsComplete, 0), max(segmentsTotal, 0))
        }
    }
}
#endif
