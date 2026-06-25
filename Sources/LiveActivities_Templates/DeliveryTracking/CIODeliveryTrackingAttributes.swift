import CioLiveActivities_Attributes
import Foundation

#if os(iOS)
import ActivityKit

/// Attributes for the Delivery Tracking template.
///
/// Tracks an order from dispatch through delivery with step-based progress
/// and an estimated arrival countdown. `statusImageKey` in `ContentState`
/// is the primary demonstration of dynamic asset library usage — pre-load
/// one image per delivery stage (e.g. `"delivery-warehouse"`, `"delivery-truck"`,
/// `"delivery-door"`) and push the relevant key as status changes.
@available(iOS 17.2, *)
public struct CIODeliveryTrackingAttributes: CIOActivityAttribute {

    public static let identifier = "io.customer.liveactivities.deliverytracking"

    // MARK: - Static attributes

    public var activityInstanceId: String
    public var branding: CIOActivityBranding
    public var orderId: String
    public var recipientName: String?

    public init(
        activityInstanceId: String,
        branding: CIOActivityBranding,
        orderId: String,
        recipientName: String? = nil
    ) {
        self.activityInstanceId = activityInstanceId
        self.branding = branding
        self.orderId = orderId
        self.recipientName = recipientName
    }

    // MARK: - Dynamic content state

    public struct ContentState: Codable, Hashable, Sendable {
        /// Human-readable status label e.g. `"Your order is out for delivery"`.
        public var statusMessage: String
        /// AssetKey for the status illustration. Pre-load all stage images at
        /// SDK configure time; push the appropriate key as the delivery progresses.
        public var statusImageKey: String?
        /// Current progress step (1-based).
        public var stepCurrent: Int
        /// Total number of progress steps.
        public var stepTotal: Int
        /// Estimated arrival time, used to render a live countdown.
        public var estimatedArrival: Date?
        /// Driver or courier name.
        public var driverName: String?
        /// Message shown when the activity becomes stale.
        public var staleMessage: String?

        public init(
            statusMessage: String,
            statusImageKey: String? = nil,
            stepCurrent: Int,
            stepTotal: Int,
            estimatedArrival: Date? = nil,
            driverName: String? = nil,
            staleMessage: String? = nil
        ) {
            self.statusMessage = statusMessage
            self.statusImageKey = statusImageKey
            self.stepCurrent = stepCurrent
            self.stepTotal = stepTotal
            self.estimatedArrival = estimatedArrival
            self.driverName = driverName
            self.staleMessage = staleMessage
        }
    }
}
#endif
