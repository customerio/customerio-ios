import CioLiveActivities_Attributes
import Foundation

#if os(iOS)
import ActivityKit

/// Attributes for the Auction Bid template.
///
/// Tracks a live auction with current bid, countdown, and a freeform status message
/// (winning / outbid / ended) whose accent color is driven by `statusColor`.
///
/// Text fields (`header`, `title`, `subtitle`, `statusMessage`) are freeform slots rendered
/// verbatim; the SDK never composes them.
@available(iOS 17.2, *)
public struct CIOAuctionBidAttributes: CIOActivityAttribute {
    public static let identifier = "io.customer.liveactivities.auctionbid"

    // MARK: - Static attributes

    public var activityInstanceId: String
    /// Optional top line, e.g. a brand or auction house label. Rendered verbatim.
    public var header: String?
    /// Display name of the item being auctioned. Rendered verbatim.
    public var title: String
    /// Asset reference for the item image (bundle name / asset key / URL), resolved via `CIOAssetLibrary`.
    public var image: String?
    /// Currency symbol shown alongside bid amounts e.g. `"$"`, `"£"`.
    public var currencySymbol: String

    public init(
        activityInstanceId: String,
        header: String? = nil,
        title: String,
        image: String? = nil,
        currencySymbol: String = "$"
    ) {
        self.activityInstanceId = activityInstanceId
        self.header = header
        self.title = title
        self.image = image
        self.currencySymbol = currencySymbol
    }

    // MARK: - Dynamic content state

    public struct ContentState: Codable, Hashable, Sendable {
        /// Current highest bid, pre-formatted without currency symbol e.g. `"1,250"`.
        public var currentBid: String
        /// Optional secondary line, e.g. `"47 bids"` or your standing bid. Rendered verbatim.
        public var subtitle: String?
        /// Status label e.g. `"You're winning"`, `"You've been outbid"`, `"Auction ended"`. Rendered verbatim.
        public var statusMessage: String
        /// Auction end time, used to render a live countdown.
        public var endTime: EpochMillisDate
        /// Hex color (e.g. `"#34C759"`) applied to the status message. `nil` uses the template tint.
        public var statusColor: String?
        /// Message shown when the activity becomes stale.
        public var staleMessage: String?

        public init(
            currentBid: String,
            subtitle: String? = nil,
            statusMessage: String,
            endTime: EpochMillisDate,
            statusColor: String? = nil,
            staleMessage: String? = nil
        ) {
            self.currentBid = currentBid
            self.subtitle = subtitle
            self.statusMessage = statusMessage
            self.endTime = endTime
            self.statusColor = statusColor
            self.staleMessage = staleMessage
        }
    }
}
#endif
