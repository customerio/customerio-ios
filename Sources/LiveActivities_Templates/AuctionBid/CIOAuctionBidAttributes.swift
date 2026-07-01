import CioLiveActivities_Attributes
import Foundation

#if os(iOS)
import ActivityKit

/// Attributes for the Auction Bid template.
///
/// Tracks a live auction with current bid, bid count, countdown, and
/// per-user standing (winning / outbid).
@available(iOS 17.2, *)
public struct CIOAuctionBidAttributes: CIOActivityAttribute {
    public static let identifier = "io.customer.liveactivities.auctionbid"

    // MARK: - Static attributes

    public var activityInstanceId: String
    public var branding: CIOActivityBranding
    /// Display name of the item being auctioned.
    public var itemTitle: String
    /// AssetKey for the item image, resolved via `CIOAssetLibrary`.
    public var itemImageKey: String?
    /// Currency symbol prepended to bid amounts e.g. `"$"`, `"£"`.
    public var currencySymbol: String

    public init(
        activityInstanceId: String,
        branding: CIOActivityBranding,
        itemTitle: String,
        itemImageKey: String? = nil,
        currencySymbol: String = "$"
    ) {
        self.activityInstanceId = activityInstanceId
        self.branding = branding
        self.itemTitle = itemTitle
        self.itemImageKey = itemImageKey
        self.currencySymbol = currencySymbol
    }

    // MARK: - Dynamic content state

    public struct ContentState: Codable, Hashable, Sendable {
        /// Current highest bid, pre-formatted without currency symbol e.g. `"1,250"`.
        public var currentBid: String
        public var bidCount: Int
        /// Auction end time, used to render a live countdown.
        public var endTime: Date
        /// Status label e.g. `"You're winning"`, `"You've been outbid"`, `"Auction ended"`.
        public var statusMessage: String
        /// Whether the viewing user currently holds the highest bid.
        public var isUserHighBidder: Bool
        /// The user's current standing bid, pre-formatted without currency symbol.
        public var userBidAmount: String?
        /// Message shown when the activity becomes stale.
        public var staleMessage: String?

        public init(
            currentBid: String,
            bidCount: Int,
            endTime: Date,
            statusMessage: String,
            isUserHighBidder: Bool = false,
            userBidAmount: String? = nil,
            staleMessage: String? = nil
        ) {
            self.currentBid = currentBid
            self.bidCount = bidCount
            self.endTime = endTime
            self.statusMessage = statusMessage
            self.isUserHighBidder = isUserHighBidder
            self.userBidAmount = userBidAmount
            self.staleMessage = staleMessage
        }
    }
}
#endif
