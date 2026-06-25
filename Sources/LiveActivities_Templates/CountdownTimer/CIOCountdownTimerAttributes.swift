import CioLiveActivities_Attributes
import Foundation

#if os(iOS)
import ActivityKit

/// Attributes for the Countdown Timer template.
///
/// Displays a live countdown to a target date with a hero image and
/// configurable messaging. Supports a post-expiry state via `expiredMessage`.
@available(iOS 17.2, *)
public struct CIOCountdownTimerAttributes: CIOActivityAttribute {

    public static let identifier = "io.customer.liveactivities.countdowntimer"

    // MARK: - Static attributes

    public var activityInstanceId: String
    public var branding: CIOActivityBranding
    /// Primary title displayed above the countdown e.g. `"Flash Sale"`.
    public var title: String
    /// AssetKey for a hero or background image.
    public var heroImageKey: String?

    public init(
        activityInstanceId: String,
        branding: CIOActivityBranding,
        title: String,
        heroImageKey: String? = nil
    ) {
        self.activityInstanceId = activityInstanceId
        self.branding = branding
        self.title = title
        self.heroImageKey = heroImageKey
    }

    // MARK: - Dynamic content state

    public struct ContentState: Codable, Hashable, Sendable {
        /// The countdown target. Dynamic so the deadline can be extended via push.
        public var targetDate: Date
        /// Label displayed above the timer e.g. `"Sale starts in"`.
        public var statusMessage: String
        /// Replaces the countdown once `targetDate` has passed e.g. `"Sale is live!"`.
        /// `nil` hides the activity post-expiry.
        public var expiredMessage: String?
        /// Message shown when the activity becomes stale.
        public var staleMessage: String?

        public init(
            targetDate: Date,
            statusMessage: String,
            expiredMessage: String? = nil,
            staleMessage: String? = nil
        ) {
            self.targetDate = targetDate
            self.statusMessage = statusMessage
            self.expiredMessage = expiredMessage
            self.staleMessage = staleMessage
        }
    }
}
#endif
