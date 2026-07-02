import CioLiveActivities_Attributes
import Foundation

#if os(iOS)
import ActivityKit

/// Attributes for the Delivery Tracking template.
///
/// Tracks an order from dispatch through delivery with step-based progress
/// and an estimated arrival countdown. `image` in `ContentState` is the primary
/// demonstration of dynamic asset library usage — pre-load one image per delivery
/// stage (e.g. `"delivery-warehouse"`, `"delivery-truck"`, `"delivery-door"`) and
/// push the relevant asset reference as status changes.
///
/// Text fields (`header`, `title`, `subtitle`) are freeform slots rendered verbatim;
/// the SDK never composes them.
@available(iOS 17.2, *)
public struct CIODeliveryTrackingAttributes: CIOActivityAttribute {
    public static let identifier = "io.customer.liveactivities.deliverytracking"

    // MARK: - Static attributes

    public var activityInstanceId: String
    /// Optional top line, e.g. a brand or order label. Rendered verbatim.
    public var header: String?

    public init(
        activityInstanceId: String,
        header: String? = nil
    ) {
        self.activityInstanceId = activityInstanceId
        self.header = header
    }

    // MARK: - Nested types

    /// Step-based delivery progress.
    public struct Progress: Codable, Hashable, Sendable {
        /// Current progress step (1-based).
        public var current: Int
        /// Total number of progress steps.
        public var total: Int

        public init(current: Int, total: Int) {
            self.current = current
            self.total = total
        }
    }

    // MARK: - Dynamic content state

    public struct ContentState: Codable, Hashable, Sendable {
        /// Primary status line, e.g. `"Your order is out for delivery"`. Rendered verbatim.
        public var title: String
        /// Optional secondary line, e.g. recipient / driver / detail. Rendered verbatim.
        public var subtitle: String?
        /// Asset reference for the status illustration (bundle name / asset key / URL),
        /// resolved via `CIOAssetLibrary`. Pre-load stage images at configure time.
        public var image: String?
        /// Step-based delivery progress.
        public var progress: Progress
        /// Estimated arrival time, used to render a live countdown.
        public var estimatedArrival: EpochMillisDate?
        /// Hex color (e.g. `"#34C759"`) applied to status accents. `nil` uses the template tint.
        public var statusColor: String?
        /// Message shown when the activity becomes stale.
        public var staleMessage: String?

        public init(
            title: String,
            subtitle: String? = nil,
            image: String? = nil,
            progress: Progress,
            estimatedArrival: EpochMillisDate? = nil,
            statusColor: String? = nil,
            staleMessage: String? = nil
        ) {
            self.title = title
            self.subtitle = subtitle
            self.image = image
            self.progress = progress
            self.estimatedArrival = estimatedArrival
            self.statusColor = statusColor
            self.staleMessage = staleMessage
        }
    }
}
#endif
